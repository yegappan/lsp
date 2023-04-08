vim9script

# LSP server functions
#
# The functions to send request messages to the language server are in this
# file.
#
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specificaiton.

import './options.vim' as opt
import './handlers.vim'
import './util.vim'
import './capabilities.vim'
import './diag.vim'
import './selection.vim'
import './symbol.vim'
import './textedit.vim'
import './completion.vim'
import './hover.vim'
import './signature.vim'
import './codeaction.vim'
import './codelens.vim'
import './callhierarchy.vim' as callhier
import './typehierarchy.vim' as typehier
import './inlayhints.vim'

# LSP server standard output handler
def Output_cb(lspserver: dict<any>, chan: channel, msg: any): void
  lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Received {msg->string()}')
  lspserver.data = msg
  lspserver.processMessages()
enddef

# LSP server error output handler
def Error_cb(lspserver: dict<any>, chan: channel, emsg: string): void
  lspserver.errorLog(emsg)
enddef

# LSP server exit callback
def Exit_cb(lspserver: dict<any>, job: job, status: number): void
  util.WarnMsg($'{strftime("%m/%d/%y %T")}: LSP server exited with status {status}')
  lspserver.running = false
  lspserver.ready = false
  lspserver.requests = {}
enddef

# Start a LSP server
#
def StartServer(lspserver: dict<any>, bnr: number): number
  if lspserver.running
    util.WarnMsg('LSP server for is already running')
    return 0
  endif

  var cmd = [lspserver.path]
  cmd->extend(lspserver.args)

  var opts = {in_mode: 'lsp',
		out_mode: 'lsp',
		err_mode: 'raw',
		noblock: 1,
		out_cb: function(Output_cb, [lspserver]),
		err_cb: function(Error_cb, [lspserver]),
		exit_cb: function(Exit_cb, [lspserver])}

  lspserver.data = ''
  lspserver.caps = {}
  lspserver.nextID = 1
  lspserver.requests = {}
  lspserver.omniCompletePending = false
  lspserver.completionLazyDoc = false
  lspserver.completionTriggerChars = []
  lspserver.signaturePopup = -1
  lspserver.workspaceFolders = [bnr->bufname()->fnamemodify(':p:h')]

  var job = cmd->job_start(opts)
  if job->job_status() == 'fail'
    util.ErrMsg($'Error: Failed to start LSP server {lspserver.path}')
    return 1
  endif

  # wait a little for the LSP server to start
  sleep 10m

  lspserver.job = job
  lspserver.running = true

  lspserver.initServer(bnr)

  return 0
enddef

# process the 'initialize' method reply from the LSP server
# Result: InitializeResult
def ServerInitReply(lspserver: dict<any>, initResult: dict<any>): void
  if initResult->empty()
    return
  endif

  var caps: dict<any> = initResult.capabilities
  lspserver.caps = caps

  for [key, val] in initResult->items()
    if key == 'capabilities'
      continue
    endif

    lspserver.caps[$'~additionalInitResult_{key}'] = val
  endfor

  capabilities.ProcessServerCaps(lspserver, caps)

  if opt.lspOptions.autoComplete && caps->has_key('completionProvider')
    lspserver.completionTriggerChars =
			caps.completionProvider->get('triggerCharacters', [])
    lspserver.completionLazyDoc =
			caps.completionProvider->get('resolveProvider', false)
  endif

  # send a "initialized" notification to server
  lspserver.sendInitializedNotif()
  # send any workspace configuration (optional)
  if !lspserver.workspaceConfig->empty()
    lspserver.sendWorkspaceConfig()
  endif
  lspserver.ready = true
  if exists($'#User#LspServerReady{lspserver.name}')
    exe $'doautocmd <nomodeline> User LspServerReady{lspserver.name}'
  endif

  # if the outline window is opened, then request the symbols for the current
  # buffer
  if bufwinid('LSP-Outline') != -1
    lspserver.getDocSymbols(@%)
  endif

  # Update the inlay hints (if enabled)
  if opt.lspOptions.showInlayHints && (lspserver.isInlayHintProvider
				    || lspserver.isClangdInlayHintsProvider)
    inlayhints.LspInlayHintsUpdateNow()
  endif
enddef

# Request: 'initialize'
# Param: InitializeParams
def InitServer(lspserver: dict<any>, bnr: number)
  # interface 'InitializeParams'
  var initparams: dict<any> = {}
  initparams.processId = getpid()
  initparams.clientInfo = {
	name: 'Vim',
	version: v:versionlong->string(),
      }

  # Compute the rootpath (based on the directory of the buffer)
  var bufDir = bnr->bufname()->fnamemodify(':p:h')
  var rootPath = ''
  var rootSearchFiles = lspserver.rootSearchFiles
  if !rootSearchFiles->empty()
    rootPath = util.FindNearestRootDir(bufDir, rootSearchFiles)
  endif
  if rootPath == ''
    rootPath = bufDir
  endif
  var rootUri = util.LspFileToUri(rootPath)
  initparams.rootPath = rootPath
  initparams.rootUri = rootUri
  initparams.workspaceFolders = [{
	name: rootPath->fnamemodify(':t'),
	uri: rootUri
     }]
  initparams.trace = 'off'
  initparams.capabilities = capabilities.GetClientCaps()
  if !lspserver.initializationOptions->empty()
    initparams.initializationOptions = lspserver.initializationOptions
  endif

  lspserver.rpc_a('initialize', initparams, ServerInitReply)
enddef

# Send a "initialized" notification to the language server
def SendInitializedNotif(lspserver: dict<any>)
  # Notification: 'initialized'
  # Params: InitializedParams
  lspserver.sendNotification('initialized')
enddef

# Request: shutdown
# Param: void
def ShutdownServer(lspserver: dict<any>): void
  lspserver.rpc('shutdown', {})
enddef

# Send a 'exit' notification to the language server
def ExitServer(lspserver: dict<any>): void
  # Notification: 'exit'
  # Params: void
  lspserver.sendNotification('exit')
enddef

