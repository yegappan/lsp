vim9script

# Functions for on-type formatting (textDocument/onTypeFormatting).  As the
# user types, when a character the server designates as a trigger character
# is inserted, request formatting edits for the surrounding text and apply
# them.  Opt-in via the 'onTypeFormatting' option (see options.vim).

import './options.vim' as opt
import './buffer.vim' as buf

# Pre-create the (empty) augroup used for the buffer-local trigger autocmd.
export def InitOnce()
  augroup LspOnTypeFormatting
    autocmd!
  augroup END
enddef

# Handle a text change in insert mode: detect the character that was just
# typed and, if it is one of the server's on-type-formatting trigger
# characters, request on-type formatting for it.
export def OnTypeFormat(bnr: number)
  if !opt.lspOptions.onTypeFormatting
    return
  endif

  var lspserver: dict<any> = buf.BufLspServerGet(bnr, 'documentOnTypeFormatting')
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  var curLine = line('.')
  var prevLine = bnr->getbufvar('LspOnTypeFormatPrevLine', curLine)
  setbufvar(bnr, 'LspOnTypeFormatPrevLine', curLine)

  var ch: string
  if curLine > prevLine
    # A newline was just inserted.
    ch = "\n"
  else
    var col = charcol('.')
    var curText = getline('.')
    ch = curText[col - 2]
  endif

  if ch == '' || lspserver.onTypeFormattingTriggers->index(ch) == -1
    return
  endif

  lspserver.textDocOnTypeFormat(ch)
enddef

# Do buffer-local initialization for on-type formatting.
export def BufferInit(lspserver: dict<any>, bnr: number)
  if !lspserver.isDocumentOnTypeFormattingProvider
    # no support for on-type formatting
    return
  endif

  if !lspserver.featureEnabled('documentOnTypeFormatting')
    return
  endif

  autocmd_add([{bufnr: bnr,
		replace: true,
		event: 'TextChangedI',
		group: 'LspOnTypeFormatting',
		cmd: $'OnTypeFormat({bnr})'}])
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
