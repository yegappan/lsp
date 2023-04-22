vim9script

# Functions for dealing with inlay hints

import './util.vim'
import './buffer.vim' as buf
import './options.vim' as opt

# Initialize the highlight group and the text property type used for
# inlay hints.
export def InitOnce()
  hlset([{name: 'LspInlayHintsType', default: true, linksto: 'Label'}])
  hlset([{name: 'LspInlayHintsParam', default: true, linksto: 'Conceal'}])
  prop_type_add('LspInlayHintsType', {highlight: 'LspInlayHintsType'})
  prop_type_add('LspInlayHintsParam', {highlight: 'LspInlayHintsParam'})
enddef

# Clear all the inlay hints text properties in the current buffer
def InlayHintsClear(lspserver: dict<any>)
  prop_remove({type: 'LspInlayHintsType', bufnr: bufnr('%'), all: true})
  prop_remove({type: 'LspInlayHintsParam', bufnr: bufnr('%'), all: true})
enddef

# LSP inlay hints reply message handler
export def InlayHintsReply(lspserver: dict<any>, inlayHints: any)
  if inlayHints->empty()
    return
  endif

  InlayHintsClear(lspserver)

  if mode() != 'n'
    # Update inlay hints only in normal mode
    return
  endif

  var bufnum = bufnr('%')
  for hint in inlayHints
    var label = ''
    if hint.label->type() == v:t_list
      label = hint.label->copy()->map((_, v) => v.value)->join(', ')
    else
      label = hint.label
    endif

    var kind = hint->has_key('kind') ? hint.kind->string() : '1'
    try
      if kind == "'type'" || kind == '1'
	prop_add(hint.position.line + 1, hint.position.character + 1,
	  {type: 'LspInlayHintsType', text: label, bufnr: bufnum})
      elseif kind == "'parameter'" || kind == '2'
	prop_add(hint.position.line + 1, hint.position.character + 1,
	  {type: 'LspInlayHintsParam', text: label, bufnr: bufnum})
      endif
    catch /E966\|E964/ # Invalid lnum | Invalid col
      # Inlay hints replies arrive asynchronously and the document might have
      # been modified in the mean time.  As the reply is stale, ignore invalid
      # line number and column number errors.
    endtry
  endfor
enddef

# Timer callback to display the inlay hints.
def InlayHintsCallback(lspserver: dict<any>, timerid: number)
  lspserver.inlayHintsShow()
  b:LspInlayHintsNeedsUpdate = false
enddef

# Update all the inlay hints.  A timer is used to throttle the updates.
def LspInlayHintsUpdate()
  if !get(b:, 'LspInlayHintsNeedsUpdate', true)
    return
  endif

  var timerid = get(b:, 'LspInlayHintsTimer', -1)
  if timerid != -1
    timerid->timer_stop()
    b:LspInlayHintsTimer = -1
  endif

  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  timerid = timer_start(300, function('InlayHintsCallback', [lspserver]))
  b:LspInlayHintsTimer = timerid
enddef

# Text is modified. Need to update the inlay hints.
def LspInlayHintsChanged()
  b:LspInlayHintsNeedsUpdate = true
enddef

# Trigger an update of the inlay hints in the current buffer.
export def LspInlayHintsUpdateNow()
  b:LspInlayHintsNeedsUpdate = true
  LspInlayHintsUpdate()
enddef

# Stop updating the inlay hints.
def LspInlayHintsUpdateStop()
  var timerid = get(b:, 'LspInlayHintsTimer', -1)
  if timerid != -1
    timerid->timer_stop()
    b:LspInlayHintsTimer = -1
  endif
enddef

# Do buffer-local initialization for displaying inlay hints
export def BufferInit(lspserver: dict<any>, bnr: number)
  if !lspserver.isInlayHintProvider && !lspserver.isClangdInlayHintsProvider
    # no support for inley hints
    return
  endif

  # Inlays hints are disabled
  if !opt.lspOptions.showInlayHints
    return
  endif

  var acmds: list<dict<any>> = []

  # Update the inlay hints (if needed) when the cursor is not moved for some
  # time.
  acmds->add({bufnr: bnr,
		event: ['CursorHold'],
		group: 'LSPBufferAutocmds',
		cmd: 'LspInlayHintsUpdate()'})
  # After the text in the current buffer is modified, the inlay hints need to
  # be updated.
  acmds->add({bufnr: bnr,
		event: ['TextChanged'],
		group: 'LSPBufferAutocmds',
		cmd: 'LspInlayHintsChanged()'})
  # Editing a file should trigger an inlay hint update.
  acmds->add({bufnr: bnr,
		event: ['BufReadPost'],
		group: 'LSPBufferAutocmds',
		cmd: 'LspInlayHintsUpdateNow()'})
  # Inlay hints need not be updated if a buffer is no longer active.
  acmds->add({bufnr: bnr,
		event: ['BufLeave'],
		group: 'LSPBufferAutocmds',
		cmd: 'LspInlayHintsUpdateStop()'})

  autocmd_add(acmds)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
