vim9script

# Functions related to handling LSP code actions to fix diagnostics.

import './util.vim'
import './textedit.vim'
import './options.vim' as opt

export def HandleCodeAction(lspserver: dict<any>, selAction: dict<any>)
  # textDocument/codeAction can return either Command[] or CodeAction[].
  # If it is a CodeAction, it can have either an edit, a command or both.
  # Edits should be executed first.
  # Both Command and CodeAction interfaces has 'command' member
  # so we should check 'command' type - for Command it will be 'string'
  if selAction->has_key('edit')
     || (selAction->has_key('command') && selAction.command->type() == v:t_dict)
    # selAction is a CodeAction instance, apply edit and command
    if selAction->has_key('edit')
      # apply edit first
      textedit.ApplyWorkspaceEdit(selAction.edit)
    endif
    if selAction->has_key('command')
      lspserver.executeCommand(selAction.command)
    endif
  else
    # selAction is a Command instance, apply it directly
    lspserver.executeCommand(selAction)
  endif
enddef

export def ApplyCodeAction(lspserver: dict<any>, actions: list<dict<any>>): void
  if actions->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  var text: list<string> = []
  var act: dict<any>
  for i in range(actions->len())
    act = actions[i]
    var t: string = act.title->substitute('\r\n', '\\r\\n', 'g')
    t = t->substitute('\n', '\\n', 'g')
    text->add(printf(" %d. %s ", i + 1, t))
  endfor

  var choice: number

  if exists('g:LSPTest') && g:LSPTest && exists('g:LSPTest_CodeActionChoice')
    # Running the LSP unit-tests. Instead of prompting the user, use the
    # choice set in LSPTest_CodeActionChoice.
    choice = g:LSPTest_CodeActionChoice
  else
    if opt.lspOptions.usePopupInCodeAction
      # Use a popup menu to show the code action
      popup_create(text, {
        pos: 'botleft',
        line: 'cursor-1',
        col: 'cursor',
        zindex: 1000,
        cursorline: 1,
        mapping: 0,
        wrap: 0,
        title: 'Code action',
        callback: (_, id) => {
          # Invalid item selected or closed the popup
          if id <= 0 || id > text->len()
            return
          endif

          # Do the code action
          HandleCodeAction(lspserver, actions[id - 1])
        },
        filter: 'popup_filter_menu'
      })
    else
      choice = inputlist(["Code action:"] + text)
    endif
  endif

  if choice < 1 || choice > text->len()
    return
  endif

  HandleCodeAction(lspserver, actions[choice - 1])
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