# Stop a LSP server
def StopServer(lspserver: dict<any>): number
  if !lspserver.running
    util.WarnMsg('LSP server is not running')
    return 0
  endif

  # Send the shutdown request to the server
  lspserver.shutdownServer()

  # Notify the server to exit
  lspserver.exitServer()

  # Wait for the server to process the exit notification and exit for a
  # maximum of 2 seconds.
  var maxCount: number = 1000
  while lspserver.job->job_status() == 'run' && maxCount > 0
    sleep 2m
    maxCount -= 1
  endwhile

  if lspserver.job->job_status() == 'run'
    lspserver.job->job_stop()
  endif
  lspserver.running = false
  lspserver.ready = false
  lspserver.requests = {}
  return 0
enddef

# Set the language server trace level using the '$/setTrace' notification.
# Supported values for "traceVal" are "off", "messages" and "verbose".
def SetTrace(lspserver: dict<any>, traceVal: string)
  # Notification: '$/setTrace'
  # Params: SetTraceParams
  var params = {value: traceVal}
  lspserver.sendNotification('$/setTrace', params)
enddef

# Log a debug message to the LSP server debug file
def TraceLog(lspserver: dict<any>, msg: string)
  if lspserver.debug
    util.TraceLog(lspserver.logfile, false, msg)
  endif
enddef

# Log an error message to the LSP server error file
def ErrorLog(lspserver: dict<any>, errmsg: string)
  if lspserver.debug
    util.TraceLog(lspserver.errfile, true, errmsg)
  endif
enddef

# Return the next id for a LSP server request message
def NextReqID(lspserver: dict<any>): number
  var id = lspserver.nextID
  lspserver.nextID = id + 1
  return id
enddef

# create a LSP server request message
def CreateRequest(lspserver: dict<any>, method: string): dict<any>
  var req = {}
  req.jsonrpc = '2.0'
  req.id = lspserver.nextReqID()
  req.method = method
  req.params = {}

  # Save the request, so that the corresponding response can be processed
  lspserver.requests->extend({[req.id->string()]: req})

  return req
enddef

# create a LSP server response message
def CreateResponse(lspserver: dict<any>, req_id: number): dict<any>
  var resp = {}
  resp.jsonrpc = '2.0'
  resp.id = req_id

  return resp
enddef

# create a LSP server notification message
def CreateNotification(lspserver: dict<any>, notif: string): dict<any>
  var req = {}
  req.jsonrpc = '2.0'
  req.method = notif
  req.params = {}

  return req
enddef

# send a response message to the server
def SendResponse(lspserver: dict<any>, request: dict<any>, result: any, error: dict<any>)
  if (request.id->type() == v:t_string
	&& (request.id->trim() =~ '[^[:digit:]]\+'
	    || request.id->trim() == ''))
    || (request.id->type() != v:t_string && request.id->type() != v:t_number)
    util.ErrMsg('Error: request.id of response to LSP server is not a correct number')
    return
  endif
  var resp: dict<any> = lspserver.createResponse(
	    request.id->type() == v:t_string ? request.id->str2nr() : request.id)
  if error->empty()
    resp->extend({result: result})
  else
    resp->extend({error: error})
  endif
  lspserver.sendMessage(resp)
enddef

# Send a request message to LSP server
def SendMessage(lspserver: dict<any>, content: dict<any>): void
  var job = lspserver.job
  if job->job_status() != 'run'
    # LSP server has exited
    return
  endif
  job->ch_sendexpr(content)
  if content->has_key('id')
    lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Sent {content->string()}')
  endif
enddef

# Send a notification message to the language server
def SendNotification(lspserver: dict<any>, method: string, params: any = {})
  var notif: dict<any> = CreateNotification(lspserver, method)
  notif.params->extend(params)
  lspserver.sendMessage(notif)
enddef

# Send a sync RPC request message to the LSP server and return the received
# reply.  In case of an error, an empty Dict is returned.
def Rpc(lspserver: dict<any>, method: string, params: any, handleError: bool = true): dict<any>
  var req = {}
  req.method = method
  req.params = {}
  req.params->extend(params)

  var job = lspserver.job
  if job->job_status() != 'run'
    # LSP server has exited
    return {}
  endif

  lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Sent {req->string()}')

  # Do the synchronous RPC call
  var reply = job->ch_evalexpr(req)

  lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Received {reply->string()}')

  if reply->has_key('result')
    # successful reply
    return reply
  endif

  if reply->has_key('error') && handleError
    # request failed
    var emsg: string = reply.error.message
    emsg ..= $', code = {reply.error.code}'
    if reply.error->has_key('data')
      emsg ..= $', data = {reply.error.data->string()}'
    endif
    util.ErrMsg($'Error(LSP): request {method} failed ({emsg})')
  endif

  return {}
enddef

# LSP server asynchronous RPC callback
def AsyncRpcCb(lspserver: dict<any>, method: string, RpcCb: func, chan: channel, reply: dict<any>)
  lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Received {reply->string()}')

  if reply->empty()
    return
  endif

  if reply->has_key('error')
    # request failed
    var emsg: string
    emsg = $'{reply.error.message}, code = {reply.error.code}'
    if reply.error->has_key('data')
      emsg ..= $', data = {reply.error.data->string()}'
    endif
    util.ErrMsg($'Error(LSP): request {method} failed ({emsg})')
    return
  endif

  if !reply->has_key('result')
    util.ErrMsg($'Error(LSP): request {method} failed (no result)')
    return
  endif

  RpcCb(lspserver, reply.result)
enddef

# Send a async RPC request message to the LSP server with a callback function.
# Returns the LSP message id.  This id can be used to cancel the RPC request
# (if needed).  Returns -1 on error.
def AsyncRpc(lspserver: dict<any>, method: string, params: any, Cbfunc: func): number
  var req = {}
  req.method = method
  req.params = {}
  req.params->extend(params)

  var job = lspserver.job
  if job->job_status() != 'run'
    # LSP server has exited
    return -1
  endif

  lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Sent {req->string()}')

  # Do the asynchronous RPC call
  var Fn = function('AsyncRpcCb', [lspserver, method, Cbfunc])

  var reply: dict<any>
  if get(g:, 'LSPTest')
    # When running LSP tests, make this a synchronous RPC call
    reply = Rpc(lspserver, method, params)
    Fn(test_null_channel(), reply)
  else
    # Otherwise, make an asynchronous RPC call
    reply = job->ch_sendexpr(req, {callback: Fn})
  endif
  if reply->empty()
    return -1
  endif

  return reply.id
