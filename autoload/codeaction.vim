vim9script

var util = {}
var textedit = {}

if has('patch-8.2.4019')
  import './util.vim' as util_import
  import './textedit.vim' as textedit_import

  util.WarnMsg = util_import.WarnMsg
  textedit.ApplyWorkspaceEdit = textedit_import.ApplyWorkspaceEdit
else
  import WarnMsg from './util.vim'
  import ApplyWorkspaceEdit from './textedit.vim'

  util.WarnMsg = WarnMsg
  textedit.ApplyWorkspaceEdit = ApplyWorkspaceEdit
endif

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
  var choice = inputlist(prompt)
  if choice < 1 || choice > prompt->len()
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

# vim: shiftwidth=2 softtabstop=2
