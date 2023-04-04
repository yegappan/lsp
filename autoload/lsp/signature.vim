vim9script

# Functions related to handling LSP symbol signature help.

import './options.vim' as opt
import './util.vim'
import './buffer.vim' as buf

# close the signature popup window
def CloseSignaturePopup(lspserver: dict<any>)
  lspserver.signaturePopup->popup_close()
  lspserver.signaturePopup = -1
enddef

def CloseCurBufSignaturePopup()
  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty()
    return
  endif

  CloseSignaturePopup(lspserver)
enddef

export def InitOnce()
  hlset([{name: 'LspSigActiveParameter', default: true, linksto: 'LineNr'}])
enddef

# Initialize the signature triggers for the current buffer
export def BufferInit(lspserver: dict<any>)
  if !lspserver.isSignatureHelpProvider
	|| !lspserver.caps.signatureHelpProvider->has_key('triggerCharacters')
    # no support for signature help
    return
  endif

  if !opt.lspOptions.showSignature
    # Show signature are disabled
    return
  endif

  # map characters that trigger signature help
  for ch in lspserver.caps.signatureHelpProvider.triggerCharacters
    exe $"inoremap <buffer> <silent> {ch} {ch}<C-R>=LspShowSignature()<CR>"
  endfor

  # close the signature popup when leaving insert mode
  autocmd_add([{bufnr: bufnr(),
		event: 'InsertLeave',
		cmd: 'CloseCurBufSignaturePopup()'}])
enddef

# process the 'textDocument/signatureHelp' reply from the LSP server and
# display the symbol signature help.
# Result: SignatureHelp | null
export def SignatureHelp(lspserver: dict<any>, sighelp: any): void
  if sighelp->empty()
    CloseSignaturePopup(lspserver)
    return
  endif

  if sighelp.signatures->len() <= 0
    util.WarnMsg('No signature help available')
    CloseSignaturePopup(lspserver)
    return
  endif

  var sigidx: number = 0
  if sighelp->has_key('activeSignature')
    sigidx = sighelp.activeSignature
  endif

  var sig: dict<any> = sighelp.signatures[sigidx]
  var text: string = sig.label
  var hllen: number = 0
  var startcol: number = 0
  if sig->has_key('parameters') && sighelp->has_key('activeParameter')
    var params_len = sig.parameters->len()
    if params_len > 0 && sighelp.activeParameter < params_len
      var label: string = sig.parameters[sighelp.activeParameter].label
      hllen = label->len()
      startcol = text->stridx(label)
    endif
  endif
  if opt.lspOptions.echoSignature
    :echon "\r\r"
    :echon ''
    :echon text->strpart(0, startcol)
    :echoh LspSigActiveParameter
    :echon text->strpart(startcol, hllen)
    :echoh None
    :echon text->strpart(startcol + hllen)
  else
    # Close the previous signature popup and open a new one
    lspserver.signaturePopup->popup_close()

    var popupID = text->popup_atcursor({moved: [col('.') - 1, 9999999]})
    var bnum: number = popupID->winbufnr()
    prop_type_add('signature', {bufnr: bnum, highlight: 'LspSigActiveParameter'})
    if hllen > 0
      prop_add(1, startcol + 1, {bufnr: bnum, length: hllen, type: 'signature'})
    endif
    lspserver.signaturePopup = popupID
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