enddef

# Wait for a response message from the LSP server for the request "req"
# Waits for a maximum of 5 seconds
def WaitForResponse(lspserver: dict<any>, req: dict<any>)
  var maxCount: number = 2500
  var key: string = req.id->string()

  while lspserver.requests->has_key(key) && maxCount > 0
    sleep 2m
    maxCount -= 1
  endwhile
enddef

# Retrieve the Workspace configuration asked by the server.
# Request: workspace/configuration
def WorkspaceConfigGet(lspserver: dict<any>, configItem: dict<any>): dict<any>
  if lspserver.workspaceConfig->empty()
    return {}
  endif
  if !configItem->has_key('section') || configItem.section->empty()
    return lspserver.workspaceConfig
  endif
  var config: dict<any> = lspserver.workspaceConfig
  for part in configItem.section->split('\.')
    if !config->has_key(part)
      return {}
    endif
    config = config[part]
  endfor
  return config
enddef

# Send a "workspace/didChangeConfiguration" notification to the language
# server.
def SendWorkspaceConfig(lspserver: dict<any>)
  # Params: DidChangeConfigurationParams
  var params = {settings: lspserver.workspaceConfig}
  lspserver.sendNotification('workspace/didChangeConfiguration', params)
enddef

# Send a file/document opened notification to the language server.
def TextdocDidOpen(lspserver: dict<any>, bnr: number, ftype: string): void
  # Notification: 'textDocument/didOpen'
  # Params: DidOpenTextDocumentParams
  var tdi = {}
  tdi.uri = util.LspBufnrToUri(bnr)
  tdi.languageId = ftype
  tdi.version = 1
  tdi.text = bnr->getbufline(1, '$')->join("\n") .. "\n"
  var params = {textDocument: tdi}
  lspserver.sendNotification('textDocument/didOpen', params)
enddef

# Send a file/document closed notification to the language server.
def TextdocDidClose(lspserver: dict<any>, bnr: number): void
  # Notification: 'textDocument/didClose'
  # Params: DidCloseTextDocumentParams
  var tdid = {}
  tdid.uri = util.LspBufnrToUri(bnr)
  var params = {textDocument: tdid}
  lspserver.sendNotification('textDocument/didClose', params)
enddef

# Send a file/document change notification to the language server.
# Params: DidChangeTextDocumentParams
def TextdocDidChange(lspserver: dict<any>, bnr: number, start: number,
			end: number, added: number,
			changes: list<dict<number>>): void
  # Notification: 'textDocument/didChange'
  # Params: DidChangeTextDocumentParams
  var vtdid: dict<any> = {}
  vtdid.uri = util.LspBufnrToUri(bnr)
  # Use Vim 'changedtick' as the LSP document version number
  vtdid.version = bnr->getbufvar('changedtick')

  var changeset: list<dict<any>>

  ##### FIXME: Sending specific buffer changes to the LSP server doesn't
  ##### work properly as the computed line range numbers is not correct.
  ##### For now, send the entire buffer content to LSP server.
  # #     Range
  # for change in changes
  #   var lines: string
  #   var start_lnum: number
  #   var end_lnum: number
  #   var start_col: number
  #   var end_col: number
  #   if change.added == 0
  #     # lines changed
  #     start_lnum =  change.lnum - 1
  #     end_lnum = change.end - 1
  #     lines = getbufline(bnr, change.lnum, change.end - 1)->join("\n") .. "\n"
  #     start_col = 0
  #     end_col = 0
  #   elseif change.added > 0
  #     # lines added
  #     start_lnum = change.lnum - 1
  #     end_lnum = change.lnum - 1
  #     start_col = 0
  #     end_col = 0
  #     lines = getbufline(bnr, change.lnum, change.lnum + change.added - 1)->join("\n") .. "\n"
  #   else
  #     # lines removed
  #     start_lnum = change.lnum - 1
  #     end_lnum = change.lnum + (-change.added) - 1
  #     start_col = 0
  #     end_col = 0
  #     lines = ''
  #   endif
  #   var range: dict<dict<number>> = {'start': {'line': start_lnum, 'character': start_col}, 'end': {'line': end_lnum, 'character': end_col}}
  #   changeset->add({'range': range, 'text': lines})
  # endfor

  changeset->add({text: bnr->getbufline(1, '$')->join("\n") .. "\n"})
  var params = {textDocument: vtdid, contentChanges: changeset}
  lspserver.sendNotification('textDocument/didChange', params)
enddef

# Return the current cursor position as a LSP position.
# find_ident will search for a identifier in front of the cursor, just like
# CTRL-] and c_CTRL-R_CTRL-W does.
#
# LSP line and column numbers start from zero, whereas Vim line and column
# numbers start from one. The LSP column number is the character index in the
# line and not the byte index in the line.
def GetLspPosition(find_ident: bool): dict<number>
  var lnum: number = line('.') - 1
  var col: number = charcol('.') - 1
  var line = getline('.')

  if find_ident
    # 1. skip to start of identifier
    while line[col] != '' && line[col] !~ '\k'
      col = col + 1
    endwhile

    # 2. back up to start of identifier
    while col > 0 && line[col - 1] =~ '\k'
      col = col - 1
    endwhile
  endif

  return {line: lnum, character: col}
enddef

# Return the current file name and current cursor position as a LSP
# TextDocumentPositionParams structure
def GetLspTextDocPosition(find_ident: bool): dict<dict<any>>
  # interface TextDocumentIdentifier
  # interface Position
  return {textDocument: {uri: util.LspFileToUri(@%)},
	  position: GetLspPosition(find_ident)}
enddef

# Get a list of completion items.
# Request: "textDocument/completion"
# Param: CompletionParams
def GetCompletion(lspserver: dict<any>, triggerKind_arg: number, triggerChar: string): void
  # Check whether LSP server supports completion
  if !lspserver.isCompletionProvider
    util.ErrMsg('Error: LSP server does not support completion')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  # interface CompletionParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition(false)
  #   interface CompletionContext
  params.context = {triggerKind: triggerKind_arg, triggerCharacter: triggerChar}

  lspserver.rpc_a('textDocument/completion', params,
			completion.CompletionReply)
enddef

