vim9script

# Functions for dealing with inlay hints

import './util.vim'
import './buffer.vim' as buf
import './options.vim' as opt

# Initialize the highlight group and the text property type used for
# inlay hints.
export def InitOnce()
  hlset([
    {name: 'LspInlayHintsType', default: true, linksto: 'Label'},
    {name: 'LspInlayHintsParam', default: true, linksto: 'Conceal'}
  ])
  prop_type_add('LspInlayHintsType', {highlight: 'LspInlayHintsType'})
  prop_type_add('LspInlayHintsParam', {highlight: 'LspInlayHintsParam'})

  autocmd_add([{group: 'LspCmds',
	        event: 'User',
		pattern: 'LspOptionsChanged',
		cmd: 'LspInlayHintsOptionsChanged()'}])
enddef

# Clear all the inlay hints text properties in the current buffer
def InlayHintsClear(bnr: number)
  prop_remove({type: 'LspInlayHintsType', bufnr: bnr, all: true})
  prop_remove({type: 'LspInlayHintsParam', bufnr: bnr, all: true})
enddef

# LSP inlay hints reply message handler
export def InlayHintsReply(lspserver: dict<any>, bnr: number, inlayHints: any)
  if inlayHints->empty()
    return
  endif

  InlayHintsClear(bnr)

  if mode() != 'n'
    # Update inlay hints only in normal mode
    return
  endif

  for hint in inlayHints
    var label = ''
    if hint.label->type() == v:t_list
      label = hint.label->copy()->map((_, v) => v.value)->join('')
    else
      label = hint.label
    endif

    # add a space before or after the label
    var padLeft: bool = hint->get('paddingLeft', false)
    var padRight: bool = hint->get('paddingRight', false)
    if padLeft
      label = $' {label}'
    endif
    if padRight
      label = $'{label} '
    endif

    var kind = hint->has_key('kind') ? hint.kind->string() : '1'
    try
      lspserver.decodePosition(bnr, hint.position)
      var byteIdx = util.GetLineByteFromPos(bnr, hint.position)
      if kind == "'type'" || kind == '1'
	prop_add(hint.position.line + 1, byteIdx + 1,
	  {type: 'LspInlayHintsType', text: label, bufnr: bnr})
      elseif kind == "'parameter'" || kind == '2'
	prop_add(hint.position.line + 1, byteIdx + 1,
	  {type: 'LspInlayHintsParam', text: label, bufnr: bnr})
      endif
    catch /E966\|E964/ # Invalid lnum | Invalid col
      # Inlay hints replies arrive asynchronously and the document might have
      # been modified in the mean time.  As the reply is stale, ignore invalid
      # line number and column number errors.
    endtry
  endfor
enddef

# Timer callback to display the inlay hints.
def InlayHintsTimerCb(lspserver: dict<any>, bnr: number, timerid: number)
  lspserver.inlayHintsShow(bnr)
  setbufvar(bnr, 'LspInlayHintsNeedsUpdate', false)
enddef

# Update all the inlay hints.  A timer is used to throttle the updates.
def LspInlayHintsUpdate(bnr: number)
  if !bnr->getbufvar('LspInlayHintsNeedsUpdate', true)
    return
  endif

  var timerid = bnr->getbufvar('LspInlayHintsTimer', -1)
  if timerid != -1
    timerid->timer_stop()
    setbufvar(bnr, 'LspInlayHintsTimer', -1)
  endif

  var lspserver: dict<any> = buf.BufLspServerGet(bnr, 'inlayHint')
  if lspserver->empty()
    return
  endif

  if get(g:, 'LSPTest')
    # When running tests, update the inlay hints immediately
    InlayHintsTimerCb(lspserver, bnr, -1)
  else
    timerid = timer_start(300, function('InlayHintsTimerCb', [lspserver, bnr]))
    setbufvar(bnr, 'LspInlayHintsTimer', timerid)
  endif
enddef

# Text is modified. Need to update the inlay hints.
def LspInlayHintsChanged(bnr: number)
  setbufvar(bnr, 'LspInlayHintsNeedsUpdate', true)
enddef

