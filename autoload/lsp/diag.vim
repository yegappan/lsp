vim9script

# Functions related to handling LSP diagnostics.

import './options.vim' as opt
import './buffer.vim' as buf
import './util.vim'

# [bnr] = {
#   serverDiagnostics: {
#     lspServer1Id: [diag, diag, diag]
#     lspServer2Id: [diag, diag, diag]
#   },
#   serverDiagnosticsByLnum: {
#     lspServer1Id: { [lnum]: [diag, diag diag] },
#     lspServer2Id: { [lnum]: [diag, diag diag] },
#   },
#   sortedDiagnostics: [lspServer1.diags, ...lspServer2.diags]->sort()
# }
var diagsMap: dict<dict<any>> = {}

# Initialize the signs and the text property type used for diagnostics.
export def InitOnce()
  # Signs and their highlight groups used for LSP diagnostics
  hlset([
    {name: 'LspDiagLine', default: true, linksto: 'NONE'},
    {name: 'LspDiagSignErrorText', default: true, linksto: 'ErrorMsg'},
    {name: 'LspDiagSignWarningText', default: true, linksto: 'Search'},
    {name: 'LspDiagSignInfoText', default: true, linksto: 'Pmenu'},
    {name: 'LspDiagSignHintText', default: true, linksto: 'Question'}
  ])
  sign_define([
    {
      name: 'LspDiagError',
      text: opt.lspOptions.diagSignErrorText,
      texthl: 'LspDiagSignErrorText',
      linehl: 'LspDiagLine'
    },
    {
      name: 'LspDiagWarning',
      text: opt.lspOptions.diagSignWarningText,
      texthl: 'LspDiagSignWarningText',
      linehl: 'LspDiagLine'
    },
    {
      name: 'LspDiagInfo',
      text: opt.lspOptions.diagSignInfoText,
      texthl: 'LspDiagSignInfoText',
      linehl: 'LspDiagLine'
    },
    {
      name: 'LspDiagHint',
      text: opt.lspOptions.diagSignHintText,
      texthl: 'LspDiagSignHintText',
      linehl: 'LspDiagLine'
    }
  ])

  # Diag inline highlight groups and text property types
  hlset([
    {name: 'LspDiagInlineError', default: true, linksto: 'SpellBad'},
    {name: 'LspDiagInlineWarning', default: true, linksto: 'SpellCap'},
    {name: 'LspDiagInlineInfo', default: true, linksto: 'SpellRare'},
    {name: 'LspDiagInlineHint', default: true, linksto: 'SpellLocal'}
  ])

  var override = &cursorline
      && &cursorlineopt =~ '\<line\>\|\<screenline\>\|\<both\>'

  prop_type_add('LspDiagInlineError',
		{highlight: 'LspDiagInlineError',
		 priority: 10,
		 override: override})
  prop_type_add('LspDiagInlineWarning',
		{highlight: 'LspDiagInlineWarning',
		 priority: 9,
		 override: override})
  prop_type_add('LspDiagInlineInfo',
		{highlight: 'LspDiagInlineInfo',
		 priority: 8,
		 override: override})
  prop_type_add('LspDiagInlineHint',
		{highlight: 'LspDiagInlineHint',
		 priority: 7,
		 override: override})

  # Diag virtual text highlight groups and text property types
  hlset([
    {name: 'LspDiagVirtualTextError', default: true, linksto: 'SpellBad'},
    {name: 'LspDiagVirtualTextWarning', default: true, linksto: 'SpellCap'},
    {name: 'LspDiagVirtualTextInfo', default: true, linksto: 'SpellRare'},
    {name: 'LspDiagVirtualTextHint', default: true, linksto: 'SpellLocal'},
  ])
  prop_type_add('LspDiagVirtualTextError',
		{highlight: 'LspDiagVirtualTextError', override: true})
  prop_type_add('LspDiagVirtualTextWarning',
		{highlight: 'LspDiagVirtualTextWarning', override: true})
  prop_type_add('LspDiagVirtualTextInfo',
		{highlight: 'LspDiagVirtualTextInfo', override: true})
  prop_type_add('LspDiagVirtualTextHint',
		{highlight: 'LspDiagVirtualTextHint', override: true})

  autocmd_add([{group: 'LspCmds',
	        event: 'User',
		pattern: 'LspOptionsChanged',
		cmd: 'LspDiagsOptionsChanged()'}])

  # ALE plugin support
  if opt.lspOptions.aleSupport
    opt.lspOptions.autoHighlightDiags = false
    autocmd_add([
      {
	group: 'LspAleCmds',
	event: 'User',
	pattern: 'ALEWantResults',
	cmd: 'AleHook(g:ale_want_results_buffer)'
      }
    ])
  endif
