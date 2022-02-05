vim9script

# Functions related to handling LSP diagnostics.

var opt = {}
var util = {}

if has('patch-8.2.4019')
  import './lspoptions.vim' as opt_import
  import './util.vim' as util_import

  opt.lspOptions = opt_import.lspOptions
  util.WarnMsg = util_import.WarnMsg
  util.GetLineByteFromPos = util_import.GetLineByteFromPos
  util.LspUriToFile = util_import.LspUriToFile
else
  import lspOptions from './lspoptions.vim'
  import {WarnMsg,
	LspUriToFile,
	GetLineByteFromPos} from './util.vim'

  opt.lspOptions = lspOptions
  util.WarnMsg = WarnMsg
  util.LspUriToFile = LspUriToFile
  util.GetLineByteFromPos = GetLineByteFromPos
endif

# Remove the diagnostics stored for buffer 'bnr'
export def DiagRemoveFile(lspserver: dict<any>, bnr: number)
  if lspserver.diagsMap->has_key(bnr)
    lspserver.diagsMap->remove(bnr)
  endif
enddef

def s:lspDiagSevToSignName(severity: number): string
  var typeMap: list<string> = ['LspDiagError', 'LspDiagWarning',
						'LspDiagInfo', 'LspDiagHint']
  if severity > 4
    return 'LspDiagHint'
  endif
  return typeMap[severity - 1]
enddef

# New LSP diagnostic messages received from the server for a file.
# Update the signs placed in the buffer for this file
def ProcessNewDiags(lspserver: dict<any>, bnr: number)
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

  # Remove all the existing diagnostic signs
  sign_unplace('LSPDiag', {buffer: bnr})

  if lspserver.diagsMap[bnr]->empty()
    return
  endif

  var signs: list<dict<any>> = []
  for [lnum, diag] in lspserver.diagsMap[bnr]->items()
    signs->add({id: 0, buffer: bnr, group: 'LSPDiag',
				lnum: str2nr(lnum),
				name: s:lspDiagSevToSignName(diag.severity)})
  endfor

  signs->sign_placelist()
enddef

# FIXME: Remove this function once the Vim bug (calling one exported function
# from another exported function in an autoload script is not working) is
# fixed. Replace the calls to this function directly with calls to
# ProcessNewDiags().
export def UpdateDiags(lspserver: dict<any>, bnr: number)
  ProcessNewDiags(lspserver, bnr)
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

  lspserver.diagsMap->extend({['' .. bnr]: diag_by_lnum})
  ProcessNewDiags(lspserver, bnr)
enddef

# get the count of error in the current buffer
export def DiagsGetErrorCount(lspserver: dict<any>): dict<number>
  var res = {'Error': 0, 'Warn': 0, 'Info': 0, 'Hint': 0}

  var bnr: number = bufnr()
  if lspserver.diagsMap->has_key(bnr)
      for item in lspserver.diagsMap[bnr]->values()
          if item->has_key('severity')
              if item.severity == 1
                  res.Error = res.Error + 1
              elseif item.severity == 2
                  res.Warn = res.Warn + 1
              elseif item.severity == 3
                  res.Info = res.Info + 1
              elseif item.severity == 4
                  res.Hint = res.Hint + 1
              endif
          endif
      endfor
  endif

  return res
enddef

# Map the LSP DiagnosticSeverity to a quickfix type character
def s:lspDiagSevToQfType(severity: number): string
  var typeMap: list<string> = ['E', 'W', 'I', 'N']

  if severity > 4
    return ''
  endif

  return typeMap[severity - 1]
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a location list
export def ShowAllDiags(lspserver: dict<any>): void
  var fname: string = expand('%:p')
  if fname == ''
    return
  endif
  var bnr: number = bufnr()

  if !lspserver.diagsMap->has_key(bnr) || lspserver.diagsMap[bnr]->empty()
    util.WarnMsg('No diagnostic messages found for ' .. fname)
    return
  endif

  var qflist: list<dict<any>> = []
  var text: string

  for [lnum, diag] in lspserver.diagsMap[bnr]->items()
    text = diag.message->substitute("\n\\+", "\n", 'g')
    qflist->add({'filename': fname,
		    'lnum': diag.range.start.line + 1,
		    'col': util.GetLineByteFromPos(bnr, diag.range.start) + 1,
		    'text': text,
		    'type': s:lspDiagSevToQfType(diag.severity)})
  endfor
  setloclist(0, [], ' ', {'title': 'Language Server Diagnostics',
							'items': qflist})
  :lopen
enddef

# Show the diagnostic message for the current line
export def ShowCurrentDiag(lspserver: dict<any>)
  var bnr: number = bufnr()
  var lnum: number = line('.')
  var diag: dict<any> = lspserver.getDiagByLine(bnr, lnum)
  if diag->empty()
    util.WarnMsg('No diagnostic messages found for current line')
  else
    echo diag.message
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
    if has_key(diag, 'code')
      code = "[" .. diag.code .. "] "
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
def s:getSortedDiagLines(lspsrv: dict<any>, bnr: number): list<number>
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
    util.WarnMsg('No diagnostic messages found for ' .. fname)
    return
  endif

  # sort the diagnostics by line number
  var sortedDiags: list<number> = s:getSortedDiagLines(lspserver, bnr)

  if which == 'first'
    cursor(sortedDiags[0], 1)
    return
  endif

  # Find the entry just before the current line (binary search)
  var curlnum: number = line('.')
  for lnum in (which == 'next') ? sortedDiags : sortedDiags->reverse()
    if (which == 'next' && lnum > curlnum)
	  || (which == 'prev' && lnum < curlnum)
      cursor(lnum, 1)
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
  # Remove all the existing diagnostic signs in all the buffers
  opt.lspOptions.autoHighlightDiags = true
enddef

# vim: shiftwidth=2 softtabstop=2