# Trigger an update of the inlay hints in the current buffer.
export def LspInlayHintsUpdateNow(bnr: number)
  setbufvar(bnr, 'LspInlayHintsNeedsUpdate', true)
  LspInlayHintsUpdate(bnr)
enddef

# Stop updating the inlay hints.
def LspInlayHintsUpdateStop(bnr: number)
  var timerid = bnr->getbufvar('LspInlayHintsTimer', -1)
  if timerid != -1
    timerid->timer_stop()
    setbufvar(bnr, 'LspInlayHintsTimer', -1)
  endif
enddef

# Do buffer-local initialization for displaying inlay hints
export def BufferInit(lspserver: dict<any>, bnr: number)
  if !lspserver.isInlayHintProvider && !lspserver.isClangdInlayHintsProvider
    # no support for inlay hints
    return
  endif

  # Inlays hints are disabled
  if !opt.lspOptions.showInlayHints
      || !lspserver.featureEnabled('inlayHint')
    return
  endif

  var acmds: list<dict<any>> = []

  # Update the inlay hints (if needed) when the cursor is not moved for some
  # time.
  acmds->add({bufnr: bnr,
		event: ['CursorHold'],
		group: 'LspInlayHints',
		cmd: $'LspInlayHintsUpdate({bnr})'})
  # After the text in the current buffer is modified, the inlay hints need to
  # be updated.
  acmds->add({bufnr: bnr,
		event: ['TextChanged'],
		group: 'LspInlayHints',
		cmd: $'LspInlayHintsChanged({bnr})'})
  # Editing a file should trigger an inlay hint update.
  acmds->add({bufnr: bnr,
		event: ['BufReadPost'],
		group: 'LspInlayHints',
		cmd: $'LspInlayHintsUpdateNow({bnr})'})
  # Inlay hints need not be updated if a buffer is no longer active.
  acmds->add({bufnr: bnr,
		event: ['BufLeave'],
		group: 'LspInlayHints',
		cmd: $'LspInlayHintsUpdateStop({bnr})'})

  # Inlay hints maybe a bit delayed if it was a sync init lsp server.
  if lspserver.syncInit
    acmds->add({bufnr: bnr,
		  event: ['User'],
		  group: 'LspAttached',
		  cmd: $'LspInlayHintsUpdateNow({bnr})'})
  endif

  autocmd_add(acmds)
enddef

# Track the current inlay hints enabled/disabled state.  Used when the
# "showInlayHints" option value is changed.
var save_showInlayHints = opt.lspOptions.showInlayHints

# Enable inlay hints.  For all the buffers with an attached language server
# that supports inlay hints, refresh the inlay hints.
export def InlayHintsEnable()
  opt.lspOptions.showInlayHints = true
  for binfo in getbufinfo()
    var lspservers: list<dict<any>> = buf.BufLspServersGet(binfo.bufnr)
    if lspservers->empty()
      continue
    endif
    for lspserver in lspservers
      if !lspserver.ready
	  || !lspserver.featureEnabled('inlayHint')
	  || (!lspserver.isInlayHintProvider &&
	      !lspserver.isClangdInlayHintsProvider)
	continue
      endif
      BufferInit(lspserver, binfo.bufnr)
      LspInlayHintsUpdateNow(binfo.bufnr)
    endfor
  endfor
  save_showInlayHints = true
enddef

# Disable inlay hints for the current Vim session.  Clear the inlay hints in
# all the buffers.
export def InlayHintsDisable()
  opt.lspOptions.showInlayHints = false
  for binfo in getbufinfo()
    var lspserver: dict<any> = buf.BufLspServerGet(binfo.bufnr, 'inlayHint')
    if lspserver->empty()
      continue
    endif
    LspInlayHintsUpdateStop(binfo.bufnr)
    :silent! autocmd_delete([{bufnr: binfo.bufnr, group: 'LspInlayHints'}])
    InlayHintsClear(binfo.bufnr)
  endfor
  save_showInlayHints = false
enddef

# Some options are changed.  If 'showInlayHints' option is changed, then
# either enable or disable inlay hints.
export def LspInlayHintsOptionsChanged()
  if save_showInlayHints && !opt.lspOptions.showInlayHints
    InlayHintsDisable()
  elseif !save_showInlayHints && opt.lspOptions.showInlayHints
    InlayHintsEnable()
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
