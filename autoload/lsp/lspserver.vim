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
import './offset.vim'
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
import './semantichighlight.vim'

# LSP server standard output handler
def Output_cb(lspserver: dict<any>, chan: channel, msg: any): void
  if lspserver.debug
    lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Received {msg->string()}')
  endif
  lspserver.data = msg
  lspserver.processMessages()
enddef

# LSP server error output handler
def Error_cb(lspserver: dict<any>, chan: channel, emsg: string): void
  lspserver.errorLog(emsg)
enddef

# LSP server exit callback
def Exit_cb(lspserver: dict<any>, job: job, status: number): void
  util.WarnMsg($'{strftime("%m/%d/%y %T")}: LSP server ({lspserver.name}) exited with status {status}')
  lspserver.running = false
  lspserver.ready = false
  lspserver.requests = {}
enddef

# Start a LSP server
#
def StartServer(lspserver: dict<any>, bnr: number): number
  if lspserver.running
    util.WarnMsg($'LSP server "{lspserver.name}" is already running')
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

  var job = cmd->job_start(opts)
  if job->job_status() == 'fail'
    util.ErrMsg($'Failed to start LSP server {lspserver.path}')
    return 1
  endif

  # wait a little for the LSP server to start
  sleep 10m

  lspserver.job = job
  lspserver.running = true

  lspserver.initServer(bnr)

  return 0
enddef

# process the "initialize" method reply from the LSP server
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

  if caps->has_key('completionProvider')
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
  # Used internally, and shouldn't be used by users
  if exists($'#User#LspServerReady_{lspserver.id}')
    exe $'doautocmd <nomodeline> User LspServerReady_{lspserver.id}'
  endif

  # set the server debug trace level
  if lspserver.traceLevel != 'off'
    lspserver.setTrace(lspserver.traceLevel)
  endif

  # if the outline window is opened, then request the symbols for the current
  # buffer
  if bufwinid('LSP-Outline') != -1
    lspserver.getDocSymbols(@%, true)
  endif

  # Update the inlay hints (if enabled)
  if opt.lspOptions.showInlayHints && (lspserver.isInlayHintProvider
				    || lspserver.isClangdInlayHintsProvider)
    inlayhints.LspInlayHintsUpdateNow(bufnr())
  endif
enddef

# Request: "initialize"
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
  var rootPath = ''
  var rootSearchFiles = lspserver.rootSearchFiles
  var bufDir = bnr->bufname()->fnamemodify(':p:h')
  if !rootSearchFiles->empty()
    rootPath = util.FindNearestRootDir(bufDir, rootSearchFiles)
  endif
  if rootPath->empty()
    var cwd = getcwd()

    # bufDir is within cwd
    var bufDirPrefix = bufDir[0 : cwd->strcharlen() - 1]
    if &fileignorecase
        ? bufDirPrefix ==? cwd
        : bufDirPrefix == cwd
      rootPath = cwd
    else
      rootPath = bufDir
    endif
  endif

  lspserver.workspaceFolders = [rootPath]

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
  else
    initparams.initializationOptions = {}
  endif

  lspserver.rpcInitializeRequest = initparams

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
    util.WarnMsg($'LSP server {lspserver.name} is not running')
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
  var req = {
    jsonrpc: '2.0',
    id: lspserver.nextReqID(),
    method: method,
    params: {}
  }

  # Save the request, so that the corresponding response can be processed
  lspserver.requests->extend({[req.id->string()]: req})

  return req
enddef

# create a LSP server response message
def CreateResponse(lspserver: dict<any>, req_id: number): dict<any>
  var resp = {
    jsonrpc: '2.0',
    id: req_id
  }
  return resp
enddef

# create a LSP server notification message
def CreateNotification(lspserver: dict<any>, notif: string): dict<any>
  var req = {
    jsonrpc: '2.0',
    method: notif,
    params: {}
  }

  return req
enddef

# send a response message to the server
def SendResponse(lspserver: dict<any>, request: dict<any>, result: any, error: dict<any>)
  if (request.id->type() == v:t_string
	&& (request.id->trim() =~ '[^[:digit:]]\+'
	    || request.id->trim()->empty()))
    || (request.id->type() != v:t_string && request.id->type() != v:t_number)
    util.ErrMsg('request.id of response to LSP server is not a correct number')
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
    if lspserver.debug
      lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Sent {content->string()}')
    endif
  endif
enddef

# Send a notification message to the language server
def SendNotification(lspserver: dict<any>, method: string, params: any = {})
  var notif: dict<any> = CreateNotification(lspserver, method)
  notif.params->extend(params)
  lspserver.sendMessage(notif)
enddef

# Translate an LSP error code into a readable string
def LspGetErrorMessage(errcode: number): string
  var errmap = {
    -32001: 'UnknownErrorCode',
    -32002: 'ServerNotInitialized',
    -32600: 'InvalidRequest',
    -32601: 'MethodNotFound',
    -32602: 'InvalidParams',
    -32603: 'InternalError',
    -32700: 'ParseError',
    -32800: 'RequestCancelled',
    -32801: 'ContentModified',
    -32802: 'ServerCancelled',
    -32803: 'RequestFailed'
  }

  return errmap->get(errcode, errcode->string())
enddef