# Get lazy properties for a completion item.
# Request: "completionItem/resolve"
# Param: CompletionItem
def ResolveCompletion(lspserver: dict<any>, item: dict<any>): void
  # Check whether LSP server supports completion item resolve
  if !lspserver.isCompletionResolveProvider
    util.ErrMsg('Error: LSP server does not support completion item resolve')
    return
  endif

  # interface CompletionItem
  lspserver.rpc_a('completionItem/resolve', item,
			completion.CompletionResolveReply)
enddef

# Jump to or peek a symbol location.
#
# Send 'msg' to a LSP server and process the reply.  'msg' is one of the
# following:
#   textDocument/definition
#   textDocument/declaration
#   textDocument/typeDefinition
#   textDocument/implementation
#
# Process the LSP server reply and jump to the symbol location.  Before
# jumping to the symbol location, save the current cursor position in the tag
# stack.
#
# If 'peekSymbol' is true, then display the symbol location in the preview
# window but don't jump to the symbol location.
#
# Result: Location | Location[] | LocationLink[] | null
def GotoSymbolLoc(lspserver: dict<any>, msg: string, peekSymbol: bool,
		  cmdmods: string)
  var reply = lspserver.rpc(msg, GetLspTextDocPosition(true), false)
  if reply->empty() || reply.result->empty()
    var emsg: string
    if msg ==# 'textDocument/declaration'
      emsg = 'Error: symbol declaration is not found'
    elseif msg ==# 'textDocument/typeDefinition'
      emsg = 'Error: symbol type definition is not found'
    elseif msg ==# 'textDocument/implementation'
      emsg = 'Error: symbol implementation is not found'
    else
      emsg = 'Error: symbol definition is not found'
    endif

    util.WarnMsg(emsg)
    return
  endif

  var location: dict<any>
  if reply.result->type() == v:t_list
    # When there are multiple symbol locations, display the locations in a
    # location list.
    if reply.result->len() > 1
      var title: string = ''
      if msg ==# 'textDocument/declaration'
	title = 'Declarations'
      elseif msg ==# 'textDocument/typeDefinition'
	title = 'Type Definitions'
      elseif msg ==# 'textDocument/implementation'
	title = 'Implementations'
      else
	title = 'Definitions'
      endif

      symbol.ShowLocations(lspserver, reply.result, peekSymbol, title)
      return
    endif

    # Only one location
    location = reply.result[0]
  else
    location = reply.result
  endif

  symbol.GotoSymbol(lspserver, location, peekSymbol, cmdmods)
enddef

# Request: "textDocument/definition"
# Param: DefinitionParams
def GotoDefinition(lspserver: dict<any>, peek: bool, cmdmods: string)
  # Check whether LSP server supports jumping to a definition
  if !lspserver.isDefinitionProvider
    util.ErrMsg('Error: Jumping to a symbol definition is not supported')
    return
  endif

  # interface DefinitionParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/definition', peek, cmdmods)
enddef

# Request: "textDocument/declaration"
# Param: DeclarationParams
def GotoDeclaration(lspserver: dict<any>, peek: bool, cmdmods: string)
  # Check whether LSP server supports jumping to a declaration
  if !lspserver.isDeclarationProvider
    util.ErrMsg('Error: Jumping to a symbol declaration is not supported')
    return
  endif

  # interface DeclarationParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/declaration', peek, cmdmods)
enddef

# Request: "textDocument/typeDefinition"
# Param: TypeDefinitionParams
def GotoTypeDef(lspserver: dict<any>, peek: bool, cmdmods: string)
  # Check whether LSP server supports jumping to a type definition
  if !lspserver.isTypeDefinitionProvider
    util.ErrMsg('Error: Jumping to a symbol type definition is not supported')
    return
  endif

  # interface TypeDefinitionParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/typeDefinition', peek, cmdmods)
enddef

# Request: "textDocument/implementation"
# Param: ImplementationParams
def GotoImplementation(lspserver: dict<any>, peek: bool, cmdmods: string)
  # Check whether LSP server supports jumping to a implementation
  if !lspserver.isImplementationProvider
    util.ErrMsg('Error: Jumping to a symbol implementation is not supported')
    return
  endif

  # interface ImplementationParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/implementation', peek, cmdmods)
enddef

