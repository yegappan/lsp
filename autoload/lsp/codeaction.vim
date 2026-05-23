vim9script

# Functions related to handling LSP code actions to fix diagnostics.

import './util.vim'
import './textedit.vim'
import './options.vim' as opt
import './buffer.vim' as buf

var CommandHandlers: dict<func>

export def RegisterCmdHandler(cmd: string, Handler: func)
  CommandHandlers[cmd] = Handler
enddef

export def DoCommand(lspserver: dict<any>, cmd: dict<any>)
  if cmd->has_key('command') && CommandHandlers->has_key(cmd.command)
    # Prefer client-side handlers for known commands (for example custom
    # integrations). Unknown commands are delegated back to the originating
    # server via workspace/executeCommand.
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

  var codeAction = selAction

  # If we don't have a complete CodeAction then use the servers's CodeAction
  # property resolution to complete the definition.
  if !selAction->has_key('edit') && !selAction->has_key('command')
    lspserver.traceLog("Resolving incomplete CodeAction")
    var resolved = lspserver.resolveCodeAction(selAction)
    if resolved->empty()
      util.WarnMsg("Code action could not be resolved by LSP server.")
      return
    endif
    codeAction = resolved
  endif

  if codeAction->has_key('edit')
     || (codeAction->has_key('command') && codeAction.command->type() == v:t_dict)
    # codeAction is a CodeAction instance, apply edit and command
    if codeAction->has_key('edit')
      # apply edit first
      textedit.ApplyWorkspaceEdit(codeAction.edit)
    endif
    if codeAction->has_key('command')
      DoCommand(lspserver, codeAction.command)
    endif
  else
    # codeAction is a Command instance, apply it directly
    DoCommand(lspserver, codeAction)
  endif
enddef

def SortCodeActions(actions: list<dict<any>>): list<dict<any>>
  var ranked: list<dict<any>> = []

  for i in actions->len()->range()
    ranked->add({
	index: i,
	preferredRank: actions[i]->get('isPreferred', false) ? 0 : 1,
	action: actions[i],
      })
  endfor

  # Stable preferred-first ordering: rank by isPreferred, then preserve
  # original server-provided order within the same rank.
  ranked->sort((a, b) => a.preferredRank == b.preferredRank
	? a.index - b.index
	: a.preferredRank - b.preferredRank)

  return ranked->map((_, item) => item.action)
enddef

def ActionMenuText(actions: list<dict<any>>): list<string>
  var duplicateTitles = GetDuplicateActionTitles(actions)
  var actionListLength = actions->len()

  var bitfield = opt.lspOptions.codeActionPopupDetailsBitfield
  var hasKind: bool = and(bitfield, opt.CODEACTIONDETAILS_KIND) != 0
  var hasFullKind: bool = and(bitfield, opt.CODEACTIONDETAILS_FULLKIND) != 0
  var hasServer: bool = and(bitfield, opt.CODEACTIONDETAILS_SERVER) != 0

  var strings: list<dict<string>> = []
  var widths: list<dict<number>> = []
  var longest = { title: 0, kind: 0, server: 0}

  for act in actions
    var hasDuplicateTitle: bool = duplicateTitles->has_key(act->get('title', ''))
    var width: dict<number> = {}
    var string: dict<string> = {}

    string.title = act.title->substitute('\r\n\|\n', '\\n', 'g')
    if act->get('isPreferred', false)
      string.title = '*' .. string.title
    endif

    string.kind = ''
    if hasKind
      string.kind = substitute(act->get('kind', ''), '\..*$', '', '')
    elseif hasFullKind
      string.kind = act->get('kind', '')
    endif

    if !empty(string.kind)
      string.kind = printf("[%s]", string.kind)
    endif

    string.server = ''
    if hasServer || hasDuplicateTitle
      string.server = printf("[%s]", act->get('__lsp_server_name', ''))
    endif

    strings->add(string)

    # Compute widths
    width.title = strdisplaywidth(string.title)
    width.kind = strdisplaywidth(string.kind)
    width.server = strdisplaywidth(string.server)
    width.postfix = width.server + width.kind
    widths->add(width)

    # Compute maxima
    longest.title = max([longest.title, width.title])
    longest.kind = max([longest.kind, width.kind])
    longest.server = max([longest.server, width.server])
  endfor

  var popupText: list<string> = []

  var minPadding = 4
  var numWidth = actionListLength->string()->len()
  var longestPostfix = longest.kind + longest.server
  var popupWidth = longest.title + longestPostfix + minPadding

  for i in actionListLength->range()
    var act = actions[i]
    var hasDuplicateTitle: bool = duplicateTitles->has_key(act->get('title', ''))

    var numPrefix = printf(' %*d. ', numWidth, i + 1)
    var line: string

    if !hasKind && !hasFullKind && !hasServer && !hasDuplicateTitle
      line = numPrefix .. strings[i].title .. ' '
    else
      var postfix = ''
      if !empty(strings[i].kind)
	postfix ..= strings[i].kind
      endif

      if !empty(strings[i].server)
	if !empty(postfix)
	  postfix ..= ' '
	endif
	postfix ..= strings[i].server
      endif

      var padding = max([minPadding, popupWidth - widths[i].title - widths[i].postfix -
	(longest.server - widths[i].server)])
      line = numPrefix .. strings[i].title .. repeat(' ', padding) .. postfix .. ' '
    endif
    popupText->add(line)
  endfor

  return popupText
enddef

def GetDuplicateActionTitles(actions: list<dict<any>>): dict<bool>
  # Server labels are shown only for duplicate titles to avoid noisy menus.
  var titleCount: dict<number> = {}

  for act in actions
    var title = act->get('title', '')
    titleCount[title] = titleCount->get(title, 0) + 1
  endfor

  var duplicateTitles: dict<bool> = {}
  for [title, count] in titleCount->items()
    if count > 1
      duplicateTitles[title] = true
    endif
  endfor

  return duplicateTitles
enddef

def ResolveActionServer(defaultServer: dict<any>, action: dict<any>): dict<any>
  var lspserver = defaultServer

  # Multi-server actions include source metadata injected at aggregation time.
  # Look up the live server by id so resolve/executeCommand is routed correctly.
  if action->has_key('__lsp_server_id')
    lspserver = buf.BufLspServerGetById(bufnr(), action.__lsp_server_id)
    if lspserver->empty() || !lspserver.running || !lspserver.ready
      util.WarnMsg('Code action source LSP server is no longer available')
      return {}
    endif
  endif

  if lspserver->empty()
    util.WarnMsg('No language server is available to execute code action')
    return {}
  endif

  return lspserver
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
    # Disabled actions are often explanatory-only placeholders.
    actions = actions->filter((ix, act) => !act->has_key('disabled'))
  endif
  actions = SortCodeActions(actions)

  if actions->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  var text = ActionMenuText(actions)

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
    var popupAttrs = opt.PopupConfigure('CodeAction', {
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

  # Selection precedence: numeric index, regexp, literal prefix, then UI.
  # Resolve the source server at selection-time in case servers changed
  # between request and user choice.
  var action = actions[result - 1]
  var actionServer = ResolveActionServer(lspserver, action)
  if actionServer->empty()
    return
  endif
  HandleCodeAction(actionServer, action)
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
    popup_create(text, popupAttrs)
  else
    choice = inputlist(['Code action:'] + text)
  endif

  if choice < 1 || choice > text->len()
    return
  endif

  var action = actions[choice - 1]
  # Route execution to the server that supplied this action.
  var actionServer = ResolveActionServer(lspserver, action)
  if actionServer->empty()
    return
  endif

  HandleCodeAction(actionServer, action)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