# Process a LSP server response error and display an error message.
def ProcessLspServerError(method: string, responseError: dict<any>)
  # request failed
  var emsg: string = responseError.message
  emsg ..= $', error = {LspGetErrorMessage(responseError.code)}'
  if responseError->has_key('data')
    emsg ..= $', data = {responseError.data->string()}'
  endif
  util.ErrMsg($'request {method} failed ({emsg})')
enddef

# Send a sync RPC request message to the LSP server and return the received
# reply.  In case of an error, an empty Dict is returned.
def Rpc(lspserver: dict<any>, method: string, params: any, handleError: bool = true): dict<any>
  var req = {
    method: method,
    params: params
  }

  var job = lspserver.job
  if job->job_status() != 'run'
    # LSP server has exited
    return {}
  endif

  if lspserver.debug
    lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Sent {req->string()}')
  endif

  # Do the synchronous RPC call
  var reply = job->ch_evalexpr(req)

  if lspserver.debug
    lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Received {reply->string()}')
  endif

  if reply->has_key('result')
    # successful reply
    return reply
  endif

  if reply->has_key('error') && handleError
    # request failed
    ProcessLspServerError(method, reply.error)
  endif

  return {}
enddef

# LSP server asynchronous RPC callback
def AsyncRpcCb(lspserver: dict<any>, method: string, RpcCb: func, chan: channel, reply: dict<any>)
  if lspserver.debug
    lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Received {reply->string()}')
  endif

  if reply->empty()
    return
  endif

  if reply->has_key('error')
    # request failed
    ProcessLspServerError(method, reply.error)
    return
  endif

  if !reply->has_key('result')
    util.ErrMsg($'request {method} failed (no result)')
    return
  endif

  RpcCb(lspserver, reply.result)
enddef

# Send a async RPC request message to the LSP server with a callback function.
# Returns the LSP message id.  This id can be used to cancel the RPC request
# (if needed).  Returns -1 on error.
def AsyncRpc(lspserver: dict<any>, method: string, params: any, Cbfunc: func): number
  var req = {
    method: method,
    params: params
  }

  var job = lspserver.job
  if job->job_status() != 'run'
    # LSP server has exited
    return -1
  endif

  if lspserver.debug
    lspserver.traceLog($'{strftime("%m/%d/%y %T")}: Sent {req->string()}')
  endif

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

# Returns true when the "lspserver" has "feature" enabled.
# By default, all the features of a lsp server are enabled.
def FeatureEnabled(lspserver: dict<any>, feature: string): bool
  return lspserver.features->get(feature, true)
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

# Update semantic highlighting for buffer "bnr"
# Request: textDocument/semanticTokens/full or
#	   textDocument/semanticTokens/full/delta
def SemanticHighlightUpdate(lspserver: dict<any>, bnr: number)
  if !lspserver.isSemanticTokensProvider
    return
  endif

  # Send the pending buffer changes to the language server
  bnr->listener_flush()

  var method = 'textDocument/semanticTokens/full'
  var params: dict<any> = {
    textDocument: {
      uri: util.LspBufnrToUri(bnr)
    }
  }

  # Should we send a semantic tokens delta request instead of a full request?
  if lspserver.semanticTokensDelta
    var prevResultId: string = ''
    prevResultId = bnr->getbufvar('LspSemanticResultId', '')
    if prevResultId != ''
      # semantic tokens delta request
      params.previousResultId = prevResultId
      method ..= '/delta'
    endif
  endif

  var reply = lspserver.rpc(method, params)

  if reply->empty() || reply.result->empty()
    return
  endif

  semantichighlight.UpdateTokens(lspserver, bnr, reply.result)
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
  var params = {
    textDocument: {
      uri: util.LspBufnrToUri(bnr),
      languageId: ftype,
      # Use Vim 'changedtick' as the LSP document version number
      version: bnr->getbufvar('changedtick'),
      text: bnr->getbufline(1, '$')->join("\n") .. "\n"
    }
  }
  lspserver.sendNotification('textDocument/didOpen', params)
enddef

# Send a file/document closed notification to the language server.
def TextdocDidClose(lspserver: dict<any>, bnr: number): void
  # Notification: 'textDocument/didClose'
  # Params: DidCloseTextDocumentParams
  var params = {
    textDocument: {
      uri: util.LspBufnrToUri(bnr)
    }
  }
  lspserver.sendNotification('textDocument/didClose', params)
enddef

# Send a file/document change notification to the language server.
# Params: DidChangeTextDocumentParams
def TextdocDidChange(lspserver: dict<any>, bnr: number, start: number,
			end: number, added: number,
			changes: list<dict<number>>): void
  # Notification: 'textDocument/didChange'
  # Params: DidChangeTextDocumentParams

  # var changeset: list<dict<any>>

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

  var params = {
    textDocument: {
      uri: util.LspBufnrToUri(bnr),
      # Use Vim 'changedtick' as the LSP document version number
      version: bnr->getbufvar('changedtick')
    },
    contentChanges: [
      {text: bnr->getbufline(1, '$')->join("\n") .. "\n"}
    ]
  }
  lspserver.sendNotification('textDocument/didChange', params)
enddef

