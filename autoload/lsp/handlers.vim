vim9script

# Handlers for messages from the LSP server
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specification.

import './util.vim'
import './diag.vim'
import './textedit.vim'
import './buffer.vim' as buf

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
def ProcessDiagNotif(lspserver: dict<any>, reply: dict<any>): void
  # For pull-capable servers, diagnostics come from textDocument/diagnostic.
  # Ignore push notifications from such servers.
  if lspserver.isDiagnosticsProvider
    return
  endif

  var params = reply.params
  diag.DiagNotification(lspserver, params.uri, params.diagnostics)
enddef

# Convert LSP message type to a string
def LspMsgTypeToString(lspMsgType: number): string
  var msgStrMap: list<string> = ['', 'Error', 'Warning', 'Info', 'Log']
  var mtype: string = 'Log'
  if lspMsgType > 0 && lspMsgType < 5
    mtype = msgStrMap[lspMsgType]
  endif
  return mtype
enddef

# process a show notification message from the LSP server
# Notification: window/showMessage
# Param: ShowMessageParams
def ProcessShowMsgNotif(lspserver: dict<any>, reply: dict<any>)
  var msgType = reply.params.type
  if msgType >= 4
    # ignore log messages from the LSP server (too chatty)
    # TODO: Add a configuration to control the message level that will be
    # displayed. Also store these messages and provide a command to display
    # them.
    return
  endif
  if msgType == 1
    util.ErrMsg($'Lsp({lspserver.name}) {reply.params.message}')
  elseif msgType == 2
    util.WarnMsg($'Lsp({lspserver.name}) {reply.params.message}')
  elseif msgType == 3
    util.InfoMsg($'Lsp({lspserver.name}) {reply.params.message}')
  endif
enddef

# process a log notification message from the LSP server
# Notification: window/logMessage
# Param: LogMessageParams
def ProcessLogMsgNotif(lspserver: dict<any>, reply: dict<any>)
  var params = reply.params
  var mtype = LspMsgTypeToString(params.type)
  lspserver.addMessage(mtype, params.message)
enddef

# process the log trace notification messages
# Notification: $/logTrace
# Param: LogTraceParams
def ProcessLogTraceNotif(lspserver: dict<any>, reply: dict<any>)
  lspserver.addMessage('trace', reply.params.message)
enddef

# process unsupported notification messages
def ProcessUnsupportedNotif(lspserver: dict<any>, reply: dict<any>)
  lspserver.traceLog($'Error: Unsupported notification message received: {reply->string()}')
enddef

# Dict to process telemetry notification messages only once per filetype
var telemetryProcessed: dict<bool> = {}
# process unsupported notification messages only once
def ProcessUnsupportedNotifOnce(lspserver: dict<any>, reply: dict<any>)
  if !telemetryProcessed->get(&ft, false)
    ProcessUnsupportedNotif(lspserver, reply)
    telemetryProcessed->extend({[&ft]: true})
  endif
enddef

# Global progress state: { token: { title, message, percentage, serverName } }
if !exists('g:LspProgress')
  g:LspProgress = {}
endif

# process the $/progress notification
# Notification: $/progress
# Param: ProgressParams { token, value: WorkDoneProgressBegin | Report | End }
def ProcessProgressNotif(lspserver: dict<any>, reply: dict<any>)
  var params = reply.params
  var token = params.token
  var tokenKey = token->string()
  var value = params.value

  lspserver.supportsWorkDoneProgress = true

  if value.kind == 'begin'
    lspserver.workDoneProgressTokens[tokenKey] = true
    g:LspProgress[token] = {
      title: value->get('title', ''),
      message: value->get('message', ''),
      percentage: value->get('percentage', -1),
      serverName: lspserver.name
    }
  elseif value.kind == 'report'
    if g:LspProgress->has_key(token)
      if value->has_key('message')
        g:LspProgress[token].message = value.message
      endif
      if value->has_key('percentage')
        g:LspProgress[token].percentage = value.percentage
      endif
    endif
  elseif value.kind == 'end'
    lspserver.sawWorkDoneProgressEnd = true
    if lspserver.workDoneProgressTokens->has_key(tokenKey)
      lspserver.workDoneProgressTokens->remove(tokenKey)
    endif
    if g:LspProgress->has_key(token)
      g:LspProgress->remove(token)
    endif
  endif

  if lspserver.isDiagnosticsProvider
    lspserver.queuePullDiagnosticsAllBuffers()
  endif

  # Trigger statusline refresh
  if exists('#User#LspProgressUpdate')
    doautocmd <nomodeline> User LspProgressUpdate
  endif
enddef

