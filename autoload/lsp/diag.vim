vim9script

# Functions related to handling LSP diagnostics.

import './options.vim' as opt
import './buffer.vim' as buf
import './util.vim'

# Remove the diagnostics stored for buffer 'bnr'
export def DiagRemoveFile(lspserver: dict<any>, bnr: number)
  if lspserver.diagsMap->has_key(bnr)
    lspserver.diagsMap->remove(bnr)
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

# Refresh the signs placed in buffer 'bnr' on lines with a diagnostic message.
def DiagsRefreshSigns(lspserver: dict<any>, bnr: number)
  # Remove all the existing diagnostic signs
  sign_unplace('LSPDiag', {buffer: bnr})

  if lspserver.diagsMap[bnr]->empty()
    return
  endif

  var signs: list<dict<any>> = []
  for [lnum, diag] in lspserver.diagsMap[bnr]->items()
    signs->add({id: 0, buffer: bnr, group: 'LSPDiag',
				lnum: lnum->str2nr(),
				name: DiagSevToSignName(diag.severity)})
  endfor

  signs->sign_placelist()
enddef

# New LSP diagnostic messages received from the server for a file.
# Update the signs placed in the buffer for this file
export def ProcessNewDiags(lspserver: dict<any>, bnr: number)
  if opt.lspOptions.autoPopulateDiags
    DiagsUpdateLocList(lspserver, bnr)
  endif

  if !opt.lspOptions.autoHighlightDiags
    return
  endif

  if bnr == -1 || !lspserver.diagsMap->has_key(bnr)
    return
  endif

  var curmode: string = mode()
  if curmode == 'i' || curmode == 'R' || curmode == 'Rv'
    # postpone placing signs in insert mode and replace mode. These will be
    # placed after the user returns to Normal mode.
    b:LspDiagsUpdatePending = true
    return
  endif

  DiagsRefreshSigns(lspserver, bnr)
enddef

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
export def DiagNotification(lspserver: dict<any>, uri: string, diags: list<dict<any>>): void
  var fname: string = util.LspUriToFile(uri)
  var bnr: number = fname->bufnr()
  if bnr == -1
    # Is this condition possible?
    return
  endif

  # TODO: Is the buffer (bnr) always a loaded buffer? Should we load it here?
  var lastlnum: number = bnr->getbufinfo()[0].linecount
  var lnum: number

  # store the diagnostic for each line separately
  var diag_by_lnum: dict<dict<any>> = {}
  for d in diags
    lnum = d.range.start.line + 1
    if lnum > lastlnum
      # Make sure the line number is a valid buffer line number
      lnum = lastlnum
    endif
    diag_by_lnum[lnum] = d
  endfor

  lspserver.diagsMap->extend({[$'{bnr}']: diag_by_lnum})
  ProcessNewDiags(lspserver, bnr)

  # Notify user scripts that diags has been updated
  if exists('#User#LspDiagsUpdated')
    doautocmd <nomodeline> User LspDiagsUpdated
  endif
enddef