# Return the current cursor position as a LSP position.
# find_ident will search for a identifier in front of the cursor, just like
# CTRL-] and c_CTRL-R_CTRL-W does.
#
# LSP line and column numbers start from zero, whereas Vim line and column
# numbers start from one. The LSP column number is the character index in the
# line and not the byte index in the line.
def GetPosition(lspserver: dict<any>, find_ident: bool): dict<number>
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

  # Compute character index counting composing characters as separate
  # characters
  var pos = {line: lnum, character: util.GetCharIdxWithCompChar(line, col)}
  lspserver.encodePosition(bufnr(), pos)

  return pos
enddef

# Return the current file name and current cursor position as a LSP
# TextDocumentPositionParams structure
def GetTextDocPosition(lspserver: dict<any>, find_ident: bool): dict<dict<any>>
  # interface TextDocumentIdentifier
  # interface Position
  return {textDocument: {uri: util.LspFileToUri(@%)},
	  position: lspserver.getPosition(find_ident)}
enddef

# Get a list of completion items.
# Request: "textDocument/completion"
# Param: CompletionParams
def GetCompletion(lspserver: dict<any>, triggerKind_arg: number, triggerChar: string): void
  # Check whether LSP server supports completion
  if !lspserver.isCompletionProvider
    util.ErrMsg('LSP server does not support completion')
    return
  endif

  var fname = @%
  if fname->empty()
    return
  endif

  # interface CompletionParams
  #   interface TextDocumentPositionParams
  var params = lspserver.getTextDocPosition(false)
  #   interface CompletionContext
  params.context = {triggerKind: triggerKind_arg, triggerCharacter: triggerChar}

  lspserver.rpc_a('textDocument/completion', params,
			completion.CompletionReply)
enddef

# Get lazy properties for a completion item.
# Request: "completionItem/resolve"
# Param: CompletionItem
def ResolveCompletion(lspserver: dict<any>, item: dict<any>, sync: bool = false): dict<any>
  # Check whether LSP server supports completion item resolve
  if !lspserver.isCompletionResolveProvider
    return {}
  endif

  # interface CompletionItem
  if sync
    var reply = lspserver.rpc('completionItem/resolve', item)
    if !reply->empty() && !reply.result->empty()
      return reply.result
    endif
  else
    lspserver.rpc_a('completionItem/resolve', item,
			  completion.CompletionResolveReply)
  endif
  return {}
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
		  cmdmods: string, count: number)
  var reply = lspserver.rpc(msg, lspserver.getTextDocPosition(true), false)
  if reply->empty() || reply.result->empty()
    var emsg: string
    if msg == 'textDocument/declaration'
      emsg = 'symbol declaration is not found'
    elseif msg == 'textDocument/typeDefinition'
      emsg = 'symbol type definition is not found'
    elseif msg == 'textDocument/implementation'
      emsg = 'symbol implementation is not found'
    else
      emsg = 'symbol definition is not found'
    endif

    util.WarnMsg(emsg)
    return
  endif

  var result = reply.result
  var location: dict<any>
  if result->type() == v:t_list
    if count == 0
      # When there are multiple symbol locations, and a specific one isn't
      # requested with 'count', display the locations in a location list.
      if result->len() > 1
        var title: string = ''
        if msg == 'textDocument/declaration'
          title = 'Declarations'
        elseif msg == 'textDocument/typeDefinition'
          title = 'Type Definitions'
        elseif msg == 'textDocument/implementation'
          title = 'Implementations'
        else
          title = 'Definitions'
        endif

	if lspserver.needOffsetEncoding
	  # Decode the position encoding in all the symbol locations
	  result->map((_, loc) => {
	      lspserver.decodeLocation(loc)
	      return loc
	    })
	endif

        symbol.ShowLocations(lspserver, result, peekSymbol, title)
        return
      endif
    endif

    # Select the location requested in 'count'
    var idx = count - 1
    if idx >= result->len()
      idx = result->len() - 1
    endif
    location = result[idx]
  else
    location = result
  endif
  lspserver.decodeLocation(location)

  symbol.GotoSymbol(lspserver, location, peekSymbol, cmdmods)
enddef

# Request: "textDocument/definition"
# Param: DefinitionParams
def GotoDefinition(lspserver: dict<any>, peek: bool, cmdmods: string, count: number)
  # Check whether LSP server supports jumping to a definition
  if !lspserver.isDefinitionProvider
    util.ErrMsg('Jumping to a symbol definition is not supported')
    return
  endif

  # interface DefinitionParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/definition', peek, cmdmods, count)
enddef

# Request: "textDocument/declaration"
# Param: DeclarationParams
def GotoDeclaration(lspserver: dict<any>, peek: bool, cmdmods: string, count: number)
  # Check whether LSP server supports jumping to a declaration
  if !lspserver.isDeclarationProvider
    util.ErrMsg('Jumping to a symbol declaration is not supported')
    return
  endif

  # interface DeclarationParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/declaration', peek, cmdmods, count)
enddef

# Request: "textDocument/typeDefinition"
# Param: TypeDefinitionParams
def GotoTypeDef(lspserver: dict<any>, peek: bool, cmdmods: string, count: number)
  # Check whether LSP server supports jumping to a type definition
  if !lspserver.isTypeDefinitionProvider
    util.ErrMsg('Jumping to a symbol type definition is not supported')
    return
  endif

  # interface TypeDefinitionParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/typeDefinition', peek, cmdmods, count)
enddef

