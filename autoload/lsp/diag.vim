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
  # Signs used for LSP diagnostics
  hlset([{name: 'LspDiagLine', default: true, linksto: 'DiffAdd'}])
  hlset([{name: 'LspDiagSignErrorText', default: true, linksto: 'ErrorMsg'}])
  hlset([{name: 'LspDiagSignWarningText', default: true, linksto: 'Search'}])
  hlset([{name: 'LspDiagSignInfoText', default: true, linksto: 'Pmenu'}])
  hlset([{name: 'LspDiagSignHintText', default: true, linksto: 'Question'}])
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

  if opt.lspOptions.highlightDiagInline
    hlset([{name: 'LspDiagInlineError', default: true, linksto: 'SpellBad'}])
    hlset([{name: 'LspDiagInlineWarning', default: true, linksto: 'SpellCap'}])
    hlset([{name: 'LspDiagInlineInfo', default: true, linksto: 'SpellRare'}])
    hlset([{name: 'LspDiagInlineHint', default: true, linksto: 'SpellLocal'}])
    prop_type_add('LspDiagInlineError',
			{ highlight: 'LspDiagInlineError' })
    prop_type_add('LspDiagInlineWarning',
			{ highlight: 'LspDiagInlineWarning' })
    prop_type_add('LspDiagInlineInfo',
			{ highlight: 'LspDiagInlineInfo' })
    prop_type_add('LspDiagInlineHint',
			{ highlight: 'LspDiagInlineHint' })
  endif

  if opt.lspOptions.showDiagWithVirtualText
    hlset([{name: 'LspDiagVirtualText', default: true, linksto: 'LineNr'}])
    prop_type_add('LspDiagVirtualText', {highlight: 'LspDiagVirtualText',
					 override: true})
  endif
enddef

# Sort diagnostics ascending based on line and character offset
def SortDiags(diags: list<dict<any>>): list<dict<any>>
  return diags->sort((a, b) => {
    var linediff = a.range.start.line - b.range.start.line
    if linediff == 0
      return a.range.start.character - b.range.start.character
    endif
    return linediff
  })
enddef

# Remove the diagnostics stored for buffer 'bnr'
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

# Refresh the placed diagnostics in buffer 'bnr'
# This inline signs, inline props, and virtual text diagnostics
def DiagsRefresh(bnr: number)
  bnr->bufload()
  # Remove all the existing diagnostic signs
  sign_unplace('LSPDiag', {buffer: bnr})

  if opt.lspOptions.showDiagWithVirtualText
    # Remove all the existing virtual text
    prop_remove({type: 'LspDiagVirtualText', bufnr: bnr, all: true})
  endif

  if opt.lspOptions.highlightDiagInline
    # Remove all the existing virtual text
    prop_remove({type: 'LspDiagInlineError', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagInlineWarning', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagInlineInfo', bufnr: bnr, all: true})
    prop_remove({type: 'LspDiagInlineHint', bufnr: bnr, all: true})
  endif

  if !diagsMap->has_key(bnr) ||
      diagsMap[bnr].sortedDiagnostics->empty()
    return
  endif

  var signs: list<dict<any>> = []
  var diags: list<dict<any>> = diagsMap[bnr].sortedDiagnostics
  for diag in diags
    # TODO: prioritize most important severity if there are multiple diagnostics
    # from the same line
    var lnum = diag.range.start.line + 1
    signs->add({id: 0, buffer: bnr, group: 'LSPDiag',
				lnum: lnum,
				name: DiagSevToSignName(diag.severity)})

    try
      if opt.lspOptions.highlightDiagInline
        prop_add(diag.range.start.line + 1,
                  util.GetLineByteFromPos(bnr, diag.range.start) + 1,
                  {end_lnum: diag.range.end.line + 1,
                    end_col: util.GetLineByteFromPos(bnr, diag.range.end) + 1,
                    bufnr: bnr,
                    type: DiagSevToInlineHLName(diag.severity)})
      endif

      if opt.lspOptions.showDiagWithVirtualText
        var padding = diag.range.start.character
        if padding > 0
          padding = strdisplaywidth(getline(diag.range.start.line + 1)[ : diag.range.start.character - 1])
        endif
        prop_add(lnum, 0, {bufnr: bnr,
                           type: 'LspDiagVirtualText',
                           text: $'┌─ {diag.message}',
                           text_align: 'above',
                           text_padding_left: padding})
      endif
    catch /E966\|E964/ # Invalid lnum | Invalid col
      # Diagnostics arrive asynchronous and the document changed while they wore
      # send. Ignore this as new once will arrive shortly.
    endtry
  endfor

  signs->sign_placelist()