# process notification messages from the LSP server
export def ProcessNotif(lspserver: dict<any>, reply: dict<any>): void
  var lsp_notif_handlers: dict<func> =
    {
      'window/showMessage': ProcessShowMsgNotif,
      'window/logMessage': ProcessLogMsgNotif,
      'textDocument/publishDiagnostics': ProcessDiagNotif,
      '$/logTrace': ProcessLogTraceNotif,
      'telemetry/event': ProcessUnsupportedNotifOnce,
      '$/progress': ProcessProgressNotif,
    }

  # Explicitly ignored notification messages (many of them are specific to a
  # particular language server)
  var lsp_ignored_notif_handlers: list<string> =
    [
      '$/status/report',
      '$/status/show',
      # PHP intelephense server sends the "indexingStarted" and
      # "indexingEnded" notifications which is not in the LSP specification.
      'indexingStarted',
      'indexingEnded',
      # Java language server sends the 'language/status' notification which is
      # not in the LSP specification.
      'language/status',
      # Typescript language server sends the '$/typescriptVersion'
      # notification which is not in the LSP specification.
      '$/typescriptVersion',
      # Dart language server sends the '$/analyzerStatus' notification which
      # is not in the LSP specification.
      '$/analyzerStatus',
      # pyright language server notifications
      'pyright/beginProgress',
      'pyright/reportProgress',
      'pyright/endProgress',
      'eslint/status',
      'taplo/didChangeSchemaAssociation',
      'sqlLanguageServer.finishSetup',
      # ccls language server notifications
      '$ccls/publishSkippedRanges',
      '$ccls/publishSemanticHighlight',
      # omnisharp language server notifications
      'o#/backgrounddiagnosticstatus',
      'o#/msbuildprojectdiagnostics',
      'o#/projectadded',
      'o#/projectchanged',
      'o#/projectconfiguration',
      'o#/projectdiagnosticstatus',
      'o#/unresolveddependencies',
      '@/tailwindCSS/projectInitialized',
      # lua-language-server sends a "hello world" message on start-up.
      '$/hello',
      # bitbake language server notifications
      'bitbake/EmbeddedLanguageDocs',
      # devicetree language server notifications
      'devicetree/activeContextStableNotification',
      'devicetree/contextCreated',
      'devicetree/contextDeleted',
      'devicetree/contextStableNotification',
      'devicetree/newActiveContext',
      'devicetree/settingsChanged',
    ]

  if lsp_notif_handlers->has_key(reply.method)
    lsp_notif_handlers[reply.method](lspserver, reply)
  elseif lspserver.customNotificationHandlers->has_key(reply.method)
    lspserver.customNotificationHandlers[reply.method](lspserver, reply)
  elseif lsp_ignored_notif_handlers->index(reply.method) == -1
    ProcessUnsupportedNotif(lspserver, reply)
  endif
enddef

# process the workspace/applyEdit LSP server request
# Request: "workspace/applyEdit"
# Param: ApplyWorkspaceEditParams
def ProcessApplyEditReq(lspserver: dict<any>, request: dict<any>)
  # interface ApplyWorkspaceEditParams
  if !ValidateObjectParams(lspserver, request, 'workspace/applyEdit')
    return
  endif

  var workspaceEditParams: dict<any> = request.params
  if !workspaceEditParams->has_key('edit')
    SendInvalidParamsError(lspserver, request,
      'workspace/applyEdit params.edit is required')
    return
  endif

  if workspaceEditParams->has_key('label')
    util.InfoMsg($'Workspace edit {workspaceEditParams.label}')
  endif
  textedit.ApplyWorkspaceEdit(workspaceEditParams.edit)
  # TODO: Need to return the proper result of the edit operation
  lspserver.sendResponse(request, {applied: true}, {})
enddef

# process the workspace/workspaceFolders LSP server request
# Request: "workspace/workspaceFolders"
# Param: none
def ProcessWorkspaceFoldersReq(lspserver: dict<any>, request: dict<any>)
  if !ValidateNoParams(lspserver, request, 'workspace/workspaceFolders')
    return
  endif

  if !lspserver->has_key('workspaceFolders')
    lspserver.sendResponse(request, null, {})
    return
  endif
  if lspserver.workspaceFolders->empty()
    lspserver.sendResponse(request, [], {})
  else
    lspserver.sendResponse(request,
	  \ lspserver.workspaceFolders->copy()->map('{name: v:val->fnamemodify(":t"), uri: util.LspFileToUri(v:val)}'),
	  \ {})
  endif
enddef

# process the workspace/configuration LSP server request
# Request: "workspace/configuration"
# Param: ConfigurationParams
def ProcessWorkspaceConfiguration(lspserver: dict<any>, request: dict<any>)
  if !ValidateObjectParams(lspserver, request, 'workspace/configuration')
    return
  endif

  if !request.params->has_key('items')
    SendInvalidParamsError(lspserver, request,
      'workspace/configuration params.items is required')
    return
  endif
  if request.params.items->type() != v:t_list
    SendInvalidParamsError(lspserver, request,
      'workspace/configuration params.items must be an array')
    return
  endif

  var items = request.params.items
  var response = items->map((_, item) => lspserver.workspaceConfigGet(item))

  # Server expect null value if no config is given
  if response->type() == v:t_list && response->len() == 1
    && response[0]->type() == v:t_dict
    && response[0] == null_dict
    response[0] = null
  endif

  lspserver.sendResponse(request, response, {})