# Request: "textDocument/implementation"
# Param: ImplementationParams
def GotoImplementation(lspserver: dict<any>, peek: bool, cmdmods: string, count: number)
  # Check whether LSP server supports jumping to a implementation
  if !lspserver.isImplementationProvider
    util.ErrMsg('Jumping to a symbol implementation is not supported')
    return
  endif

  # interface ImplementationParams
  #   interface TextDocumentPositionParams
  GotoSymbolLoc(lspserver, 'textDocument/implementation', peek, cmdmods, count)
enddef

# Request: "textDocument/switchSourceHeader"
# Param: TextDocumentIdentifier
# Clangd specific extension
def SwitchSourceHeader(lspserver: dict<any>)
  var param = {
    uri: util.LspFileToUri(@%)
  }
  var reply = lspserver.rpc('textDocument/switchSourceHeader', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg('Source/Header file is not found')
    return
  endif

  # process the 'textDocument/switchSourceHeader' reply from the LSP server
  # Result: URI | null
  var fname = util.LspUriToFile(reply.result)
  # TODO: Add support for cmd modifiers
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
    util.ErrMsg('LSP server does not support signature help')
    return
  endif

  # interface SignatureHelpParams
  #   interface TextDocumentPositionParams
  var params = lspserver.getTextDocPosition(false)
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
  var params: dict<any> = {textDocument: {uri: util.LspBufnrToUri(bnr)}}

  if lspserver.caps.textDocumentSync->type() == v:t_dict
      && lspserver.caps.textDocumentSync->has_key('save')
    if lspserver.caps.textDocumentSync.save->type() == v:t_dict
	&& lspserver.caps.textDocumentSync.save->has_key('includeText')
	&& lspserver.caps.textDocumentSync.save.includeText
      params.text = bnr->getbufline(1, '$')->join("\n") .. "\n"
    endif
  endif

  lspserver.sendNotification('textDocument/didSave', params)
enddef

# get the hover information
# Request: "textDocument/hover"
# Param: HoverParams
def ShowHoverInfo(lspserver: dict<any>, cmdmods: string): void
  # Check whether LSP server supports getting hover information.
  # caps->hoverProvider can be a "boolean" or "HoverOptions"
  if !lspserver.isHoverProvider
    return
  endif

  # interface HoverParams
  #   interface TextDocumentPositionParams
  var params = lspserver.getTextDocPosition(false)
  lspserver.rpc_a('textDocument/hover', params, (_, reply) => {
    hover.HoverReply(lspserver, reply, cmdmods)
  })
enddef

# Request: "textDocument/references"
# Param: ReferenceParams
def ShowReferences(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports getting reference information
  if !lspserver.isReferencesProvider
    util.ErrMsg('LSP server does not support showing references')
    return
  endif

  # interface ReferenceParams
  #   interface TextDocumentPositionParams
  var param: dict<any>
  param = lspserver.getTextDocPosition(true)
  param.context = {includeDeclaration: true}
  var reply = lspserver.rpc('textDocument/references', param)

  # Result: Location[] | null
  if reply->empty() || reply.result->empty()
    util.WarnMsg('No references found')
    return
  endif

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the reference locations
    reply.result->map((_, loc) => {
      lspserver.decodeLocation(loc)
      return loc
    })
  endif

  symbol.ShowLocations(lspserver, reply.result, peek, 'Symbol References')
enddef

# process the 'textDocument/documentHighlight' reply from the LSP server
# Result: DocumentHighlight[] | null
def DocHighlightReply(lspserver: dict<any>, docHighlightReply: any,
                      bnr: number, cmdmods: string): void
  if docHighlightReply->empty()
    if cmdmods !~ 'silent'
      util.WarnMsg($'No highlight for the current position')
    endif
    return
  endif

  for docHL in docHighlightReply
    lspserver.decodeRange(bnr, docHL.range)
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
    try
      var docHL_range = docHL.range
      var docHL_start = docHL_range.start
      var docHL_end = docHL_range.end
      prop_add(docHL_start.line + 1,
                  util.GetLineByteFromPos(bnr, docHL_start) + 1,
                  {end_lnum: docHL_end.line + 1,
                    end_col: util.GetLineByteFromPos(bnr, docHL_end) + 1,
                    bufnr: bnr,
                    type: propName})
    catch /E966\|E964/ # Invalid lnum | Invalid col
      # Highlight replies arrive asynchronously and the document might have
      # been modified in the mean time.  As the reply is stale, ignore invalid
      # line number and column number errors.
    endtry
  endfor
enddef

# Request: "textDocument/documentHighlight"
# Param: DocumentHighlightParams
def DocHighlight(lspserver: dict<any>, bnr: number, cmdmods: string): void
  # Check whether LSP server supports getting highlight information
  if !lspserver.isDocumentHighlightProvider
    util.ErrMsg('LSP server does not support document highlight')
    return
  endif

  # Send the pending buffer changes to the language server
  bnr->listener_flush()

  # interface DocumentHighlightParams
  #   interface TextDocumentPositionParams
  var params = lspserver.getTextDocPosition(false)
  lspserver.rpc_a('textDocument/documentHighlight', params, (_, reply) => {
    DocHighlightReply(lspserver, reply, bufnr(), cmdmods)
  })
enddef

# Request: "textDocument/documentSymbol"
# Param: DocumentSymbolParams
def GetDocSymbols(lspserver: dict<any>, fname: string, showOutline: bool): void
  # Check whether LSP server supports getting document symbol information
  if !lspserver.isDocumentSymbolProvider
    util.ErrMsg('LSP server does not support getting list of symbols')
    return
  endif

  # interface DocumentSymbolParams
  # interface TextDocumentIdentifier
  var params = {textDocument: {uri: util.LspFileToUri(fname)}}
  lspserver.rpc_a('textDocument/documentSymbol', params, (_, reply) => {
    if showOutline
      symbol.DocSymbolOutline(lspserver, reply, fname)
    else
      symbol.DocSymbolPopup(lspserver, reply, fname)
    endif
  })
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
    util.ErrMsg('LSP server does not support formatting documents')
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
  var fmtopts: dict<any> = {
    tabSize: shiftwidth(),
    insertSpaces: &expandtab ? true : false,
  }
  var param = {
    textDocument: {
      uri: util.LspFileToUri(fname)
    },
    options: fmtopts
  }

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

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the reference locations
    reply.result->map((_, textEdit) => {
      lspserver.decodeRange(bnr, textEdit.range)
      return textEdit
    })
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
  param = lspserver.getTextDocPosition(false)
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
    util.ErrMsg('LSP server does not support call hierarchy')
    return
  endif

  callhier.IncomingCalls(lspserver)
enddef

def GetIncomingCalls(lspserver: dict<any>, item_arg: dict<any>): any
  # Request: "callHierarchy/incomingCalls"
  # Param: CallHierarchyIncomingCallsParams
  var param = {
    item: item_arg
  }
  var reply = lspserver.rpc('callHierarchy/incomingCalls', param)
  if reply->empty()
    return null
  endif

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the incoming call locations
    var bnr = util.LspUriToBufnr(item_arg.uri)
    reply.result->map((_, hierItem) => {
      lspserver.decodeRange(bnr, hierItem.from.range)
      return hierItem
    })
  endif

  return reply.result
enddef

# Request: "callHierarchy/outgoingCalls"
def OutgoingCalls(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports call hierarchy
  if !lspserver.isCallHierarchyProvider
    util.ErrMsg('LSP server does not support call hierarchy')
    return
  endif

  callhier.OutgoingCalls(lspserver)
enddef

def GetOutgoingCalls(lspserver: dict<any>, item_arg: dict<any>): any
  # Request: "callHierarchy/outgoingCalls"
  # Param: CallHierarchyOutgoingCallsParams
  var param = {
    item: item_arg
  }
  var reply = lspserver.rpc('callHierarchy/outgoingCalls', param)
  if reply->empty()
    return null
  endif

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the outgoing call locations
    var bnr = util.LspUriToBufnr(item_arg.uri)
    reply.result->map((_, hierItem) => {
      lspserver.decodeRange(bnr, hierItem.to.range)
      return hierItem
    })
  endif

  return reply.result
enddef

# Request: "textDocument/inlayHint"
# Inlay hints.
def InlayHintsShow(lspserver: dict<any>, bnr: number)
  # Check whether LSP server supports type hierarchy
  if !lspserver.isInlayHintProvider && !lspserver.isClangdInlayHintsProvider
    util.ErrMsg('LSP server does not support inlay hint')
    return
  endif

  # Send the pending buffer changes to the language server
  bnr->listener_flush()

  var binfo = bnr->getbufinfo()
  if binfo->empty()
    return
  endif
  var lastlnum = binfo[0].linecount
  var lastline = bnr->getbufline('$')
  var lastcol = 1
  if !lastline->empty() && !lastline[0]->empty()
    lastcol = lastline[0]->strchars()
  endif
  var param = {
      textDocument: {uri: util.LspBufnrToUri(bnr)},
      range:
      {
	start: {line: 0, character: 0},
	end: {line: lastlnum - 1, character: lastcol - 1}
      }
  }

  lspserver.encodeRange(bnr, param.range)

  var msg: string
  if lspserver.isClangdInlayHintsProvider
    # clangd-style inlay hints
    msg = 'clangd/inlayHints'
  else
    msg = 'textDocument/inlayHint'
  endif
  var reply = lspserver.rpc_a(msg, param, (_, reply) => {
    inlayhints.InlayHintsReply(lspserver, bnr, reply)
  })
enddef

def DecodeTypeHierarchy(lspserver: dict<any>, isSuper: bool, typeHier: dict<any>)
  if !lspserver.needOffsetEncoding
    return
  endif
  var bnr = util.LspUriToBufnr(typeHier.uri)
  lspserver.decodeRange(bnr, typeHier.range)
  lspserver.decodeRange(bnr, typeHier.selectionRange)
  var subType: list<dict<any>>
  if isSuper
    subType = typeHier->get('parents', [])
  else
    subType = typeHier->get('children', [])
  endif
  if !subType->empty()
    # Decode the position encoding in all the type hierarchy items
    subType->map((_, typeHierItem) => {
        DecodeTypeHierarchy(lspserver, isSuper, typeHierItem)
	return typeHierItem
      })
  endif
enddef

# Request: "textDocument/typehierarchy"
# Support the clangd version of type hierarchy retrieval method.
# The method described in the LSP 3.17.0 standard is not supported as clangd
# doesn't support that method.
def TypeHierarchy(lspserver: dict<any>, direction: number)
  # Check whether LSP server supports type hierarchy
  if !lspserver.isTypeHierarchyProvider
    util.ErrMsg('LSP server does not support type hierarchy')
    return
  endif

  # interface TypeHierarchy
  #   interface TextDocumentPositionParams
  var param: dict<any>
  param = lspserver.getTextDocPosition(false)
  # 0: children, 1: parent, 2: both
  param.direction = direction
  param.resolve = 5
  var reply = lspserver.rpc('textDocument/typeHierarchy', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg('No type hierarchy available')
    return
  endif

  var isSuper = (direction == 1)

  DecodeTypeHierarchy(lspserver, isSuper, reply.result)

  typehier.ShowTypeHierarchy(lspserver, isSuper, reply.result)
enddef

# Decode the ranges in "WorkspaceEdit"
def DecodeWorkspaceEdit(lspserver: dict<any>, workspaceEdit: dict<any>)
  if !lspserver.needOffsetEncoding
    return
  endif
  if workspaceEdit->has_key('changes')
    for [uri, changes] in workspaceEdit.changes->items()
      var bnr: number = util.LspUriToBufnr(uri)
      if bnr <= 0
	continue
      endif
      # Decode the position encoding in all the text edit locations
      changes->map((_, textEdit) => {
	lspserver.decodeRange(bnr, textEdit.range)
	return textEdit
      })
    endfor
  endif

  if workspaceEdit->has_key('documentChanges')
    for change in workspaceEdit.documentChanges
      if !change->has_key('kind')
	var bnr: number = util.LspUriToBufnr(change.textDocument.uri)
	if bnr <= 0
	  continue
	endif
	# Decode the position encoding in all the text edit locations
	change.edits->map((_, textEdit) => {
	  lspserver.decodeRange(bnr, textEdit.range)
	  return textEdit
	})
      endif
    endfor
  endif
enddef

# Request: "textDocument/rename"
# Param: RenameParams
def RenameSymbol(lspserver: dict<any>, newName: string)
  # Check whether LSP server supports rename operation
  if !lspserver.isRenameProvider
    util.ErrMsg('LSP server does not support rename operation')
    return
  endif

  # interface RenameParams
  #   interface TextDocumentPositionParams
  var param: dict<any> = {}
  param = lspserver.getTextDocPosition(true)
  param.newName = newName

  var reply = lspserver.rpc('textDocument/rename', param)

  # Result: WorkspaceEdit | null
  if reply->empty() || reply.result->empty()
    # nothing to rename
    return
  endif

  # result: WorkspaceEdit
  DecodeWorkspaceEdit(lspserver, reply.result)
  textedit.ApplyWorkspaceEdit(reply.result)
enddef

# Decode the range in "CodeAction"
def DecodeCodeAction(lspserver: dict<any>, actionList: list<dict<any>>)
  if !lspserver.needOffsetEncoding
    return
  endif
  actionList->map((_, act) => {
      if !act->has_key('disabled') && act->has_key('edit')
	DecodeWorkspaceEdit(lspserver, act.edit)
      endif
      return act
    })
enddef

# Request: "textDocument/codeAction"
# Param: CodeActionParams
def CodeAction(lspserver: dict<any>, fname_arg: string, line1: number,
		line2: number, query: string)
  # Check whether LSP server supports code action operation
  if !lspserver.isCodeActionProvider
    util.ErrMsg('LSP server does not support code action operation')
    return
  endif

  # interface CodeActionParams
  var params: dict<any> = {}
  var fname: string = fname_arg->fnamemodify(':p')
  var bnr: number = fname_arg->bufnr()
  var r: dict<dict<number>> = {
    start: {
      line: line1 - 1,
      character: line1 == line2 ? util.GetCharIdxWithCompChar(getline('.'), charcol('.') - 1) : 0
    },
    end: {
      line: line2 - 1,
      character: util.GetCharIdxWithCompChar(getline(line2), charcol([line2, '$']) - 1)
    }
  }
  lspserver.encodeRange(bnr, r)
  params->extend({textDocument: {uri: util.LspFileToUri(fname)}, range: r})
  var d: list<dict<any>> = []
  for lnum in range(line1, line2)
    var diagsInfo: list<dict<any>> = diag.GetDiagsByLine(bnr, lnum, lspserver)->deepcopy()
    if lspserver.needOffsetEncoding
      diagsInfo->map((_, di) => {
	  lspserver.encodeRange(bnr, di.range)
	  return di
	})
    endif
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

  DecodeCodeAction(lspserver, reply.result)

  codeaction.ApplyCodeAction(lspserver, reply.result, query)
enddef

# Request: "textDocument/codeLens"
# Param: CodeLensParams
def CodeLens(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports code lens operation
  if !lspserver.isCodeLensProvider
    util.ErrMsg('LSP server does not support code lens operation')
    return
  endif

  var params = {textDocument: {uri: util.LspFileToUri(fname)}}
  var reply = lspserver.rpc('textDocument/codeLens', params)
  if reply->empty() || reply.result->empty()
    util.WarnMsg($'No code lens actions found for the current file')
    return
  endif

  var bnr = fname->bufnr()

  # Decode the position encoding in all the code lens items
  if lspserver.needOffsetEncoding
    reply.result->map((_, codeLensItem) => {
      lspserver.decodeRange(bnr, codeLensItem.range)
      return codeLensItem
    })
  endif

  codelens.ProcessCodeLens(lspserver, bnr, reply.result)
enddef

# Request: "codeLens/resolve"
# Param: CodeLens
def ResolveCodeLens(lspserver: dict<any>, bnr: number,
		    codeLens: dict<any>): dict<any>
  if !lspserver.isCodeLensResolveProvider
    return {}
  endif

  if lspserver.needOffsetEncoding
    lspserver.encodeRange(bnr, codeLens.range)
  endif

  var reply = lspserver.rpc('codeLens/resolve', codeLens)
  if reply->empty()
    return {}
  endif

  var codeLensItem: dict<any> = reply.result

  # Decode the position encoding in the code lens item
  if lspserver.needOffsetEncoding
    lspserver.decodeRange(bnr, codeLensItem.range)
  endif

  return codeLensItem
enddef

# List project-wide symbols matching query string
# Request: "workspace/symbol"
# Param: WorkspaceSymbolParams
def WorkspaceQuerySymbols(lspserver: dict<any>, query: string, firstCall: bool, cmdmods: string = '')
  # Check whether the LSP server supports listing workspace symbols
  if !lspserver.isWorkspaceSymbolProvider
    util.ErrMsg('LSP server does not support listing workspace symbols')
    return
  endif

  # Param: WorkspaceSymbolParams
  var param = {
    query: query
  }
  var reply = lspserver.rpc('workspace/symbol', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg($'Symbol "{query}" is not found')
    return
  endif

  var symInfo: list<dict<any>> = reply.result

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the symbol locations
    symInfo->map((_, sym) => {
      if sym->has_key('location')
	lspserver.decodeLocation(sym.location)
      endif
      return sym
    })
  endif

  if firstCall && symInfo->len() == 1
    # If there is only one symbol, then jump to the symbol location
    var symLoc: dict<any> = symInfo[0]->get('location', {})
    if !symLoc->empty()
      symbol.GotoSymbol(lspserver, symLoc, false, cmdmods)
    endif
  else
    symbol.WorkspaceSymbolPopup(lspserver, query, symInfo, cmdmods)
  endif
enddef

# Add a workspace folder to the language server.
def AddWorkspaceFolder(lspserver: dict<any>, dirName: string): void
  if !lspserver.caps->has_key('workspace')
	  || !lspserver.caps.workspace->has_key('workspaceFolders')
	  || !lspserver.caps.workspace.workspaceFolders->has_key('supported')
	  || !lspserver.caps.workspace.workspaceFolders.supported
      util.ErrMsg('LSP server does not support workspace folders')
    return
  endif

  if lspserver.workspaceFolders->index(dirName) != -1
    util.ErrMsg($'{dirName} is already part of this workspace')
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
      util.ErrMsg('LSP server does not support workspace folders')
    return
  endif

  var idx: number = lspserver.workspaceFolders->index(dirName)
  if idx == -1
    util.ErrMsg($'{dirName} is not currently part of this workspace')
    return
  endif

  # Notification: "workspace/didChangeWorkspaceFolders"
  # Param: DidChangeWorkspaceFoldersParams
  var params = {event: {added: [], removed: [dirName]}}
  lspserver.sendNotification('workspace/didChangeWorkspaceFolders', params)

  lspserver.workspaceFolders->remove(idx)
enddef

def DecodeSelectionRange(lspserver: dict<any>, bnr: number, selRange: dict<any>)
  lspserver.decodeRange(bnr, selRange.range)
  if selRange->has_key('parent')
    DecodeSelectionRange(lspserver, bnr, selRange.parent)
  endif
enddef

# select the text around the current cursor location
# Request: "textDocument/selectionRange"
# Param: SelectionRangeParams
def SelectionRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports selection ranges
  if !lspserver.isSelectionRangeProvider
    util.ErrMsg('LSP server does not support selection ranges')
    return
  endif

  # clear the previous selection reply
  lspserver.selection = {}

  # interface SelectionRangeParams
  # interface TextDocumentIdentifier
  var param = {
    textDocument: {
      uri: util.LspFileToUri(fname)
    },
    positions: [lspserver.getPosition(false)]
  }
  var reply = lspserver.rpc('textDocument/selectionRange', param)

  if reply->empty() || reply.result->empty()
    return
  endif

  # Decode the position encoding in all the selection range items
  if lspserver.needOffsetEncoding
    var bnr = fname->bufnr()
    reply.result->map((_, selItem) => {
	DecodeSelectionRange(lspserver, bnr, selItem)
	return selItem
      })
  endif

  selection.SelectionStart(lspserver, reply.result)
enddef

# Expand the previous selection or start a new one
def SelectionExpand(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.isSelectionRangeProvider
    util.ErrMsg('LSP server does not support selection ranges')
    return
  endif

  selection.SelectionModify(lspserver, true)
enddef

# Shrink the previous selection or start a new one
def SelectionShrink(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.isSelectionRangeProvider
    util.ErrMsg('LSP server does not support selection ranges')
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
    util.ErrMsg('LSP server does not support folding')
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
  var params: dict<any> = {}
  params.command = cmd.command
  if cmd->has_key('arguments')
    params.arguments = cmd.arguments
  endif

  lspserver.rpc_a('workspace/executeCommand', params, WorkspaceExecuteReply)
enddef

# Display the LSP server capabilities (received during the initialization
# stage).
def GetCapabilities(lspserver: dict<any>): list<string>
  var l = []
  var heading = $"'{lspserver.path}' Language Server Capabilities"
  var underlines = repeat('=', heading->len())
  l->extend([heading, underlines])
  for k in lspserver.caps->keys()->sort()
    l->add($'{k}: {lspserver.caps[k]->string()}')
  endfor
  return l
enddef

# Display the LSP server initialize request and result
def GetInitializeRequest(lspserver: dict<any>): list<string>
  var l = []
  var heading = $"'{lspserver.path}' Language Server Initialize Request"
  var underlines = repeat('=', heading->len())
  l->extend([heading, underlines])
  if lspserver->has_key('rpcInitializeRequest')
    for k in lspserver.rpcInitializeRequest->keys()->sort()
      l->add($'{k}: {lspserver.rpcInitializeRequest[k]->string()}')
    endfor
  endif
  return l
enddef

# Store a log or trace message received from the language server.
def AddMessage(lspserver: dict<any>, msgType: string, newMsg: string)
  # A single message may contain multiple lines separate by newline
  var msgs = newMsg->split("\n")
  lspserver.messages->add($'{strftime("%m/%d/%y %T")}: [{msgType}]: {msgs[0]}')
  lspserver.messages->extend(msgs[1 : ])
  # Keep only the last 500 messages to reduce the memory usage
  if lspserver.messages->len() >= 600
    lspserver.messages = lspserver.messages[-500 : ]
  endif
enddef

# Display the log messages received from the LSP server (window/logMessage)
def GetMessages(lspserver: dict<any>): list<string>
  if lspserver.messages->empty()
    return [$'No messages received from "{lspserver.name}" server']
  endif

  var l = []
  var heading = $"'{lspserver.path}' Language Server Messages"
  var underlines = repeat('=', heading->len())
  l->extend([heading, underlines])
  l->extend(lspserver.messages)
  return l
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
  var reply = lspserver.rpc('textDocument/definition',
			    lspserver.getTextDocPosition(false))
  if reply->empty() || reply.result->empty()
    return null
  endif

  var taglocations: list<dict<any>>
  if reply.result->type() == v:t_list
    taglocations = reply.result
  else
    taglocations = [reply.result]
  endif

  if lspserver.needOffsetEncoding
    # Decode the position encoding in all the reference locations
    taglocations->map((_, loc) => {
      lspserver.decodeLocation(loc)
      return loc
    })
  endif

  return symbol.TagFunc(lspserver, taglocations, pat)
enddef

# Returns unique ID used for identifying the various servers
var UniqueServerIdCounter = 0
def GetUniqueServerId(): number
  UniqueServerIdCounter = UniqueServerIdCounter + 1
  return UniqueServerIdCounter
enddef

export def NewLspServer(serverParams: dict<any>): dict<any>
  var lspserver: dict<any> = {
    id: GetUniqueServerId(),
    name: serverParams.name,
    path: serverParams.path,
    args: serverParams.args->deepcopy(),
    running: false,
    ready: false,
    job: v:none,
    data: '',
    nextID: 1,
    caps: {},
    requests: {},
    callHierarchyType: '',
    completionTriggerChars: [],
    customNotificationHandlers: serverParams.customNotificationHandlers->deepcopy(),
    customRequestHandlers: serverParams.customRequestHandlers->deepcopy(),
    debug: serverParams.debug,
    features: serverParams.features->deepcopy(),
    forceOffsetEncoding: serverParams.forceOffsetEncoding,
    initializationOptions: serverParams.initializationOptions->deepcopy(),
    messages: [],
    needOffsetEncoding: false,
    omniCompletePending: false,
    peekSymbolFilePopup: -1,
    peekSymbolPopup: -1,
    processDiagHandler: serverParams.processDiagHandler,
    rootSearchFiles: serverParams.rootSearch->deepcopy(),
    runIfSearchFiles: serverParams.runIfSearch->deepcopy(),
    runUnlessSearchFiles: serverParams.runUnlessSearch->deepcopy(),
    selection: {},
    signaturePopup: -1,
    syncInit: serverParams.syncInit,
    traceLevel: serverParams.traceLevel,
    typeHierFilePopup: -1,
    typeHierPopup: -1,
    workspaceConfig: serverParams.workspaceConfig->deepcopy(),
    workspaceSymbolPopup: -1,
    workspaceSymbolQuery: ''
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
    encodePosition: function(offset.EncodePosition, [lspserver]),
    decodePosition: function(offset.DecodePosition, [lspserver]),
    encodeRange: function(offset.EncodeRange, [lspserver]),
    decodeRange: function(offset.DecodeRange, [lspserver]),
    encodeLocation: function(offset.EncodeLocation, [lspserver]),
    decodeLocation: function(offset.DecodeLocation, [lspserver]),
    getPosition: function(GetPosition, [lspserver]),
    getTextDocPosition: function(GetTextDocPosition, [lspserver]),
    featureEnabled: function(FeatureEnabled, [lspserver]),
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
    typeHierarchy: function(TypeHierarchy, [lspserver]),
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
    semanticHighlightUpdate: function(SemanticHighlightUpdate, [lspserver]),
    getCapabilities: function(GetCapabilities, [lspserver]),
    getInitializeRequest: function(GetInitializeRequest, [lspserver]),
    addMessage: function(AddMessage, [lspserver]),
    getMessages: function(GetMessages, [lspserver])
  })

  return lspserver
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