# get the count of error in the current buffer
export def DiagsGetErrorCount(lspserver: dict<any>): dict<number>
  var errCount = 0
  var warnCount = 0
  var infoCount = 0
  var hintCount = 0

  var bnr: number = bufnr()
  if lspserver.diagsMap->has_key(bnr)
    for item in lspserver.diagsMap[bnr]->values()
      var severity = item->get('severity', -1)
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
def DiagsUpdateLocList(lspserver: dict<any>, bnr: number): bool
  var fname: string = bnr->bufname()->fnamemodify(':p')
  if fname == ''
    return false
  endif

  var LspQfId: number = 0
  if bnr->getbufvar('LspQfId', 0) != 0 &&
		  getloclist(0, {id: b:LspQfId}).id == b:LspQfId
    LspQfId = b:LspQfId
  endif

  if !lspserver.diagsMap->has_key(bnr) || lspserver.diagsMap[bnr]->empty()
    if LspQfId != 0
      setloclist(0, [], 'r', {id: LspQfId, items: []})
    endif
    return false
  endif

  var qflist: list<dict<any>> = []
  var text: string

  for [lnum, diag] in lspserver.diagsMap[bnr]->items()
    text = diag.message->substitute("\n\\+", "\n", 'g')
    qflist->add({filename: fname,
		    lnum: diag.range.start.line + 1,
		    col: util.GetLineByteFromPos(bnr, diag.range.start) + 1,
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
    b:LspQfId = getloclist(0, {id: 0}).id
  endif

  return true
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a location list
export def ShowAllDiags(lspserver: dict<any>): void
  if !DiagsUpdateLocList(lspserver, bufnr())
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
  var ppopts = {}
  ppopts.pos = 'topleft'
  ppopts.line = d.row + 1
  ppopts.col = d.col
  ppopts.moved = 'any'
  ppopts.wrap = false
  popup_create(diag.message->split("\n"), ppopts)
enddef

# Show the diagnostic message for the current line
export def ShowCurrentDiag(lspserver: dict<any>)
  var bnr: number = bufnr()
  var lnum: number = line('.')
  var diag: dict<any> = lspserver.getDiagByLine(bnr, lnum)
  if diag->empty()
    util.WarnMsg('No diagnostic messages found for current line')
  else
    if opt.lspOptions.showDiagInPopup
      # Display the diagnostic message in a popup window.
      ShowDiagInPopup(diag)
    else
      # Display the diagnostic message in the status message area
      echo diag.message
    endif
  endif
enddef

# Show the diagnostic message for the current line without linebreak
export def ShowCurrentDiagInStatusLine(lspserver: dict<any>)
  var bnr: number = bufnr()
  var lnum: number = line('.')
  var diag: dict<any> = lspserver.getDiagByLine(bnr, lnum)
  if !diag->empty()
    # 15 is a enough length not to cause line break
    var max_width = &columns - 15
    var code = ""
    if diag->has_key('code')
      code = $'[{diag.code}] '
    endif
    var msgNoLineBreak = code .. substitute(substitute(diag.message, "\n", " ", ""), "\\n", " ", "")
    echo msgNoLineBreak[ : max_width]
  else
    echo ""
  endif
enddef

# Get the diagnostic from the LSP server for a particular line in a file
export def GetDiagByLine(lspserver: dict<any>, bnr: number, lnum: number): dict<any>
  if lspserver.diagsMap->has_key(bnr) &&
				lspserver.diagsMap[bnr]->has_key(lnum)
    return lspserver.diagsMap[bnr][lnum]
  endif
  return {}
enddef

# sort the diaganostics messages for a buffer by line number
def GetSortedDiagLines(lspsrv: dict<any>, bnr: number): list<number>
  # create a list of line numbers from the diag map keys
  var lnums: list<number> =
		lspsrv.diagsMap[bnr]->keys()->mapnew((_, v) => v->str2nr())
  return lnums->sort((a, b) => a - b)
enddef

# jump to the next/previous/first diagnostic message in the current buffer
export def LspDiagsJump(lspserver: dict<any>, which: string): void
  var fname: string = expand('%:p')
  if fname == ''
    return
  endif
  var bnr: number = bufnr()

  if !lspserver.diagsMap->has_key(bnr) || lspserver.diagsMap[bnr]->empty()
    util.WarnMsg($'No diagnostic messages found for {fname}')
    return
  endif

  # sort the diagnostics by line number
  var sortedDiags: list<number> = GetSortedDiagLines(lspserver, bnr)

  if which == 'first'
    [sortedDiags[0], 1]->cursor()
    return
  endif

  # Find the entry just before the current line (binary search)
  var curlnum: number = line('.')
  for lnum in (which == 'next') ? sortedDiags : sortedDiags->reverse()
    if (which == 'next' && lnum > curlnum)
	  || (which == 'prev' && lnum < curlnum)
      [lnum, 1]->cursor()
      return
    endif
  endfor

  util.WarnMsg('Error: No more diagnostics found')
enddef

# Disable the LSP diagnostics highlighting in all the buffers
export def DiagsHighlightDisable()
  # Remove all the existing diagnostic signs in all the buffers
  sign_unplace('LSPDiag')
  opt.lspOptions.autoHighlightDiags = false
enddef

# Enable the LSP diagnostics highlighting
export def DiagsHighlightEnable()
  opt.lspOptions.autoHighlightDiags = true
  for binfo in getbufinfo({bufloaded: true})
    var lspserver: dict<any> = buf.BufLspServerGet(binfo.bufnr)
    if !lspserver->empty() && lspserver.running
      DiagsRefreshSigns(lspserver, binfo.bufnr)
    endif
  endfor
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
