vim9script

# Functions for dealing with inlay hints

import './util.vim'
import './buffer.vim' as buf

# Initialize the highlight group and the text property type used for
# inlay hints.
export def InitOnce()
  if !hlexists('LspInlayHintsType')
    hlset([{name: 'LspInlayHintsType', linksto: 'Label'}])
  endif
  if !hlexists('LspInlayHintsParam')
    hlset([{name: 'LspInlayHintsParam', linksto: 'Conceal'}])
  endif
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

  #echomsg inlayHints->string

  InlayHintsClear(lspserver)

  if mode() !=# 'n'
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

    if hint.kind ==# 'type'
      prop_add(hint.position.line + 1, hint.position.character + 1,
		{type: 'LspInlayHintsType', text: label, bufnr: bufnum})
    elseif hint.kind ==# 'parameter'
      prop_add(hint.position.line + 1, hint.position.character + 1,
		{type: 'LspInlayHintsParam', text: label, bufnr: bufnum})
    endif
  endfor
enddef

# Timer callback to display the inlay hints.
def InlayHintsCallback(lspserver: dict<any>, timerid: number)
  lspserver.inlayHintsShow()
  b:LspInlayHintsNeedsUpdate = false
enddef

# Update all the inlay hints.  A timer is used to throttle the updates.
def InlayHintsUpdate()
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
def InlayHintsChanged()
  b:LspInlayHintsNeedsUpdate = true
enddef

# Stop updating the inlay hints.
def InlayHintsUpdateStop()
  var timerid = get(b:, 'LspInlayHintsTimer', -1)
  if timerid != -1
    timerid->timer_stop()
    b:LspInlayHintsTimer = -1
  endif
enddef

# Do buffer-local initialization for displaying inlay hints
export def BufferInit(bnr: number)
  var acmds: list<dict<any>> = []

  acmds->add({bufnr: bnr,
		event: ['CursorHold'],
		group: 'LSPBufferAutocmds',
		cmd: 'InlayHintsUpdate()'})
  acmds->add({bufnr: bnr,
		event: ['TextChanged'],
		group: 'LSPBufferAutocmds',
		cmd: 'InlayHintsChanged()'})
  acmds->add({bufnr: bnr,
		event: ['BufLeave'],
		group: 'LSPBufferAutocmds',
		cmd: 'InlayHintsUpdateStop()'})

  autocmd_add(acmds)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