enddef

# process the window/workDoneProgress/create LSP server request
# Request: "window/workDoneProgress/create"
# Param: none
def ProcessWorkDoneProgressCreate(lspserver: dict<any>, request: dict<any>)
  if !ValidateObjectParams(lspserver, request, 'window/workDoneProgress/create')
    return
  endif

  if !request.params->has_key('token')
    SendInvalidParamsError(lspserver, request,
      'window/workDoneProgress/create params.token is required')
    return
  endif

  lspserver.supportsWorkDoneProgress = true
  lspserver.sendResponse(request, null, {})
enddef

# process the window/showMessageRequest LSP server request
# Request: "window/showMessageRequest"
# Param: ShowMessageRequestParams
def ProcessShowMessageRequest(lspserver: dict<any>, req: dict<any>)
  if !ValidateObjectParams(lspserver, req, 'window/showMessageRequest')
    return
  endif

  var params: dict<any> = req.params
  if !params->has_key('message')
    SendInvalidParamsError(lspserver, req,
      'window/showMessageRequest params.message is required')
    return
  endif
  if params.message->type() != v:t_string
    SendInvalidParamsError(lspserver, req,
      'window/showMessageRequest params.message must be a string')
    return
  endif

  if params->has_key('actions')
    if params.actions->type() != v:t_list
      SendInvalidParamsError(lspserver, req,
        'window/showMessageRequest params.actions must be an array')
      return
    endif

    var actions: list<dict<any>> = params.actions
    if actions->empty()
      util.WarnMsg($'Empty actions in showMessage request {params.message}')
      lspserver.sendResponse(req, null, {})
      return
    endif

    # Generate a list of strings from the action titles
    var text: list<string> = []
    var act: dict<any>
    for i in actions->len()->range()
      act = actions[i]
      if act->type() != v:t_dict || !act->has_key('title')
        SendInvalidParamsError(lspserver, req,
          'window/showMessageRequest action must contain title')
        return
      endif
      if act.title->type() != v:t_string
        SendInvalidParamsError(lspserver, req,
          'window/showMessageRequest action title must be a string')
        return
      endif
      var t: string = act.title->substitute('\r\n', '\\r\\n', 'g')
      t = t->substitute('\n', '\\n', 'g')
      text->add(printf(" %d. %s ", i + 1, t))
    endfor

    # Ask the user to choose one of the actions
    var choice: number = inputlist([params.message] + text)
    if choice < 1 || choice > text->len()
      lspserver.sendResponse(req, null, {})
      return
    endif
    lspserver.sendResponse(req, actions[choice - 1], {})
  else
    # No actions in the message. Simply display the message.
    ProcessShowMsgNotif(lspserver, req)
    lspserver.sendResponse(req, null, {})
  endif
enddef

# process the client/registerCapability LSP server request
# Request: "client/registerCapability"
# Param: RegistrationParams
# process the workspace/diagnostic/refresh LSP server request
# Request: "workspace/diagnostic/refresh"
# Param: none
# Re-pull diagnostics for all open buffers served by this server.
def ProcessDiagnosticRefreshReq(lspserver: dict<any>, request: dict<any>)
  if !ValidateNoParams(lspserver, request, 'workspace/diagnostic/refresh')
    return
  endif

  lspserver.sendResponse(request, null, {})
  for bnr in buf.BufGetServerBufnrs(lspserver)
    lspserver.pullDiagnostics(bnr)
  endfor
enddef

# process the client/registerCapability LSP server request
# Request: "client/registerCapability"
# Param: RegistrationParams
def ProcessClientRegisterCap(lspserver: dict<any>, request: dict<any>)
  if !ValidateObjectParams(lspserver, request, 'client/registerCapability')
    return
  endif

  if !request.params->has_key('registrations')
    SendInvalidParamsError(lspserver, request,
      'client/registerCapability params.registrations is required')
    return
  endif
  if request.params.registrations->type() != v:t_list
    SendInvalidParamsError(lspserver, request,
      'client/registerCapability params.registrations must be an array')
    return
  endif

  lspserver.sendResponse(request, null, {})
enddef

