vim9script

# Functions related to handling LSP code actions to fix diagnostics.

import './util.vim'
import './textedit.vim'
import './options.vim' as opt

var CommandHandlers: dict<func>

export def RegisterCmdHandler(cmd: string, Handler: func)
  CommandHandlers[cmd] = Handler
enddef

export def DoCommand(lspserver: dict<any>, cmd: dict<any>)
  if cmd->has_key('command') && CommandHandlers->has_key(cmd.command)
    var CmdHandler: func = CommandHandlers[cmd.command]
    try
      call CmdHandler(cmd)
    catch
      util.ErrMsg($'"{cmd.command}" handler raised exception {v:exception}')
    endtry
  else
    lspserver.executeCommand(cmd)
  endif
enddef

# Apply the code action selected by the user.
export def HandleCodeAction(lspserver: dict<any>, selAction: dict<any>)
  # textDocument/codeAction can return either Command[] or CodeAction[].
  # If it is a CodeAction, it can have either an edit, a command or both.
  # Edits should be executed first.
  # Both Command and CodeAction interfaces has "command" member
  # so we should check "command" type - for Command it will be "string"
  if selAction->has_key('edit')
     || (selAction->has_key('command') && selAction.command->type() == v:t_dict)
    # selAction is a CodeAction instance, apply edit and command
    if selAction->has_key('edit')
      # apply edit first
      textedit.ApplyWorkspaceEdit(selAction.edit)
    endif
    if selAction->has_key('command')
      DoCommand(lspserver, selAction.command)
    endif
  else
    # selAction is a Command instance, apply it directly
    DoCommand(lspserver, selAction)
  endif
enddef

# Process the list of code actions returned by the LSP server, ask the user to
# choose one action from the list and then apply it.
# If "query" is a number, then apply the corresponding action in the list.
# If "query" is a regular expression starting with "/", then apply the action
# matching the search string in the list.
# If "query" is a regular string, then apply the action matching the string.
# If "query" is an empty string, then if the "usePopupInCodeAction" option is
# configured by the user, then display the list of items in a popup menu.
# Otherwise display the items in an input list and prompt the user to select
# an action.
export def ApplyCodeAction(lspserver: dict<any>, actionlist: list<dict<any>>, query: string): void
  var actions = actionlist

  if opt.lspOptions.hideDisabledCodeActions
    actions = actions->filter((ix, act) => !act->has_key('disabled'))
  endif

  if actions->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  var text: list<string> = []
  var act: dict<any>
  for i in actions->len()->range()
    act = actions[i]
    var t: string = act.title->substitute('\r\n', '\\r\\n', 'g')
    t = t->substitute('\n', '\\n', 'g')
    text->add(printf(" %d. %s ", i + 1, t))
  endfor

  var choice: number

  var query_ = query->trim()
  if query_ =~ '^\d\+$'	# digit
    choice = query_->str2nr()
  elseif query_ =~ '^/'	# regex
    choice = 1 + util.Indexof(actions, (i, a) => a.title =~ query_[1 : ])
  elseif query_ != ''	# literal string
    choice = 1 + util.Indexof(actions, (i, a) => a.title[0 : query_->len() - 1] == query_)
  elseif opt.lspOptions.usePopupInCodeAction
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
      callback: (_, result) => {
	# Invalid item selected or closed the popup
	if result <= 0 || result > text->len()
	  return
	endif

	# Do the code action
	HandleCodeAction(lspserver, actions[result - 1])
      },
      filter: (winid, key) => {
	if key == 'h' || key == 'l'
	  winid->popup_close(-1)
	elseif key->str2nr() > 0
	  # assume less than 10 entries are present
	  winid->popup_close(key->str2nr())
	else
	  return popup_filter_menu(winid, key)
	endif
	return 1
      },
    })
  else
    choice = inputlist(['Code action:'] + text)
  endif

  if choice < 1 || choice > text->len()
    return
  endif

  HandleCodeAction(lspserver, actions[choice - 1])
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
