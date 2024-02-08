vim9script

# Functions related to handling LSP symbol signature help.

import './options.vim' as opt
import './util.vim'
import './buffer.vim' as buf

# close the signature popup window
def CloseSignaturePopup(lspserver: dict<any>)
  if lspserver.signaturePopup != -1
    lspserver.signaturePopup->popup_close()
  endif
  lspserver.signaturePopup = -1
enddef

def CloseCurBufSignaturePopup()
  var lspserver: dict<any> = buf.CurbufGetServer('signatureHelp')
  if lspserver->empty()
    return
  endif

  CloseSignaturePopup(lspserver)
enddef

# Show the signature using "textDocument/signatureHelp" LSP method
# Invoked from an insert-mode mapping, so return an empty string.
def g:LspShowSignature(): string
  var lspserver: dict<any> = buf.CurbufGetServerChecked('signatureHelp')
  if lspserver->empty()
    return ''
  endif

  # first send all the changes in the current buffer to the LSP server
  listener_flush()
  lspserver.showSignature()
  return ''
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
      || !lspserver.featureEnabled('signatureHelp')
    # Show signature support is disabled
    return
  endif

  # map characters that trigger signature help
  for ch in lspserver.caps.signatureHelpProvider.triggerCharacters
    exe $"inoremap <buffer> <silent> {ch} {ch}<C-R>=g:LspShowSignature()<CR>"
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
    var params: list<dict<any>> = sig.parameters
    var params_len: number = params->len()
    var activeParam: number = sighelp.activeParameter
    if params_len > 0 && activeParam < params_len
      var paramInfo: dict<any> = params[activeParam]
      var label: any = paramInfo.label
      if label->type() == v:t_string
	# label string
	var label_str: string = label
	hllen = label_str->len()
	startcol = text->stridx(label_str)
      else
	# [inclusive start offset, exclusive end offset]
	var label_offset: list<number> = params[activeParam].label
	var start_offset: number = label_offset[0]
	var end_offset: number = label_offset[1]

	if has('patch-9.0.1629')
	  # Convert UTF-16 offsets
	  startcol = text->byteidx(start_offset, true)
	  var endcol: number = text->byteidx(end_offset, true)
	  hllen = endcol - startcol
	else
	  startcol = start_offset
	  hllen = end_offset - start_offset
	endif
      endif
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

    var popupID = text->popup_atcursor({padding: [0, 1, 0, 1], moved: [col('.') - 1, 9999999]})
    var bnr: number = popupID->winbufnr()
    prop_type_add('signature', {bufnr: bnr, highlight: 'LspSigActiveParameter'})
    if hllen > 0
      prop_add(1, startcol + 1, {bufnr: bnr, length: hllen, type: 'signature'})
    endif
    lspserver.signaturePopup = popupID
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
