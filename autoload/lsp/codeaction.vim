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
  # Look up the live server by id so resolve/executeCommand is routed
  # correctly.
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
export def ApplyCodeAction(lspserver: dict<any>,
			   actionlist: list<dict<any>>, query: string): void
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

# Check if current buffer has code action capable servers that are running and
# ready
export def CurbufGetCodeActionServersChecked(): list<dict<any>>
  var fname: string = @%
  var ft = &filetype
  if fname->empty() || ft->empty()
    return []
  endif

  # Code actions are aggregated from all attached servers that advertise and
  # have the feature enabled for this buffer.
  var lspservers: list<dict<any>> = buf.CurbufGetServers()->filter((_, lspserver) =>
	lspserver.isCodeActionProvider && lspserver.featureEnabled('codeAction'))

  if lspservers->empty()
    util.ErrMsg($'Language server for "{ft}" file type supporting "codeAction" feature is not found')
    return []
  endif

  lspservers = lspservers->filter((_, lspserver) => lspserver.running)
  # Keep existing command-level UX: fail early when all candidates are down.
  if lspservers->empty()
    util.ErrMsg($'Language server for "{ft}" file type is not running')
    return []
  endif

  lspservers = lspservers->filter((_, lspserver) => lspserver.ready)
  # As above, mirror single-server readiness checks for user-facing errors.
  if lspservers->empty()
    util.ErrMsg($'Language server for "{ft}" file type is not ready')
    return []
  endif

  return lspservers
enddef

# Callback for multi-server code action aggregation in CodeAction command
export def CodeActionReply(state: dict<any>, lspserver: dict<any>,
			   actionlist: list<dict<any>>, selectorQuery: string,
			   rpcError: dict<any>)
  # The request-side parser may normalize selectors (for example only:/kind:).
  # All callbacks for one invocation produce the same selector, so capture
  # once.
  if state.selectorQuery == ''
    state.selectorQuery = selectorQuery
  endif

  # Aggregate partial success: an error from one server must not hide actions
  # returned by other servers.
  if rpcError->empty() && !actionlist->empty()
    for act in actionlist
      var action = act->deepcopy()
      # Persist source-server metadata so selection-time execution can be
      # routed back to the server that produced this action.
      action.__lsp_server_id = lspserver.id
      action.__lsp_server_name = lspserver.name
      state.actions->add(action)
    endfor
  endif

  # Wait until every server has replied before opening a single merged menu.
  state.pending -= 1
  if state.pending > 0
    return
  endif

  # Use {} here because each action carries its own source-server metadata.
  ApplyCodeAction({}, state.actions, state.selectorQuery)
enddef

# Helper: Process a single diagnostic from an AutoFix range
export def AutoFixProcessDiag(diags: list<dict<any>>,
			      idx: number, state: dict<any>): void
  if idx >= diags->len()
    return
  endif

  var diag = diags[idx]
  var dline = diag.range.start.line + 1
  var servers = state.servers
  var fname = state.fname

  for lspserver in servers
    lspserver.codeActionAsync(fname, dline, dline, '',
      (lsp, actions, _, rpcErr) => AutoFixDiagActionReply(lsp, actions, rpcErr, diags, idx, diag, state))
  endfor
enddef

# Helper: Handle code action reply for AutoFix diagnostic
def AutoFixDiagActionReply(lspserver: dict<any>, actions: list<dict<any>>,
    rpcError: dict<any>, diags: list<dict<any>>, idx: number, diag: dict<any>,
    state: dict<any>): void
  if !rpcError->empty()
    state.pending -= 1
    if state.pending == 0 && !state.handled && !state.errorOccurred
      AutoFixProcessDiag(diags, idx + 1, state)
    endif
    return
  endif

  # Filter actions to those that match this diagnostic
  var matchingActions = []
  var preferred = []
  for act in actions
    var matches = false
    if act->has_key('diagnostics')
      for ad in act.diagnostics
        if ad.range->string() == diag.range->string()
          matches = true
          break
        endif
      endfor
    else
      matches = true
    endif

    if matches
      matchingActions->add(act)
      if act->get('isPreferred', false)
        preferred->add(act)
      endif
    endif
  endfor

  # Decide which action(s) to process
  var actionsToShow = []
  if !preferred->empty()
    # Prefer the preferred actions
    actionsToShow = preferred
  elseif matchingActions->len() == 1
    # Single non-preferred action: apply it anyway
    actionsToShow = matchingActions
  else
    # No preferred and multiple non-preferred (or no actions at all): skip
    state.pending -= 1
    if state.pending == 0 && !state.handled && !state.errorOccurred
      AutoFixProcessDiag(diags, idx + 1, state)
    endif
    return
  endif

  if actionsToShow->len() == 1
    try
      HandleCodeAction(lspserver, actionsToShow[0])
    catch
      state.errorOccurred = true
      return
    endtry
    state.handled = true
    AutoFixProcessDiag(diags, idx + 1, state)
  else
    var menu = []
    for act in actionsToShow
      menu->add(ActionMenuText(act))
    endfor
    var choice = inputlist(['Select code action:'] + menu)
    AutoFixDiagOnChosenAction(choice, actionsToShow, lspserver, diags, idx, state)
  endif
enddef

# Helper: Handle user choice for multiple code actions in AutoFix
def AutoFixDiagOnChosenAction(chosenIdx: number, actions: list<dict<any>>,
			      lspserver: dict<any>, diags: list<dict<any>>,
			      idx: number, state: dict<any>): void
  if chosenIdx < 1 || chosenIdx > actions->len()
    # User cancelled
    AutoFixProcessDiag(diags, idx + 1, state)
    return
  endif

  var chosen = actions[chosenIdx - 1]
  try
    HandleCodeAction(lspserver, chosen)
  catch
    state.errorOccurred = true
    return
  endtry
  state.handled = true
  AutoFixProcessDiag(diags, idx + 1, state)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