enddef

# Initialize the diagnostics features for the buffer 'bnr'
export def BufferInit(lspserver: dict<any>, bnr: number)
  if opt.lspOptions.showDiagInBalloon
    :set ballooneval balloonevalterm
    setbufvar(bnr, '&balloonexpr', 'g:LspDiagExpr()')
  endif

  var acmds: list<dict<any>> = []
  # Show diagnostics on the status line
  if opt.lspOptions.showDiagOnStatusLine
    acmds->add({bufnr: bnr,
		event: 'CursorMoved',
		group: 'LSPBufferAutocmds',
		cmd: 'ShowCurrentDiagInStatusLine()'})
  endif
  autocmd_add(acmds)
enddef

# Function to sort the diagnostics in ascending order based on the line and
# character offset
def DiagsSortFunc(a: dict<any>, b: dict<any>): number
  var a_start: dict<number> = a.range.start
  var b_start: dict<number> = b.range.start
  var linediff: number = a_start.line - b_start.line
  if linediff == 0
    return a_start.character - b_start.character
  endif
  return linediff
enddef

# Sort diagnostics ascending based on line and character offset
def SortDiags(diags: list<dict<any>>): list<dict<any>>
  return diags->sort(DiagsSortFunc)
enddef

# Remove the diagnostics stored for buffer "bnr"
export def DiagRemoveFile(bnr: number)
  if diagsMap->has_key(bnr)
    diagsMap->remove(bnr)
  endif
enddef

def DiagSevToSignName(severity: number): string
  var typeMap: list<string> = ['LspDiagError', 'LspDiagWarning',
						'LspDiagInfo', 'LspDiagHint']
  if severity > 4
    return 'LspDiagHint'
  endif
  return typeMap[severity - 1]
enddef

def DiagSevToInlineHLName(severity: number): string
  var typeMap: list<string> = [
    'LspDiagInlineError',
    'LspDiagInlineWarning',
    'LspDiagInlineInfo',
    'LspDiagInlineHint'
  ]
  if severity > 4
    return 'LspDiagInlineHint'
  endif
  return typeMap[severity - 1]
enddef

def DiagSevToVirtualTextHLName(severity: number): string
  var typeMap: list<string> = [
    'LspDiagVirtualTextError',
    'LspDiagVirtualTextWarning',
    'LspDiagVirtualTextInfo',
    'LspDiagVirtualTextHint'
  ]
  if severity > 4
    return 'LspDiagVirtualTextHint'
  endif
  return typeMap[severity - 1]
enddef

def DiagSevToSymbolText(severity: number): string
  var lspOpts = opt.lspOptions
  var typeMap: list<string> = [
    lspOpts.diagSignErrorText,
    lspOpts.diagSignWarningText,
    lspOpts.diagSignInfoText,
    lspOpts.diagSignHintText
  ]
  if severity > 4
    return lspOpts.diagSignHintText
  endif
  return typeMap[severity - 1]
enddef