enddef

# New LSP diagnostic messages received from the server for a file.
# Update the signs placed in the buffer for this file
export def ProcessNewDiags(bnr: number)
  if opt.lspOptions.autoPopulateDiags
    DiagsUpdateLocList(bnr)
  endif

  if !opt.lspOptions.autoHighlightDiags
    return
  endif

  if bnr == -1 || !diagsMap->has_key(bnr)
    return
  endif

  var curmode: string = mode()
  if curmode == 'i' || curmode == 'R' || curmode == 'Rv'
    # postpone placing signs in insert mode and replace mode. These will be
    # placed after the user returns to Normal mode.
    b:LspDiagsUpdatePending = true
    return
  endif

  DiagsRefresh(bnr)
enddef

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
export def DiagNotification(lspserver: dict<any>, uri: string, newDiags: list<dict<any>>): void
  # Diagnostics are disabled for this server
  if lspserver.features->has_key('diagnostics') && !lspserver.features.diagnostics
    return
  endif

  var fname: string = util.LspUriToFile(uri)
  var bnr: number = fname->bufnr()
  if bnr == -1
    # Is this condition possible?
    return
  endif

  # TODO: Is the buffer (bnr) always a loaded buffer? Should we load it here?
  var lastlnum: number = bnr->getbufinfo()[0].linecount

  # store the diagnostic for each line separately
  var diagsByLnum: dict<list<dict<any>>> = {}

  var diagWithinRange: list<dict<any>> = []
  for diag in newDiags
    if diag.range.start.line + 1 > lastlnum
      # Make sure the line number is a valid buffer line number
      diag.range.start.line = lastlnum - 1
    endif

    var lnum = diag.range.start.line + 1
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
    for diag in diags
      joinedServerDiags->add(diag)
    endfor
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
export def DiagsGetErrorCount(): dict<number>
  var errCount = 0
  var warnCount = 0
  var infoCount = 0
  var hintCount = 0

  var bnr: number = bufnr()
  if diagsMap->has_key(bnr)
    var diags = diagsMap[bnr].sortedDiagnostics
    for diag in diags
      var severity = diag->get('severity', -1)
      if severity == 1
	errCount += 1
      elseif severity == 2
	warnCount += 1
      elseif severity == 3
	infoCount += 1
      elseif severity == 4
	hintCount += 1
      endif
    endfor
  endif

  return {Error: errCount, Warn: warnCount, Info: infoCount, Hint: hintCount}
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
def DiagsUpdateLocList(bnr: number): bool
  var fname: string = bnr->bufname()->fnamemodify(':p')
  if fname == ''
    return false
  endif

  var LspQfId: number = bnr->getbufvar('LspQfId', 0)
  if !LspQfId->empty() && getloclist(0, {id: LspQfId}).id != LspQfId
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
    text = diag.message->substitute("\n\\+", "\n", 'g')
    qflist->add({filename: fname,
		    lnum: diag.range.start.line + 1,
		    col: util.GetLineByteFromPos(bnr, diag.range.start) + 1,
		    end_lnum: diag.range.end.line + 1,
                    end_col: util.GetLineByteFromPos(bnr, diag.range.end) + 1,
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
  if !DiagsUpdateLocList(bufnr())
    util.WarnMsg($'No diagnostic messages found for {@%}')
    return
  endif

  :lopen
enddef

# Display the message of 'diag' in a popup window right below the position in
# the diagnostic message.
def ShowDiagInPopup(diag: dict<any>)
  var dlnum = diag.range.start.line + 1
  var ltext = dlnum->getline()
  var dlcol = ltext->byteidx(diag.range.start.character + 1)

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

# Display the 'diag' message in a popup or in the status message area
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
export def ShowCurrentDiagInStatusLine()
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
    var msgNoLineBreak = code .. substitute(substitute(diag.message, "\n", ' ', ''), "\\n", ' ', '')
    :echo msgNoLineBreak[ : max_width]
  else
    :echo ''
  endif
enddef

# Get the diagnostic from the LSP server for a particular line and character
# offset in a file
export def GetDiagByPos(bnr: number, lnum: number, col: number,
			atPos: bool = false): dict<any>
  var diags_in_line = GetDiagsByLine(bnr, lnum)

  for diag in diags_in_line
    if atPos
      if col >= diag.range.start.character + 1 && col < diag.range.end.character + 1
        return diag
      endif
    elseif col <= diag.range.start.character + 1
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
    setcursorcharpos(diag.range.start.line + 1, diag.range.start.character + 1)
    if !opt.lspOptions.showDiagWithVirtualText
      :redraw
      DisplayDiag(diag)
    endif
enddef

# jump to the next/previous/first diagnostic message in the current buffer
export def LspDiagsJump(which: string, a_count: number = 0): void
  var fname: string = expand('%:p')
  if fname == ''
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
  for diag in (which == 'next' || which == 'here') ?
					diags : diags->copy()->reverse()
    var lnum = diag.range.start.line + 1
    var col = diag.range.start.character + 1
    if (which == 'next' && (lnum > curlnum || lnum == curlnum && col > curcol))
	  || (which == 'prev' && (lnum < curlnum || lnum == curlnum
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
  if which == 'next' && a_count > 1 && a_count != count
    JumpDiag(diags[-1])
    return
  endif

  # If [count] exceeded the previous diags
  if which == 'prev' && a_count > 1 && a_count != count
    JumpDiag(diags[0])
    return
  endif

  if which == 'here'
    util.WarnMsg('No more diagnostics found on this line')
  else
    util.WarnMsg('No more diagnostics found')
  endif
enddef

# Disable the LSP diagnostics highlighting in all the buffers
export def DiagsHighlightDisable()
  # turn off all diags highlight
  opt.lspOptions.autoHighlightDiags = false

  # Remove the diganostics virtual text in all the buffers.
  if opt.lspOptions.showDiagWithVirtualText
      || opt.lspOptions.highlightDiagInline
    for binfo in getbufinfo({bufloaded: true})
      # Remove all virtual text
      if opt.lspOptions.showDiagWithVirtualText
        prop_remove({type: 'LspDiagVirtualText', bufnr: binfo.bufnr, all: true})
      endif
      if opt.lspOptions.highlightDiagInline
        prop_remove({type: 'LspDiagInlineError', bufnr: binfo.bufnr, all: true})
        prop_remove({type: 'LspDiagInlineWarning', bufnr: binfo.bufnr, all: true})
        prop_remove({type: 'LspDiagInlineInfo', bufnr: binfo.bufnr, all: true})
        prop_remove({type: 'LspDiagInlineHint', bufnr: binfo.bufnr, all: true})
      endif
    endfor
  endif

  # Remove all the existing diagnostic signs in all the buffers
  sign_unplace('LSPDiag')
enddef

# Enable the LSP diagnostics highlighting
export def DiagsHighlightEnable()
  opt.lspOptions.autoHighlightDiags = true
  for binfo in getbufinfo({bufloaded: true})
    DiagsRefresh(binfo.bufnr)
    endif
  endfor
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