# Request: "textDocument/switchSourceHeader"
# Param: TextDocumentIdentifier
# Clangd specific extension
def SwitchSourceHeader(lspserver: dict<any>)
  var param = {}
  param.uri = util.LspFileToUri(@%)
  var reply = lspserver.rpc('textDocument/switchSourceHeader', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg('Error: No alternate file found')
    return
  endif

  # process the 'textDocument/switchSourceHeader' reply from the LSP server
  # Result: URI | null
  var fname = util.LspUriToFile(reply.result)
  if (&modified && !&hidden) || &buftype != ''
    # if the current buffer has unsaved changes and 'hidden' is not set,
    # or if the current buffer is a special buffer, then ask to save changes
    exe $'confirm edit {fname}'
  else
    exe $'edit {fname}'
  endif
enddef

# get symbol signature help.
# Request: "textDocument/signatureHelp"
# Param: SignatureHelpParams
def ShowSignature(lspserver: dict<any>): void
  # Check whether LSP server supports signature help
  if !lspserver.isSignatureHelpProvider
    util.ErrMsg('Error: LSP server does not support signature help')
    return
  endif

  # interface SignatureHelpParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition(false)
  lspserver.rpc_a('textDocument/signatureHelp', params,
			signature.SignatureHelp)
enddef

# Send a file/document saved notification to the language server
def DidSaveFile(lspserver: dict<any>, bnr: number): void
  # Check whether the LSP server supports the didSave notification
  if !lspserver.supportsDidSave
    # LSP server doesn't support text document synchronization
    return
  endif

  # Notification: 'textDocument/didSave'
  # Params: DidSaveTextDocumentParams
  var params = {textDocument: {uri: util.LspBufnrToUri(bnr)}}
  # FIXME: Need to set "params.text" when
  # 'lspserver.caps.textDocumentSync.save.includeText' is set to true.
  lspserver.sendNotification('textDocument/didSave', params)
enddef

# get the hover information
# Request: "textDocument/hover"
# Param: HoverParams
def ShowHoverInfo(lspserver: dict<any>): void
  # Check whether LSP server supports getting hover information.
  # caps->hoverProvider can be a "boolean" or "HoverOptions"
  if !lspserver.isHoverProvider
    return
  endif

  # interface HoverParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition(false)
  lspserver.rpc_a('textDocument/hover', params, hover.HoverReply)
enddef

# Request: "textDocument/references"
# Param: ReferenceParams
def ShowReferences(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports getting reference information
  if !lspserver.isReferencesProvider
    util.ErrMsg('Error: LSP server does not support showing references')
    return
  endif

  # interface ReferenceParams
  #   interface TextDocumentPositionParams
  var param: dict<any>
  param = GetLspTextDocPosition(true)
  param.context = {includeDeclaration: true}
  var reply = lspserver.rpc('textDocument/references', param)

  # Result: Location[] | null
  if reply->empty() || reply.result->empty()
    util.WarnMsg('Error: No references found')
    return
  endif

  symbol.ShowLocations(lspserver, reply.result, peek, 'Symbol References')
enddef

# process the 'textDocument/documentHighlight' reply from the LSP server
# Result: DocumentHighlight[] | null
def DocHighlightReply(bnr: number, lspserver: dict<any>, docHighlightReply: any): void
  if docHighlightReply->empty()
    return
  endif

  for docHL in docHighlightReply
    var kind: number = docHL->get('kind', 1)
    var propName: string
    if kind == 2
      # Read-access
      propName = 'LspReadRef'
    elseif kind == 3
      # Write-access
      propName = 'LspWriteRef'
    else
      # textual reference
      propName = 'LspTextRef'
    endif
    prop_add(docHL.range.start.line + 1,
		util.GetLineByteFromPos(bnr, docHL.range.start) + 1,
		{end_lnum: docHL.range.end.line + 1,
		  end_col: util.GetLineByteFromPos(bnr, docHL.range.end) + 1,
		  bufnr: bnr,
		  type: propName})
  endfor
enddef

# Request: "textDocument/documentHighlight"
# Param: DocumentHighlightParams
def DocHighlight(lspserver: dict<any>): void
  # Check whether LSP server supports getting highlight information
  if !lspserver.isDocumentHighlightProvider
    util.ErrMsg('Error: LSP server does not support document highlight')
    return
  endif

  # interface DocumentHighlightParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition(false)
  lspserver.rpc_a('textDocument/documentHighlight', params,
			function('DocHighlightReply', [bufnr()]))
enddef

# Request: "textDocument/documentSymbol"
# Param: DocumentSymbolParams
def GetDocSymbols(lspserver: dict<any>, fname: string): void
  # Check whether LSP server supports getting document symbol information
  if !lspserver.isDocumentSymbolProvider
    util.ErrMsg('Error: LSP server does not support getting list of symbols')
    return
  endif

  # interface DocumentSymbolParams
  # interface TextDocumentIdentifier
  var params = {textDocument: {uri: util.LspFileToUri(fname)}}
  lspserver.rpc_a('textDocument/documentSymbol', params,
			function(symbol.DocSymbolReply, [fname]))
enddef

# Request: "textDocument/formatting"
# Param: DocumentFormattingParams
# or
# Request: "textDocument/rangeFormatting"
# Param: DocumentRangeFormattingParams
def TextDocFormat(lspserver: dict<any>, fname: string, rangeFormat: bool,
				start_lnum: number, end_lnum: number)
  # Check whether LSP server supports formatting documents
  if !lspserver.isDocumentFormattingProvider
    util.ErrMsg('Error: LSP server does not support formatting documents')
    return
  endif

  var cmd: string
  if rangeFormat
    cmd = 'textDocument/rangeFormatting'
  else
    cmd = 'textDocument/formatting'
  endif

  # interface DocumentFormattingParams
  #   interface TextDocumentIdentifier
  #   interface FormattingOptions
  var param = {}
  param.textDocument = {uri: util.LspFileToUri(fname)}
  var fmtopts: dict<any> = {
    tabSize: shiftwidth(),
    insertSpaces: &expandtab ? true : false,
  }
  param.options = fmtopts

  if rangeFormat
    var r: dict<dict<number>> = {
	start: {line: start_lnum - 1, character: 0},
	end: {line: end_lnum - 1, character: charcol([end_lnum, '$']) - 1}}
    param.range = r
  endif

  var reply = lspserver.rpc(cmd, param)

  # result: TextEdit[] | null

  if reply->empty() || reply.result->empty()
    # nothing to format
    return
  endif

  var bnr: number = fname->bufnr()
  if bnr == -1
    # file is already removed
    return
  endif

  # interface TextEdit
  # Apply each of the text edit operations
  var save_cursor: list<number> = getcurpos()
  textedit.ApplyTextEdits(bnr, reply.result)
  save_cursor->setpos('.')
enddef

# Request: "textDocument/prepareCallHierarchy"
def PrepareCallHierarchy(lspserver: dict<any>): dict<any>
  # interface CallHierarchyPrepareParams
  #   interface TextDocumentPositionParams
  var param: dict<any>
  param = GetLspTextDocPosition(false)
  var reply = lspserver.rpc('textDocument/prepareCallHierarchy', param)
  if reply->empty() || reply.result->empty()
    return {}
  endif

  # Result: CallHierarchyItem[] | null
  var choice: number = 1
  if reply.result->len() > 1
    var items: list<string> = ['Select a Call Hierarchy Item:']
    for i in reply.result->len()->range()
      items->add(printf("%d. %s", i + 1, reply.result[i].name))
    endfor
    choice = items->inputlist()
    if choice < 1 || choice > items->len()
      return {}
    endif
  endif

  return reply.result[choice - 1]
enddef

# Request: "callHierarchy/incomingCalls"
def IncomingCalls(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports call hierarchy
  if !lspserver.isCallHierarchyProvider
    util.ErrMsg('Error: LSP server does not support call hierarchy')
    return
  endif

  callhier.IncomingCalls(lspserver)
enddef

def GetIncomingCalls(lspserver: dict<any>, item: dict<any>): any
  # Request: "callHierarchy/incomingCalls"
  # Param: CallHierarchyIncomingCallsParams
  var param = {}
  param.item = item
  var reply = lspserver.rpc('callHierarchy/incomingCalls', param)
  if reply->empty()
    return null
  endif
  return reply.result
enddef

# Request: "callHierarchy/outgoingCalls"
def OutgoingCalls(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports call hierarchy
  if !lspserver.isCallHierarchyProvider
    util.ErrMsg('Error: LSP server does not support call hierarchy')
    return
  endif

  callhier.OutgoingCalls(lspserver)
enddef

def GetOutgoingCalls(lspserver: dict<any>, item: dict<any>): any
  # Request: "callHierarchy/outgoingCalls"
  # Param: CallHierarchyOutgoingCallsParams
  var param = {}
  param.item = item
  var reply = lspserver.rpc('callHierarchy/outgoingCalls', param)
  if reply->empty()
    return null
  endif
  return reply.result
enddef

# Request: "textDocument/inlayHint"
# Inlay hints.
def InlayHintsShow(lspserver: dict<any>)
  # Check whether LSP server supports type hierarchy
  if !lspserver.isInlayHintProvider && !lspserver.isClangdInlayHintsProvider
    util.ErrMsg('Error: LSP server does not support inlay hint')
    return
  endif

  var lastlnum = line('$')
  var param = {
      textDocument: {uri: util.LspFileToUri(@%)},
      range:
      {
	start: {line: 0, character: 0},
	end: {line: lastlnum - 1, character: charcol([lastlnum, '$']) - 1}
      }
  }

  var msg: string
  if lspserver.isClangdInlayHintsProvider
    # clangd-style inlay hints
    msg = 'clangd/inlayHints'
  else
    msg = 'textDocument/inlayHint'
  endif
  var reply = lspserver.rpc_a(msg, param, inlayhints.InlayHintsReply)
enddef

# Request: "textDocument/typehierarchy"
# Support the clangd version of type hierarchy retrieval method.
# The method described in the LSP 3.17.0 standard is not supported as clangd
# doesn't support that method.
def TypeHiearchy(lspserver: dict<any>, direction: number)
  # Check whether LSP server supports type hierarchy
  if !lspserver.isTypeHierarchyProvider
    util.ErrMsg('Error: LSP server does not support type hierarchy')
    return
  endif

  # interface TypeHierarchy
  #   interface TextDocumentPositionParams
  var param: dict<any>
  param = GetLspTextDocPosition(false)
  # 0: children, 1: parent, 2: both
  param.direction = direction
  param.resolve = 5
  var reply = lspserver.rpc('textDocument/typeHierarchy', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg('No type hierarchy available')
    return
  endif

  typehier.ShowTypeHierarchy(lspserver, direction == 1, reply.result)
enddef

# Request: "textDocument/rename"
# Param: RenameParams
def RenameSymbol(lspserver: dict<any>, newName: string)
  # Check whether LSP server supports rename operation
  if !lspserver.isRenameProvider
    util.ErrMsg('Error: LSP server does not support rename operation')
    return
  endif

  # interface RenameParams
  #   interface TextDocumentPositionParams
  var param: dict<any> = {}
  param = GetLspTextDocPosition(true)
  param.newName = newName

  var reply = lspserver.rpc('textDocument/rename', param)

  # Result: WorkspaceEdit | null
  if reply->empty() || reply.result->empty()
    # nothing to rename
    return
  endif

  # result: WorkspaceEdit
  textedit.ApplyWorkspaceEdit(reply.result)
enddef

# Request: "textDocument/codeAction"
# Param: CodeActionParams
def CodeAction(lspserver: dict<any>, fname_arg: string, line1: number,
		line2: number, query: string)
  # Check whether LSP server supports code action operation
  if !lspserver.isCodeActionProvider
    util.ErrMsg('Error: LSP server does not support code action operation')
    return
  endif

  # interface CodeActionParams
  var params: dict<any> = {}
  var fname: string = fname_arg->fnamemodify(':p')
  var bnr: number = fname_arg->bufnr()
  var r: dict<dict<number>> = {
    start: {
      line: line1 - 1,
      character: line1 == line2 ? charcol('.') - 1 : 0
    },
    end: {
      line: line2 - 1,
      character: charcol([line2, '$']) - 1
    }
  }
  params->extend({textDocument: {uri: util.LspFileToUri(fname)}, range: r})
  var d: list<dict<any>> = []
  for lnum in range(line1, line2)
    var diagsInfo: list<dict<any>> = diag.GetDiagsByLine(lspserver, bnr, lnum)
    d->extend(diagsInfo)
  endfor
  params->extend({context: {diagnostics: d, triggerKind: 1}})

  var reply = lspserver.rpc('textDocument/codeAction', params)

  # Result: (Command | CodeAction)[] | null
  if reply->empty() || reply.result->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  codeaction.ApplyCodeAction(lspserver, reply.result, query)
enddef

# Request: "textDocument/codeLens"
# Param: CodeLensParams
def CodeLens(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports code lens operation
  if !lspserver.isCodeLensProvider
    util.ErrMsg('Error: LSP server does not support code lens operation')
    return
  endif

  var params = {textDocument: {uri: util.LspFileToUri(fname)}}
  var reply = lspserver.rpc('textDocument/codeLens', params)
  if reply->empty() || reply.result->empty()
    util.WarnMsg($'Error: No code lens actions found for the current file')
    return
  endif

  codelens.ProcessCodeLens(lspserver, reply.result)
enddef

# Request: "codeLens/resolve"
# Param: CodeLens
def ResolveCodeLens(lspserver: dict<any>, codeLens: dict<any>): dict<any>
  if !lspserver.isCodeLensResolveProvider
    return {}
  endif
  var reply = lspserver.rpc('codeLens/resolve', codeLens)
  if reply->empty()
    return {}
  endif
  return reply.result
enddef

# List project-wide symbols matching query string
# Request: "workspace/symbol"
# Param: WorkspaceSymbolParams
def WorkspaceQuerySymbols(lspserver: dict<any>, query: string)
  # Check whether the LSP server supports listing workspace symbols
  if !lspserver.isWorkspaceSymbolProvider
    util.ErrMsg('Error: LSP server does not support listing workspace symbols')
    return
  endif

  # Param: WorkspaceSymbolParams
  var param = {}
  param.query = query
  var reply = lspserver.rpc('workspace/symbol', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg($'Error: Symbol "{query}" is not found')
    return
  endif

  symbol.WorkspaceSymbolPopup(lspserver, query, reply.result)
enddef

# Add a workspace folder to the language server.
def AddWorkspaceFolder(lspserver: dict<any>, dirName: string): void
  if !lspserver.caps->has_key('workspace')
	  || !lspserver.caps.workspace->has_key('workspaceFolders')
	  || !lspserver.caps.workspace.workspaceFolders->has_key('supported')
	  || !lspserver.caps.workspace.workspaceFolders.supported
      util.ErrMsg('Error: LSP server does not support workspace folders')
    return
  endif

  if lspserver.workspaceFolders->index(dirName) != -1
    util.ErrMsg($'Error: {dirName} is already part of this workspace')
    return
  endif

  # Notification: 'workspace/didChangeWorkspaceFolders'
  # Params: DidChangeWorkspaceFoldersParams
  var params = {event: {added: [dirName], removed: []}}
  lspserver.sendNotification('workspace/didChangeWorkspaceFolders', params)

  lspserver.workspaceFolders->add(dirName)
enddef

# Remove a workspace folder from the language server.
def RemoveWorkspaceFolder(lspserver: dict<any>, dirName: string): void
  if !lspserver.caps->has_key('workspace')
	  || !lspserver.caps.workspace->has_key('workspaceFolders')
	  || !lspserver.caps.workspace.workspaceFolders->has_key('supported')
	  || !lspserver.caps.workspace.workspaceFolders.supported
      util.ErrMsg('Error: LSP server does not support workspace folders')
    return
  endif

  var idx: number = lspserver.workspaceFolders->index(dirName)
  if idx == -1
    util.ErrMsg($'Error: {dirName} is not currently part of this workspace')
    return
  endif

  # Notification: "workspace/didChangeWorkspaceFolders"
  # Param: DidChangeWorkspaceFoldersParams
  var params = {event: {added: [], removed: [dirName]}}
  lspserver.sendNotification('workspace/didChangeWorkspaceFolders', params)

  lspserver.workspaceFolders->remove(idx)
enddef

# select the text around the current cursor location
# Request: "textDocument/selectionRange"
# Param: SelectionRangeParams
def SelectionRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports selection ranges
  if !lspserver.isSelectionRangeProvider
    util.ErrMsg('Error: LSP server does not support selection ranges')
    return
  endif

  # clear the previous selection reply
  lspserver.selection = {}

  # interface SelectionRangeParams
  # interface TextDocumentIdentifier
  var param = {}
  param.textDocument = {}
  param.textDocument.uri = util.LspFileToUri(fname)
  param.positions = [GetLspPosition(false)]
  var reply = lspserver.rpc('textDocument/selectionRange', param)

  if reply->empty() || reply.result->empty()
    return
  endif

  selection.SelectionStart(lspserver, reply.result)
enddef

# Expand the previous selection or start a new one
def SelectionExpand(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.isSelectionRangeProvider
    util.ErrMsg('Error: LSP server does not support selection ranges')
    return
  endif

  selection.SelectionModify(lspserver, true)
enddef

# Shrink the previous selection or start a new one
def SelectionShrink(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.isSelectionRangeProvider
    util.ErrMsg('Error: LSP server does not support selection ranges')
    return
  endif

  selection.SelectionModify(lspserver, false)
enddef

# fold the entire document
# Request: "textDocument/foldingRange"
# Param: FoldingRangeParams
def FoldRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports fold ranges
  if !lspserver.isFoldingRangeProvider
    util.ErrMsg('Error: LSP server does not support folding')
    return
  endif

  # interface FoldingRangeParams
  # interface TextDocumentIdentifier
  var params = {textDocument: {uri: util.LspFileToUri(fname)}}
  var reply = lspserver.rpc('textDocument/foldingRange', params)
  if reply->empty() || reply.result->empty()
    return
  endif

  # result: FoldingRange[]
  var end_lnum: number
  var last_lnum: number = line('$')
  for foldRange in reply.result
    end_lnum = foldRange.endLine + 1
    if end_lnum < foldRange.startLine + 2
      end_lnum = foldRange.startLine + 2
    endif
    exe $':{foldRange.startLine + 2}, {end_lnum}fold'
    # Open all the folds, otherwise the subsequently created folds are not
    # correct.
    :silent! foldopen!
  endfor

  if &foldcolumn == 0
    :setlocal foldcolumn=2
  endif
enddef

# process the 'workspace/executeCommand' reply from the LSP server
# Result: any | null
def WorkspaceExecuteReply(lspserver: dict<any>, execReply: any)
  # Nothing to do for the reply
enddef

# Request the LSP server to execute a command
# Request: workspace/executeCommand
# Params: ExecuteCommandParams
def ExecuteCommand(lspserver: dict<any>, cmd: dict<any>)
  # Need to check for lspserver.caps.executeCommandProvider?
  var params = cmd
  lspserver.rpc_a('workspace/executeCommand', params, WorkspaceExecuteReply)
enddef

# Display the LSP server capabilities (received during the initialization
# stage).
def ShowCapabilities(lspserver: dict<any>)
  var wid = bufwinid('Language-Server-Capabilities')
  if wid != -1
    wid->win_gotoid()
    :setlocal modifiable
    :silent! :%d _
  else
    :new Language-Server-Capabilities
    :setlocal buftype=nofile
    :setlocal bufhidden=wipe
    :setlocal noswapfile
    :setlocal nonumber nornu
    :setlocal fdc=0 signcolumn=no
  endif
  var l = []
  var heading = $"'{lspserver.path}' Language Server Capabilities"
  var underlines = repeat('=', heading->len())
  l->extend([heading, underlines])
  for k in lspserver.caps->keys()->sort()
    l->add($'{k}: {lspserver.caps[k]->string()}')
  endfor
  setline(1, l)
  :setlocal nomodified
  :setlocal nomodifiable
enddef

# Send a 'textDocument/definition' request to the LSP server to get the
# location where the symbol under the cursor is defined and return a list of
# Dicts in a format accepted by the 'tagfunc' option.
# Returns null if the LSP server doesn't support getting the location of a
# symbol definition or the symbol is not defined.
def TagFunc(lspserver: dict<any>, pat: string, flags: string, info: dict<any>): any
  # Check whether LSP server supports getting the location of a definition
  if !lspserver.isDefinitionProvider
    return null
  endif

  # interface DefinitionParams
  #   interface TextDocumentPositionParams
  var reply = lspserver.rpc('textDocument/definition', GetLspTextDocPosition(false))
  if reply->empty() || reply.result->empty()
    return null
  endif

  var taglocations: list<dict<any>>
  if reply.result->type() == v:t_list
    taglocations = reply.result
  else
    taglocations = [reply.result]
  endif

  return symbol.TagFunc(lspserver, taglocations, pat)
enddef

export def NewLspServer(name_arg: string, path_arg: string, args: list<string>,
			isSync: bool, initializationOptions: any,
			workspaceConfig: dict<any>,
			rootSearchFiles: list<any>,
			customNotificationHandlers: dict<func>,
			debug_arg: bool): dict<any>
  var lspserver: dict<any> = {
    name: name_arg,
    path: path_arg,
    args: args,
    syncInit: isSync,
    initializationOptions: initializationOptions,
    customNotificationHandlers: customNotificationHandlers,
    running: false,
    ready: false,
    job: v:none,
    data: '',
    nextID: 1,
    caps: {},
    requests: {},
    rootSearchFiles: rootSearchFiles,
    omniCompletePending: false,
    completionTriggerChars: [],
    signaturePopup: -1,
    typeHierPopup: -1,
    typeHierFilePopup: -1,
    diagsMap: {},
    workspaceSymbolPopup: -1,
    workspaceSymbolQuery: '',
    peekSymbolPopup: -1,
    peekSymbolFilePopup: -1,
    callHierarchyType: '',
    selection: {},
    workspaceConfig: workspaceConfig,
    debug: debug_arg
  }
  lspserver.logfile = $'lsp-{lspserver.name}.log'
  lspserver.errfile = $'lsp-{lspserver.name}.err'

  # Add the LSP server functions
  lspserver->extend({
    startServer: function(StartServer, [lspserver]),
    initServer: function(InitServer, [lspserver]),
    stopServer: function(StopServer, [lspserver]),
    shutdownServer: function(ShutdownServer, [lspserver]),
    exitServer: function(ExitServer, [lspserver]),
    setTrace: function(SetTrace, [lspserver]),
    traceLog: function(TraceLog, [lspserver]),
    errorLog: function(ErrorLog, [lspserver]),
    nextReqID: function(NextReqID, [lspserver]),
    createRequest: function(CreateRequest, [lspserver]),
    createResponse: function(CreateResponse, [lspserver]),
    sendResponse: function(SendResponse, [lspserver]),
    sendMessage: function(SendMessage, [lspserver]),
    sendNotification: function(SendNotification, [lspserver]),
    rpc: function(Rpc, [lspserver]),
    rpc_a: function(AsyncRpc, [lspserver]),
    waitForResponse: function(WaitForResponse, [lspserver]),
    processReply: function(handlers.ProcessReply, [lspserver]),
    processNotif: function(handlers.ProcessNotif, [lspserver]),
    processRequest: function(handlers.ProcessRequest, [lspserver]),
    processMessages: function(handlers.ProcessMessages, [lspserver]),
    getDiagByPos: function(diag.GetDiagByPos, [lspserver]),
    getDiagsByLine: function(diag.GetDiagsByLine, [lspserver]),
    textdocDidOpen: function(TextdocDidOpen, [lspserver]),
    textdocDidClose: function(TextdocDidClose, [lspserver]),
    textdocDidChange: function(TextdocDidChange, [lspserver]),
    sendInitializedNotif: function(SendInitializedNotif, [lspserver]),
    sendWorkspaceConfig: function(SendWorkspaceConfig, [lspserver]),
    getCompletion: function(GetCompletion, [lspserver]),
    resolveCompletion: function(ResolveCompletion, [lspserver]),
    gotoDefinition: function(GotoDefinition, [lspserver]),
    gotoDeclaration: function(GotoDeclaration, [lspserver]),
    gotoTypeDef: function(GotoTypeDef, [lspserver]),
    gotoImplementation: function(GotoImplementation, [lspserver]),
    tagFunc: function(TagFunc, [lspserver]),
    switchSourceHeader: function(SwitchSourceHeader, [lspserver]),
    showSignature: function(ShowSignature, [lspserver]),
    didSaveFile: function(DidSaveFile, [lspserver]),
    hover: function(ShowHoverInfo, [lspserver]),
    showReferences: function(ShowReferences, [lspserver]),
    docHighlight: function(DocHighlight, [lspserver]),
    getDocSymbols: function(GetDocSymbols, [lspserver]),
    textDocFormat: function(TextDocFormat, [lspserver]),
    prepareCallHierarchy: function(PrepareCallHierarchy, [lspserver]),
    incomingCalls: function(IncomingCalls, [lspserver]),
    getIncomingCalls: function(GetIncomingCalls, [lspserver]),
    outgoingCalls: function(OutgoingCalls, [lspserver]),
    getOutgoingCalls: function(GetOutgoingCalls, [lspserver]),
    inlayHintsShow: function(InlayHintsShow, [lspserver]),
    typeHierarchy: function(TypeHiearchy, [lspserver]),
    renameSymbol: function(RenameSymbol, [lspserver]),
    codeAction: function(CodeAction, [lspserver]),
    codeLens: function(CodeLens, [lspserver]),
    resolveCodeLens: function(ResolveCodeLens, [lspserver]),
    workspaceQuery: function(WorkspaceQuerySymbols, [lspserver]),
    addWorkspaceFolder: function(AddWorkspaceFolder, [lspserver]),
    removeWorkspaceFolder: function(RemoveWorkspaceFolder, [lspserver]),
    selectionRange: function(SelectionRange, [lspserver]),
    selectionExpand: function(SelectionExpand, [lspserver]),
    selectionShrink: function(SelectionShrink, [lspserver]),
    foldRange: function(FoldRange, [lspserver]),
    executeCommand: function(ExecuteCommand, [lspserver]),
    workspaceConfigGet: function(WorkspaceConfigGet, [lspserver]),
    showCapabilities: function(ShowCapabilities, [lspserver])
  })

  return lspserver
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