# Remove signs and text properties for diagnostics in buffer
def RemoveDiagVisualsForBuffer(bnr: number, all: bool = false)
  var lspOpts = opt.lspOptions
  if lspOpts.showDiagWithSign || all
    # Remove all the existing diagnostic signs
    sign_unplace('LSPDiag', {buffer: bnr})
  endif

  if lspOpts.showDiagWithVirtualText || all
    # Remove all the existing virtual text
    prop_remove({type: 'LspDiagVirtualTextError', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagVirtualTextWarning', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagVirtualTextInfo', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagVirtualTextHint', bufnr: bnr, all: true})
  endif

  if lspOpts.highlightDiagInline || all
    # Remove all the existing virtual text
    prop_remove({type: 'LspDiagInlineError', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagInlineWarning', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagInlineInfo', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagInlineHint', bufnr: bnr, all: true})
  endif
enddef

# Refresh the placed diagnostics in buffer "bnr"
# This inline signs, inline props, and virtual text diagnostics
export def DiagsRefresh(bnr: number, all: bool = false)
  var lspOpts = opt.lspOptions
  if !lspOpts.autoHighlightDiags
    return
  endif

  :silent! bnr->bufload()

  RemoveDiagVisualsForBuffer(bnr, all)

  if !diagsMap->has_key(bnr) ||
      diagsMap[bnr].sortedDiagnostics->empty()
    return
  endif

  # Initialize default/fallback properties for diagnostic virtual text:
  var diag_align: string = 'above'
  var diag_wrap: string = 'truncate'
  var diag_symbol: string = '┌─'

  if lspOpts.diagVirtualTextAlign == 'below'
    diag_align = 'below'
    diag_wrap = 'truncate'
    diag_symbol = '└─'
  elseif lspOpts.diagVirtualTextAlign == 'after'
    diag_align = 'after'
    diag_wrap = 'wrap'
    diag_symbol = 'E>'
  endif

  if lspOpts.diagVirtualTextWrap != 'default'
    diag_wrap = lspOpts.diagVirtualTextWrap
  endif

  var signs: list<dict<any>> = []
  var diags: list<dict<any>> = diagsMap[bnr].sortedDiagnostics
  var inlineHLprops: list<list<list<number>>> = [[], [], [], [], []]
  for diag in diags
    # TODO: prioritize most important severity if there are multiple
    # diagnostics from the same line
    var d_range = diag.range
    var d_start = d_range.start
    var d_end = d_range.end
    var lnum = d_start.line + 1
    if lspOpts.showDiagWithSign
      signs->add({id: 0, buffer: bnr, group: 'LSPDiag',
		  lnum: lnum, name: DiagSevToSignName(diag.severity),
		  priority: 10 - diag.severity})
    endif

    try
      if lspOpts.highlightDiagInline
	var propLocation: list<number> = [
	  lnum, util.GetLineByteFromPos(bnr, d_start) + 1,
	  d_end.line + 1, util.GetLineByteFromPos(bnr, d_end) + 1
	]
	inlineHLprops[diag.severity]->add(propLocation)
      endif

      if lspOpts.showDiagWithVirtualText
        var padding: number
        var symbol: string = diag_symbol

        if diag_align == 'after'
          padding = 3
          symbol = DiagSevToSymbolText(diag.severity)
        else
	  var charIdx = util.GetCharIdxWithoutCompChar(bnr, d_start)
          padding = charIdx
          if padding > 0
            padding = strdisplaywidth(getline(lnum)[ : charIdx - 1])
          endif
        endif

        prop_add(lnum, 0, {bufnr: bnr,
			   type: DiagSevToVirtualTextHLName(diag.severity),
                           text: $'{symbol} {diag.message}',
                           text_align: diag_align,
                           text_wrap: diag_wrap,
                           text_padding_left: padding})
      endif
    catch /E966\|E964/ # Invalid lnum | Invalid col
      # Diagnostics arrive asynchronously and the document changed while they
      # were in transit. Ignore this as new once will arrive shortly.
    endtry
  endfor

  if lspOpts.highlightDiagInline
    for i in range(1, 4)
      if !inlineHLprops[i]->empty()
	try
	  prop_add_list({bufnr: bnr, type: DiagSevToInlineHLName(i)},
	    inlineHLprops[i])
	catch /E966\|E964/ # Invalid lnum | Invalid col
	endtry
      endif
    endfor
  endif

  if lspOpts.showDiagWithSign
    signs->sign_placelist()
  endif
enddef

# Sends diagnostics to Ale
def SendAleDiags(bnr: number, timerid: number)
  if !diagsMap->has_key(bnr)
    return
  endif

  # Convert to Ale's diagnostics format (:h ale-loclist-format)
  ale#other_source#ShowResults(bnr, 'lsp',
    diagsMap[bnr].sortedDiagnostics->mapnew((_, v) => {
     return {text: v.message,
             lnum: v.range.start.line + 1,
             col: util.GetLineByteFromPos(bnr, v.range.start) + 1,
             end_lnum: v.range.end.line + 1,
             end_col: util.GetLineByteFromPos(bnr, v.range.end) + 1,
             type: "EWIH"[v.severity - 1]}
    })
  )
enddef

# Hook called when Ale wants to retrieve new diagnostics
def AleHook(bnr: number)
  ale#other_source#StartChecking(bnr, 'lsp')
  timer_start(0, function('SendAleDiags', [bnr]))
enddef

# New LSP diagnostic messages received from the server for a file.
# Update the signs placed in the buffer for this file
export def ProcessNewDiags(bnr: number)
  DiagsUpdateLocList(bnr)

  var lspOpts = opt.lspOptions
  if lspOpts.aleSupport
    SendAleDiags(bnr, -1)
  endif

  if bnr == -1 || !diagsMap->has_key(bnr)
    return
  endif

  var curmode: string = mode()
  if curmode == 'i' || curmode == 'R' || curmode == 'Rv'
    # postpone placing signs in insert mode and replace mode. These will be
    # placed after the user returns to Normal mode.
    setbufvar(bnr, 'LspDiagsUpdatePending', true)
    return
  endif

  DiagsRefresh(bnr)
enddef

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
export def DiagNotification(lspserver: dict<any>, uri: string, diags_arg: list<dict<any>>): void
  # Diagnostics are disabled for this server?
  if !lspserver.featureEnabled('diagnostics')
    return
  endif

  var fname: string = util.LspUriToFile(uri)
  var bnr: number = fname->bufnr()
  if bnr == -1
    # Is this condition possible?
    return
  endif

  var newDiags: list<dict<any>> = diags_arg

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the diags
    newDiags->map((_, dval) => {
	lspserver.decodeRange(bnr, dval.range)
	return dval
      })
  endif

  if lspserver.processDiagHandler != null_function
    newDiags = lspserver.processDiagHandler(diags_arg)
  endif

  # TODO: Is the buffer (bnr) always a loaded buffer? Should we load it here?
  var lastlnum: number = bnr->getbufinfo()[0].linecount

  # store the diagnostic for each line separately
  var diagsByLnum: dict<list<dict<any>>> = {}

  var diagWithinRange: list<dict<any>> = []
  for diag in newDiags
    var d_start = diag.range.start
    if d_start.line + 1 > lastlnum
      # Make sure the line number is a valid buffer line number
      d_start.line = lastlnum - 1
    endif

    var lnum = d_start.line + 1
    if !diagsByLnum->has_key(lnum)
      diagsByLnum[lnum] = []
    endif
    diagsByLnum[lnum]->add(diag)

    diagWithinRange->add(diag)
  endfor

  var serverDiags: dict<list<any>> = diagsMap->has_key(bnr) ?
      diagsMap[bnr].serverDiagnostics : {}
  serverDiags[lspserver.id] = diagWithinRange

  var serverDiagsByLnum: dict<dict<list<any>>> = diagsMap->has_key(bnr) ?
      diagsMap[bnr].serverDiagnosticsByLnum : {}
  serverDiagsByLnum[lspserver.id] = diagsByLnum

  # store the diagnostic for each line separately
  var joinedServerDiags: list<dict<any>> = []
  for diags in serverDiags->values()
    joinedServerDiags->extend(diags)
  endfor

  var sortedDiags = SortDiags(joinedServerDiags)

  diagsMap[bnr] = {
    sortedDiagnostics: sortedDiags,
    serverDiagnosticsByLnum: serverDiagsByLnum,
    serverDiagnostics: serverDiags
  }

  ProcessNewDiags(bnr)

  # Notify user scripts that diags has been updated
  if exists('#User#LspDiagsUpdated')
    :doautocmd <nomodeline> User LspDiagsUpdated
  endif
enddef

# get the count of error in the current buffer
export def DiagsGetErrorCount(bnr: number): dict<number>
  var diagSevCount: list<number> = [0, 0, 0, 0, 0]
  if diagsMap->has_key(bnr)
    var diags = diagsMap[bnr].sortedDiagnostics
    for diag in diags
      var severity = diag->get('severity', 0)
      diagSevCount[severity] += 1
    endfor
  endif

  return {
    Error: diagSevCount[1],
    Warn: diagSevCount[2],
    Info: diagSevCount[3],
    Hint: diagSevCount[4]
  }
enddef

# Map the LSP DiagnosticSeverity to a quickfix type character
def DiagSevToQfType(severity: number): string
  var typeMap: list<string> = ['E', 'W', 'I', 'N']

  if severity > 4
    return ''
  endif

  return typeMap[severity - 1]
enddef

# Update the location list window for the current window with the diagnostic
# messages.
# Returns true if diagnostics is not empty and false if it is empty.
def DiagsUpdateLocList(bnr: number, calledByCmd: bool = false): bool
  var fname: string = bnr->bufname()->fnamemodify(':p')
  if fname->empty()
    return false
  endif

  var LspQfId: number = bnr->getbufvar('LspQfId', 0)
  if LspQfId == 0 && !opt.lspOptions.autoPopulateDiags && !calledByCmd
    # Diags location list is not present. Create the location list only if
    # the 'autoPopulateDiags' option is set or the ":LspDiag show" command is
    # invoked.
    return false
  endif

  if LspQfId != 0 && getloclist(0, {id: LspQfId}).id != LspQfId
    # Previously used location list for the diagnostics is gone
    LspQfId = 0
  endif

  if !diagsMap->has_key(bnr) ||
      diagsMap[bnr].sortedDiagnostics->empty()
    if LspQfId != 0
      setloclist(0, [], 'r', {id: LspQfId, items: []})
    endif
    return false
  endif

  var qflist: list<dict<any>> = []
  var text: string

  var diags = diagsMap[bnr].sortedDiagnostics
  for diag in diags
    var d_range = diag.range
    var d_start = d_range.start
    var d_end = d_range.end
    text = diag.message->substitute("\n\\+", "\n", 'g')
    qflist->add({filename: fname,
		    lnum: d_start.line + 1,
		    col: util.GetLineByteFromPos(bnr, d_start) + 1,
		    end_lnum: d_end.line + 1,
                    end_col: util.GetLineByteFromPos(bnr, d_end) + 1,
		    text: text,
		    type: DiagSevToQfType(diag.severity)})
  endfor

  var op: string = ' '
  var props = {title: 'Language Server Diagnostics', items: qflist}
  if LspQfId != 0
    op = 'r'
    props.id = LspQfId
  endif
  setloclist(0, [], op, props)
  if LspQfId == 0
    setbufvar(bnr, 'LspQfId', getloclist(0, {id: 0}).id)
  endif

  return true
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a location list
export def ShowAllDiags(): void
  var bnr: number = bufnr()
  if !DiagsUpdateLocList(bnr, true)
    util.WarnMsg($'No diagnostic messages found for {@%}')
    return
  endif

  var save_winid = win_getid()
  # make the diagnostics error list the active one and open it
  var LspQfId: number = bnr->getbufvar('LspQfId', 0)
  var LspQfNr: number = getloclist(0, {id: LspQfId, nr: 0}).nr
  exe $':{LspQfNr} lhistory'
  :lopen
  if !opt.lspOptions.keepFocusInDiags
    save_winid->win_gotoid()
  endif
enddef

# Display the message of "diag" in a popup window right below the position in
# the diagnostic message.
def ShowDiagInPopup(diag: dict<any>)
  var d_start = diag.range.start
  var dlnum = d_start.line + 1
  var ltext = dlnum->getline()
  var dlcol = ltext->byteidxcomp(d_start.character) + 1

  var lastline = line('$')
  if dlnum > lastline
    # The line number is outside the last line in the file.
    dlnum = lastline
  endif
  if dlcol < 1
    # The column is outside the last character in line.
    dlcol = ltext->len() + 1
  endif
  var d = screenpos(0, dlnum, dlcol)
  if d->empty()
    # If the diag position cannot be converted to Vim lnum/col, then use
    # the current cursor position
    d = {row: line('.'), col: col('.')}
  endif

  # Display a popup right below the diagnostics position
  var msg = diag.message->split("\n")
  var msglen = msg->reduce((acc, val) => max([acc, val->strcharlen()]), 0)

  var ppopts = {}
  ppopts.pos = 'topleft'
  ppopts.line = d.row + 1
  ppopts.moved = 'any'

  if msglen > &columns
    ppopts.wrap = true
    ppopts.col = 1
  else
    ppopts.wrap = false
    ppopts.col = d.col
  endif

  popup_create(msg, ppopts)
enddef

# Display the "diag" message in a popup or in the status message area
def DisplayDiag(diag: dict<any>)
  if opt.lspOptions.showDiagInPopup
    # Display the diagnostic message in a popup window.
    ShowDiagInPopup(diag)
  else
    # Display the diagnostic message in the status message area
    :echo diag.message
  endif
enddef

# Show the diagnostic message for the current line
export def ShowCurrentDiag(atPos: bool)
  var bnr: number = bufnr()
  var lnum: number = line('.')
  var col: number = charcol('.')
  var diag: dict<any> = GetDiagByPos(bnr, lnum, col, atPos)
  if diag->empty()
    util.WarnMsg($'No diagnostic messages found for current {atPos ? "position" : "line"}')
  else
    DisplayDiag(diag)
  endif
enddef

# Show the diagnostic message for the current line without linebreak
def ShowCurrentDiagInStatusLine()
  var bnr: number = bufnr()
  var lnum: number = line('.')
  var col: number = charcol('.')
  var diag: dict<any> = GetDiagByPos(bnr, lnum, col)
  if !diag->empty()
    # 15 is a enough length not to cause line break
    var max_width = &columns - 15
    var code = ''
    if diag->has_key('code')
      code = $'[{diag.code}] '
    endif
    var msgNoLineBreak = code ..
	diag.message->substitute("\n", ' ', '')->substitute("\\n", ' ', '')
    :echo msgNoLineBreak[ : max_width]
  else
    # clear the previous message
    :echo ''
  endif
enddef

# Get the diagnostic from the LSP server for a particular line and character
# offset in a file
export def GetDiagByPos(bnr: number, lnum: number, col: number,
			atPos: bool = false): dict<any>
  var diags_in_line = GetDiagsByLine(bnr, lnum)

  for diag in diags_in_line
    var r = diag.range
    var startCharIdx = util.GetCharIdxWithoutCompChar(bnr, r.start)
    var endCharIdx = util.GetCharIdxWithoutCompChar(bnr, r.end)
    if atPos
      if col >= startCharIdx + 1 && col < endCharIdx + 1
        return diag
      endif
    elseif col <= startCharIdx + 1
      return diag
    endif
  endfor

  # No diagnostic to the right of the position, return the last one instead
  if !atPos && diags_in_line->len() > 0
    return diags_in_line[-1]
  endif

  return {}
enddef

# Get all diagnostics from the LSP server for a particular line in a file
export def GetDiagsByLine(bnr: number, lnum: number, lspserver: dict<any> = null_dict): list<dict<any>>
  if !diagsMap->has_key(bnr)
    return []
  endif

  var diags: list<dict<any>> = []

  var serverDiagsByLnum = diagsMap[bnr].serverDiagnosticsByLnum

  if lspserver == null_dict
    for diagsByLnum in serverDiagsByLnum->values()
      if diagsByLnum->has_key(lnum)
        diags->extend(diagsByLnum[lnum])
      endif
    endfor
  else
    if !serverDiagsByLnum->has_key(lspserver.id)
      return []
    endif
    if serverDiagsByLnum[lspserver.id]->has_key(lnum)
      diags = serverDiagsByLnum[lspserver.id][lnum]
    endif
  endif

  return diags->sort((a, b) => {
    return a.range.start.character - b.range.start.character
  })
enddef

# Utility function to do the actual jump
def JumpDiag(diag: dict<any>)
  var startPos: dict<number> = diag.range.start
  setcursorcharpos(startPos.line + 1,
		   util.GetCharIdxWithoutCompChar(bufnr(), startPos) + 1)
  :normal! zv
  if !opt.lspOptions.showDiagWithVirtualText
    :redraw
    DisplayDiag(diag)
  endif
enddef

# jump to the next/previous/first diagnostic message in the current buffer
export def LspDiagsJump(which: string, a_count: number = 0): void
  var fname: string = expand('%:p')
  if fname->empty()
    return
  endif
  var bnr: number = bufnr()

  if !diagsMap->has_key(bnr) ||
      diagsMap[bnr].sortedDiagnostics->empty()
    util.WarnMsg($'No diagnostic messages found for {fname}')
    return
  endif

  var diags = diagsMap[bnr].sortedDiagnostics

  if which == 'first'
    JumpDiag(diags[0])
    return
  endif

  if which == 'last'
    JumpDiag(diags[-1])
    return
  endif

  # Find the entry just before the current line (binary search)
  var count = a_count > 1 ? a_count : 1
  var curlnum: number = line('.')
  var curcol: number = charcol('.')
  for diag in (which == 'next' || which == 'nextWrap' || which == 'here') ?
					diags : diags->copy()->reverse()
    var d_start = diag.range.start
    var lnum = d_start.line + 1
    var col = util.GetCharIdxWithoutCompChar(bnr, d_start) + 1
    if ((which == 'next' || which == 'nextWrap') && (lnum > curlnum || lnum == curlnum && col > curcol))
	  || ((which == 'prev' || which == 'prevWrap') && (lnum < curlnum || lnum == curlnum
							&& col < curcol))
	  || (which == 'here' && (lnum == curlnum && col >= curcol))

      # Skip over as many diags as "count" dictates
      count = count - 1
      if count > 0
        continue
      endif

      JumpDiag(diag)
      return
    endif
  endfor

  # If [count] exceeded the remaining diags
  if ((which == 'next' || which == 'nextWrap') && a_count > 1 && a_count != count)
    JumpDiag(diags[-1])
    return
  endif

  # If [count] exceeded the previous diags
  if ((which == 'prev' || which == 'prevWrap') && a_count > 1 && a_count != count)
    JumpDiag(diags[0])
    return
  endif

  if which == 'nextWrap' || which == 'prevWrap'
    JumpDiag(diags[which == 'nextWrap' ? 0 : -1])
    return
  endif

  if which == 'here'
    util.WarnMsg('No more diagnostics found on this line')
  else
    util.WarnMsg('No more diagnostics found')
  endif
enddef

# Return the sorted diagnostics for buffer "bnr".  Default is the current
# buffer.  A copy of the diagnostics is returned so that the caller can modify
# the diagnostics.
export def GetDiagsForBuf(bnr: number = bufnr()): list<dict<any>>
  if !diagsMap->has_key(bnr) ||
      diagsMap[bnr].sortedDiagnostics->empty()
    return []
  endif

  return diagsMap[bnr].sortedDiagnostics->deepcopy()
enddef

# Return the diagnostic text from the LSP server for the current mouse line to
# display in a balloon
def g:LspDiagExpr(): any
  if !opt.lspOptions.showDiagInBalloon
    return ''
  endif

  var diagsInfo: list<dict<any>> =
			GetDiagsByLine(v:beval_bufnr, v:beval_lnum)
  if diagsInfo->empty()
    # No diagnostic for the current cursor location
    return ''
  endif
  var diagFound: dict<any> = {}
  for diag in diagsInfo
    var r = diag.range
    var startcol = util.GetLineByteFromPos(v:beval_bufnr, r.start) + 1
    var endcol = util.GetLineByteFromPos(v:beval_bufnr, r.end) + 1
    if v:beval_col >= startcol && v:beval_col < endcol
      diagFound = diag
      break
    endif
  endfor
  if diagFound->empty()
    # mouse is outside of the diagnostics range
    return ''
  endif

  # return the found diagnostic
  return diagFound.message->split("\n")
enddef

# Track the current diagnostics auto highlight enabled/disabled state.  Used
# when the "autoHighlightDiags" option value is changed.
var save_autoHighlightDiags = opt.lspOptions.autoHighlightDiags
var save_highlightDiagInline = opt.lspOptions.highlightDiagInline
var save_showDiagWithSign = opt.lspOptions.showDiagWithSign
var save_showDiagWithVirtualText = opt.lspOptions.showDiagWithVirtualText

# Enable the LSP diagnostics highlighting
export def DiagsHighlightEnable()
  opt.lspOptions.autoHighlightDiags = true
  save_autoHighlightDiags = true
  for binfo in getbufinfo({bufloaded: true})
    if diagsMap->has_key(binfo.bufnr)
      DiagsRefresh(binfo.bufnr)
    endif
  endfor
enddef

# Disable the LSP diagnostics highlighting in all the buffers
export def DiagsHighlightDisable()
  # turn off all diags highlight
  opt.lspOptions.autoHighlightDiags = false
  save_autoHighlightDiags = false
  for binfo in getbufinfo()
    if diagsMap->has_key(binfo.bufnr)
      RemoveDiagVisualsForBuffer(binfo.bufnr)
    endif
  endfor
enddef

# Some options are changed.  If 'autoHighlightDiags' option is changed, then
# either enable or disable diags auto highlight.
export def LspDiagsOptionsChanged()
  if save_autoHighlightDiags && !opt.lspOptions.autoHighlightDiags
    DiagsHighlightDisable()
  elseif !save_autoHighlightDiags && opt.lspOptions.autoHighlightDiags
    DiagsHighlightEnable()
  endif

  if save_highlightDiagInline != opt.lspOptions.highlightDiagInline
    || save_showDiagWithSign != opt.lspOptions.showDiagWithSign
    || save_showDiagWithVirtualText != opt.lspOptions.showDiagWithVirtualText
    save_highlightDiagInline = opt.lspOptions.highlightDiagInline
    save_showDiagWithSign = opt.lspOptions.showDiagWithSign
    save_showDiagWithVirtualText = opt.lspOptions.showDiagWithVirtualText
    for binfo in getbufinfo({bufloaded: true})
      if diagsMap->has_key(binfo.bufnr)
	DiagsRefresh(binfo.bufnr, true)
      endif
    endfor
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