# process the client/unregisterCapability LSP server request
# Request: "client/unregisterCapability"
# Param: UnregistrationParams
def ProcessClientUnregisterCap(lspserver: dict<any>, request: dict<any>)
  if !ValidateObjectParams(lspserver, request, 'client/unregisterCapability')
    return
  endif

  if !request.params->has_key('unregisterations')
    SendInvalidParamsError(lspserver, request,
      'client/unregisterCapability params.unregisterations is required')
    return
  endif
  if request.params.unregisterations->type() != v:t_list
    SendInvalidParamsError(lspserver, request,
      'client/unregisterCapability params.unregisterations must be an array')
    return
  endif

  lspserver.sendResponse(request, null, {})
enddef

# Send a JSON-RPC MethodNotFound error for unsupported server requests.
def SendMethodNotFoundError(lspserver: dict<any>, request: dict<any>)
  var errmsg = $'Unsupported request method: {request.method}'
  lspserver.sendResponse(request, null,
    {code: -32601, message: 'Method not found', data: errmsg})
enddef

# Send a JSON-RPC InvalidRequest error for malformed request objects.
def SendInvalidRequestError(lspserver: dict<any>, request: dict<any>, errmsg: string)
  lspserver.sendResponse(request, null,
    {code: -32600, message: 'Invalid request', data: errmsg})
enddef

# Send a JSON-RPC InvalidParams error for malformed method parameters.
def SendInvalidParamsError(lspserver: dict<any>, request: dict<any>, errmsg: string)
  lspserver.sendResponse(request, null,
    {code: -32602, message: 'Invalid params', data: errmsg})
enddef

# Validate a request that must not include parameters.
def ValidateNoParams(lspserver: dict<any>, request: dict<any>, method: string): bool
  if !request->has_key('params')
    return true
  endif

  # Accept null or empty object for methods without params.
  if request.params == v:null
    return true
  endif
  if request.params->type() == v:t_dict && request.params->empty()
    return true
  endif

  SendInvalidParamsError(lspserver, request,
    $'{method} does not accept params')
  return false
enddef

# Validate a request that requires params to be an object.
def ValidateObjectParams(lspserver: dict<any>, request: dict<any>, method: string): bool
  if !request->has_key('params')
    SendInvalidRequestError(lspserver, request,
      $'{method} request is missing params')
    return false
  endif

  if request.params->type() != v:t_dict
    SendInvalidParamsError(lspserver, request,
      $'{method} params must be an object')
    return false
  endif

  return true
enddef

# process a request message from the server
export def ProcessRequest(lspserver: dict<any>, request: dict<any>)
  var lspRequestHandlers: dict<func> =
    {
      'client/registerCapability': ProcessClientRegisterCap,
      'client/unregisterCapability': ProcessClientUnregisterCap,
      'window/workDoneProgress/create': ProcessWorkDoneProgressCreate,
      'window/showMessageRequest': ProcessShowMessageRequest,
      'workspace/applyEdit': ProcessApplyEditReq,
      'workspace/configuration': ProcessWorkspaceConfiguration,
      'workspace/diagnostic/refresh': ProcessDiagnosticRefreshReq,
      'workspace/workspaceFolders': ProcessWorkspaceFoldersReq
      # TODO: Handle the following requests from the server:
      #     workspace/codeLens/refresh
      #     workspace/inlayHint/refresh
      #     workspace/inlineValue/refresh
      #     workspace/semanticTokens/refresh
    }

  # Explicitly ignored requests
  var lspIgnoredRequestHandlers: list<string> =
    [
      # Eclipse java language server sends the
      # 'workspace/executeClientCommand' request (to reload bundles) which is
      # not in the LSP specification.
      'workspace/executeClientCommand',
      # bitbake language server messages
      'bitbake/getRecipeLocalFiles'
    ]

  if lspRequestHandlers->has_key(request.method)
    lspRequestHandlers[request.method](lspserver, request)
  elseif lspserver.customRequestHandlers->has_key(request.method)
    lspserver.customRequestHandlers[request.method](lspserver, request)
  else
    SendMethodNotFoundError(lspserver, request)
    if lspIgnoredRequestHandlers->index(request.method) == -1
      lspserver.traceLog($'Error: Unsupported request message received: {request->string()}')
    endif
  endif
enddef

# process one or more LSP server messages
export def ProcessMessages(lspserver: dict<any>): void
  var idx: number
  var len: number
  var content: string
  var msg: dict<any>
  var req: dict<any>

  msg = lspserver.data
  if msg->has_key('result') || msg->has_key('error')
    # A response with an unknown id can happen for canceled or timed-out
    # requests. Ignore it and only trace for debugging.
    lspserver.traceLog($'Ignored response with unknown id from LSP server: {msg->string()}')
  elseif msg->has_key('id') && msg->has_key('method')
    # request message from the server
    lspserver.processRequest(msg)
  elseif msg->has_key('method')
    # notification message from the server
    lspserver.processNotif(msg)
  else
    util.ErrMsg($'Unsupported message ({msg->string()})')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
