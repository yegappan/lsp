vim9script

# Functions related to handling LSP code actions to fix diagnostics.

import './util.vim'
import './textedit.vim'
import './options.vim' as opt

var CommandHandlers: dict<func>

export def RegisterCmdHandler(cmd: string, Handler: func)
  CommandHandlers[cmd] = Handler
enddef

def DoCommand(lspserver: dict<any>, cmd: dict<any>)
  if CommandHandlers->has_key(cmd.command)
    var CmdHandler: func = CommandHandlers[cmd.command]
    call CmdHandler(cmd)
  else
    lspserver.executeCommand(cmd)
  endif
enddef

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
      DoCommand(lspserver, selAction.command)
    endif
  else
    # selAction is a Command instance, apply it directly
    DoCommand(lspserver, selAction)
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
  for i in actions->len()->range()
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
      choice = inputlist(["Code action:"] + text)
    endif
  endif

  if choice < 1 || choice > text->len()
    return
  endif

  HandleCodeAction(lspserver, actions[choice - 1])
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
