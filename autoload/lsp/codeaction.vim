vim9script

# Functions related to handling LSP code actions to fix diagnostics.

import './util.vim'
import './textedit.vim'

export def ApplyCodeAction(lspserver: dict<any>, actions: list<dict<any>>): void
  if actions->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  var prompt: list<string> = ['Code Actions:']
  var act: dict<any>
  for i in range(actions->len())
    act = actions[i]
    var t: string = act.title->substitute('\r\n', '\\r\\n', 'g')
    t = t->substitute('\n', '\\n', 'g')
    prompt->add(printf("%d. %s", i + 1, t))
  endfor

  var choice: number

  if exists('g:LSPTest') && g:LSPTest && exists('g:LSPTest_CodeActionChoice')
    # Running the LSP unit-tests. Instead of prompting the user, use the
    # choice set in LSPTest_CodeActionChoice.
    choice = g:LSPTest_CodeActionChoice
  else
    choice = inputlist(prompt)
  endif

  if choice < 1 || choice >= prompt->len()
    return
  endif
  var selAction = actions[choice - 1]

  # textDocument/codeAction can return either Command[] or CodeAction[].
  # If it is a CodeAction, it can have either an edit, a command or both.
  # Edits should be executed first.
  if selAction->has_key('edit') || selAction->has_key('command')
    if selAction->has_key('edit')
      # apply edit first
      textedit.ApplyWorkspaceEdit(selAction.edit)
    endif
    if selAction->has_key('command')
      lspserver.executeCommand(selAction)
    endif
  else
    lspserver.executeCommand(selAction)
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
