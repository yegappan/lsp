vim9script

# Handlers for messages from the LSP server
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specification.

import './util.vim'
import './diag.vim'
import './textedit.vim'

# Process various reply messages from the LSP server
export def ProcessReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  util.ErrMsg($'Unsupported reply received from LSP server: {reply->string()} for request: {req->string()}')
enddef

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
def ProcessDiagNotif(lspserver: dict<any>, reply: dict<any>): void
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
  util.WarnMsg($'Unsupported notification message received from the LSP server ({lspserver.name}), message = {reply->string()}')
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

# process notification messages from the LSP server
export def ProcessNotif(lspserver: dict<any>, reply: dict<any>): void
  var lsp_notif_handlers: dict<func> =
    {
      'window/showMessage': ProcessShowMsgNotif,
      'window/logMessage': ProcessLogMsgNotif,
      'textDocument/publishDiagnostics': ProcessDiagNotif,
      '$/logTrace': ProcessLogTraceNotif,
      'telemetry/event': ProcessUnsupportedNotifOnce,
    }

  # Explicitly ignored notification messages (many of them are specific to a
  # particular language server)
  var lsp_ignored_notif_handlers: list<string> =
    [
      '$/progress',
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
      '@/tailwindCSS/projectInitialized'
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
  if !request->has_key('params')
    return
  endif
  var workspaceEditParams: dict<any> = request.params
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
  lspserver.sendResponse(request, null, {})
enddef

# process the window/showMessageRequest LSP server request
# Request: "window/showMessageRequest"
# Param: ShowMessageRequestParams
def ProcessShowMessageRequest(lspserver: dict<any>, request: dict<any>)
  # TODO: for now 'showMessageRequest' handled same like 'showMessage'
  # regardless 'actions'
  ProcessShowMsgNotif(lspserver, request)
  lspserver.sendResponse(request, null, {})
enddef

# process the client/registerCapability LSP server request
# Request: "client/registerCapability"
# Param: RegistrationParams
def ProcessClientRegisterCap(lspserver: dict<any>, request: dict<any>)
  lspserver.sendResponse(request, null, {})
enddef

# process the client/unregisterCapability LSP server request
# Request: "client/unregisterCapability"
# Param: UnregistrationParams
def ProcessClientUnregisterCap(lspserver: dict<any>, request: dict<any>)
  lspserver.sendResponse(request, null, {})
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
      'workspace/workspaceFolders': ProcessWorkspaceFoldersReq
      # TODO: Handle the following requests from the server:
      #     workspace/codeLens/refresh
      #     workspace/diagnostic/refresh
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
    ]

  if lspRequestHandlers->has_key(request.method)
    lspRequestHandlers[request.method](lspserver, request)
  elseif lspserver.customRequestHandlers->has_key(request.method)
    lspserver.customRequestHandlers[request.method](lspserver, request)
  elseif lspIgnoredRequestHandlers->index(request.method) == -1
    util.ErrMsg($'Unsupported request message received from the LSP server ({lspserver.name}), message = {request->string()}')
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
    # response message from the server
    req = lspserver.requests->get(msg.id->string(), {})
    if !req->empty()
      # Remove the corresponding stored request message
      lspserver.requests->remove(msg.id->string())

      if msg->has_key('result')
	lspserver.processReply(req, msg)
      else
	# request failed
	var emsg: string = msg.error.message
	emsg ..= $', code = {msg.error.code}'
	if msg.error->has_key('data')
	  emsg ..= $', data = {msg.error.data->string()}'
	endif
	util.ErrMsg($'request {req.method} failed ({emsg})')
      endif
    endif
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

# vim: tabstop=8 shiftwidth=2 softtabstop=2
