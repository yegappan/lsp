vim9script

# Functions related to handling LSP symbol signature help.

var opt = {}
var util = {}

if has('patch-8.2.4019')
  import './lspoptions.vim' as opt_import
  import './util.vim' as util_import

  opt.lspOptions = opt_import.lspOptions
  util.WarnMsg = util_import.WarnMsg
else
  import lspOptions from './lspoptions.vim'
  import {WarnMsg} from './util.vim'

  opt.lspOptions = lspOptions
  util.WarnMsg = WarnMsg
endif

# Display the symbol signature help
export def SignatureDisplay(lspserver: dict<any>, sighelp: dict<any>): void
  if sighelp->empty()
    return
  endif

  if sighelp.signatures->len() <= 0
    util.WarnMsg('No signature help available')
    return
  endif

  var sigidx: number = 0
  if sighelp->has_key('activeSignature')
    sigidx = sighelp.activeSignature
  endif

  var sig: dict<any> = sighelp.signatures[sigidx]
  var text = sig.label
  var hllen = 0
  var startcol = 0
  if sig->has_key('parameters') && sighelp->has_key('activeParameter')
    var params_len = sig.parameters->len()
    if params_len > 0 && sighelp.activeParameter < params_len
      var label = sig.parameters[sighelp.activeParameter].label
      hllen = label->len()
      startcol = text->stridx(label)
    endif
  endif
  if opt.lspOptions.echoSignature
    echon "\r\r"
    echon ''
    echon strpart(text, 0, startcol)
    echoh LineNr
    echon strpart(text, startcol, hllen)
    echoh None
    echon strpart(text, startcol + hllen)
  else
    var popupID = text->popup_atcursor({moved: 'any'})
    prop_type_add('signature', {bufnr: popupID->winbufnr(), highlight: 'LineNr'})
    if hllen > 0
      prop_add(1, startcol + 1, {bufnr: popupID->winbufnr(), length: hllen, type: 'signature'})
    endif
  endif
enddef

# vim: shiftwidth=2 softtabstop=2
