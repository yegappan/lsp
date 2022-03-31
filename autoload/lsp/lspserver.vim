vim9script

# LSP server functions
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specificaiton.

var handlers = {}
var diag = {}
var util = {}
var selection = {}

if has('patch-8.2.4019')
  import './handlers.vim' as handlers_import
  import './util.vim' as util_import
  import './diag.vim' as diag_import
  import './selection.vim' as selection_import

  handlers.ProcessReply = handlers_import.ProcessReply
  handlers.ProcessNotif = handlers_import.ProcessNotif
  handlers.ProcessRequest = handlers_import.ProcessRequest
  handlers.ProcessMessages = handlers_import.ProcessMessages
  util.WarnMsg = util_import.WarnMsg
  util.ErrMsg = util_import.ErrMsg
  util.TraceLog = util_import.TraceLog
  util.LspBufnrToUri = util_import.LspBufnrToUri
  util.LspFileToUri = util_import.LspFileToUri
  util.PushCursorToTagStack = util_import.PushCursorToTagStack
  diag.GetDiagByLine = diag_import.GetDiagByLine
  selection.SelectionModify = selection_import.SelectionModify
else
  import {ProcessReply,
	ProcessNotif,
	ProcessRequest,
	ProcessMessages} from './handlers.vim'
  import {GetDiagByLine} from './diag.vim'
  import {WarnMsg,
	ErrMsg,
	TraceLog,
	LspBufnrToUri,
	LspFileToUri,
	PushCursorToTagStack} from './util.vim'
  import {SelectionModify} from './selection.vim'

  handlers.ProcessReply = ProcessReply
  handlers.ProcessNotif = ProcessNotif
  handlers.ProcessRequest = ProcessRequest
  handlers.ProcessMessages = ProcessMessages
  util.WarnMsg = WarnMsg
  util.ErrMsg = ErrMsg
  util.TraceLog = TraceLog
  util.LspBufnrToUri = LspBufnrToUri
  util.LspFileToUri = LspFileToUri
  util.PushCursorToTagStack = PushCursorToTagStack
  diag.GetDiagByLine = GetDiagByLine
  selection.SelectionModify = SelectionModify
endif

# LSP server standard output handler
def Output_cb(lspserver: dict<any>, chan: channel, msg: string): void
  util.TraceLog(false, msg)
  lspserver.data = lspserver.data .. msg
  lspserver.processMessages()
enddef

# LSP server error output handler
def Error_cb(lspserver: dict<any>, chan: channel, emsg: string,): void
  util.TraceLog(true, emsg)
enddef

# LSP server exit callback
def Exit_cb(lspserver: dict<any>, job: job, status: number): void
  util.WarnMsg("LSP server exited with status " .. status)
  lspserver.running = false
  lspserver.ready = false
  lspserver.requests = {}
enddef

# Start a LSP server
#
# If 'isSync' is true, then waits for the server to send the initialize
# response message.
def StartServer(lspserver: dict<any>, isSync: bool = false): number
  if lspserver.running
    util.WarnMsg("LSP server for is already running")
    return 0
  endif

  var cmd = [lspserver.path]
  cmd->extend(lspserver.args)

  var opts = {in_mode: 'raw',
		out_mode: 'raw',
		err_mode: 'raw',
		noblock: 1,
		out_cb: function(Output_cb, [lspserver]),
		err_cb: function(Error_cb, [lspserver]),
		exit_cb: function(Exit_cb, [lspserver])}

  lspserver.data = ''
  lspserver.caps = {}
  lspserver.nextID = 1
  lspserver.requests = {}
  lspserver.completePending = false
  lspserver.completionTriggerChars = []
  lspserver.signaturePopup = -1
  lspserver.workspaceFolders = [getcwd()]

  var job = job_start(cmd, opts)
  if job->job_status() == 'fail'
    util.ErrMsg("Error: Failed to start LSP server " .. lspserver.path)
    return 1
  endif

  # wait a little for the LSP server to start
  sleep 10m

  lspserver.job = job
  lspserver.running = true

  lspserver.initServer(isSync)

  return 0
enddef

# Request: 'initialize'
# Param: InitializeParams
#
# If 'isSync' is true, then waits for the server to send the initialize
# response message.
def InitServer(lspserver: dict<any>, isSync: bool = false)
  var req = lspserver.createRequest('initialize')

  # client capabilities (ClientCapabilities)
  var clientCaps: dict<any> = {
    workspace: {
      workspaceFolders: true,
      applyEdit: true
    },
    textDocument: {
      foldingRange: {lineFoldingOnly: true},
      completion: {
	completionItem: {
	  documentationFormat: ['plaintext', 'markdown'],
	  snippetSupport: false
	},
	completionItemKind: {valueSet: range(1, 25)}
      },
      hover: {
        contentFormat: ['plaintext', 'markdown']
      },
      documentSymbol: {
	hierarchicalDocumentSymbolSupport: true,
	symbolKind: {valueSet: range(1, 25)}
      },
    },
    window: {},
    general: {}
  }

  # interface 'InitializeParams'
  var initparams: dict<any> = {}
  initparams.processId = getpid()
  initparams.clientInfo = {
	name: 'Vim',
	version: v:versionlong->string(),
      }
  var curdir: string = getcwd()
  initparams.rootPath = curdir
  initparams.rootUri = util.LspFileToUri(curdir)
  initparams.workspaceFolders = [{
	name: fnamemodify(curdir, ':t'),
	uri: util.LspFileToUri(curdir)
     }]
  initparams.trace = 'off'
  initparams.capabilities = clientCaps
  req.params->extend(initparams)

  lspserver.sendMessage(req)
  if isSync
    lspserver.waitForResponse(req)
  endif
enddef

# Send a "initialized" LSP notification
# Params: InitializedParams
def SendInitializedNotif(lspserver: dict<any>)
  var notif: dict<any> = lspserver.createNotification('initialized')
  lspserver.sendMessage(notif)
enddef

# Request: shutdown
# Param: void
def ShutdownServer(lspserver: dict<any>): void
  var req = lspserver.createRequest('shutdown')
  lspserver.sendMessage(req)
  lspserver.waitForResponse(req)
enddef

# Send a 'exit' notification to the LSP server
# Params: void
def ExitServer(lspserver: dict<any>): void
  var notif: dict<any> = lspserver.createNotification('exit')
  lspserver.sendMessage(notif)
enddef

# Stop a LSP server
def StopServer(lspserver: dict<any>): number
  if !lspserver.running
    util.WarnMsg("LSP server is not running")
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

# set the LSP server trace level using $/setTrace notification
def SetTrace(lspserver: dict<any>, traceVal: string)
  var notif: dict<any> = lspserver.createNotification('$/setTrace')
  notif.params->extend({value: traceVal})
  lspserver.sendMessage(notif)
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
def SendResponse(lspserver: dict<any>, request: dict<any>, result: dict<any>, error: dict<any>)
  if (type(request.id) == v:t_string && (trim(request.id) =~ '[^[:digit:]]\+' || trim(request.id) == ''))
    || (type(request.id) != v:t_string && type(request.id) != v:t_number)
    util.ErrMsg("Error: request.id of response to LSP server is not a correct number")
    return
  endif
  var resp: dict<any> = lspserver.createResponse(type(request.id) == v:t_string ? str2nr(request.id) : request.id)
  if result->type() != v:t_none
    resp->extend({result: result})
  else
    resp->extend({error: error})
  endif
  lspserver.sendMessage(resp)
enddef

# Send a request message to LSP server
def SendMessage(lspserver: dict<any>, content: dict<any>): void
  var payload_js: string = content->json_encode()
  var msg = "Content-Length: " .. payload_js->len() .. "\r\n\r\n"
  var ch = lspserver.job->job_getchannel()
  if ch_status(ch) != 'open'
    # LSP server has exited
    return
  endif
  ch->ch_sendraw(msg)
  ch->ch_sendraw(payload_js)
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

# Send a LSP "textDocument/didOpen" notification
# Params: DidOpenTextDocumentParams
def TextdocDidOpen(lspserver: dict<any>, bnr: number, ftype: string): void
  var notif: dict<any> = lspserver.createNotification('textDocument/didOpen')

  # interface DidOpenTextDocumentParams
  # interface TextDocumentItem
  var tdi = {}
  tdi.uri = util.LspBufnrToUri(bnr)
  tdi.languageId = ftype
  tdi.version = 1
  tdi.text = getbufline(bnr, 1, '$')->join("\n") .. "\n"
  notif.params->extend({textDocument: tdi})

  lspserver.sendMessage(notif)
enddef

# Send a LSP "textDocument/didClose" notification
def TextdocDidClose(lspserver: dict<any>, bnr: number): void
  var notif: dict<any> = lspserver.createNotification('textDocument/didClose')

  # interface DidCloseTextDocumentParams
  #   interface TextDocumentIdentifier
  var tdid = {}
  tdid.uri = util.LspBufnrToUri(bnr)
  notif.params->extend({textDocument: tdid})

  lspserver.sendMessage(notif)
enddef

# Send a LSP "textDocument/didChange" notification
# Params: DidChangeTextDocumentParams
def TextdocDidChange(lspserver: dict<any>, bnr: number, start: number,
			end: number, added: number,
			changes: list<dict<number>>): void
  var notif: dict<any> = lspserver.createNotification('textDocument/didChange')

  # interface DidChangeTextDocumentParams
  #   interface VersionedTextDocumentIdentifier
  var vtdid: dict<any> = {}
  vtdid.uri = util.LspBufnrToUri(bnr)
  # Use Vim 'changedtick' as the LSP document version number
  vtdid.version = bnr->getbufvar('changedtick')

  #   interface TextDocumentContentChangeEvent
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

  changeset->add({text: getbufline(bnr, 1, '$')->join("\n") .. "\n"})
  notif.params->extend({textDocument: vtdid, contentChanges: changeset})

  lspserver.sendMessage(notif)
enddef

# Return the current cursor position as a LSP position.
# LSP line and column numbers start from zero, whereas Vim line and column
# numbers start from one. The LSP column number is the character index in the
# line and not the byte index in the line.
def GetLspPosition(): dict<number>
  var lnum: number = line('.') - 1
  var col: number = charcol('.') - 1
  return {line: lnum, character: col}
enddef

# Return the current file name and current cursor position as a LSP
# TextDocumentPositionParams structure
def GetLspTextDocPosition(): dict<dict<any>>
  # interface TextDocumentIdentifier
  # interface Position
  return {textDocument: {uri: util.LspFileToUri(@%)},
	  position: GetLspPosition()}
enddef

# Get a list of completion items.
# Request: "textDocument/completion"
# Param: CompletionParams
def GetCompletion(lspserver: dict<any>, triggerKind_arg: number): void
  # Check whether LSP server supports completion
  if !lspserver.caps->has_key('completionProvider')
    util.ErrMsg("Error: LSP server does not support completion")
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  var req = lspserver.createRequest('textDocument/completion')

  # interface CompletionParams
  #   interface TextDocumentPositionParams
  req.params = GetLspTextDocPosition()
  #   interface CompletionContext
  req.params.context = {triggerKind: triggerKind_arg}

  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/definition"
# Param: DefinitionParams
def GotoDefinition(lspserver: dict<any>, peek: bool)
  # Check whether LSP server supports jumping to a definition
  if !lspserver.caps->has_key('definitionProvider')
				|| !lspserver.caps.definitionProvider
    util.ErrMsg("Error: LSP server does not support jumping to a definition")
    return
  endif

  if !peek
    util.PushCursorToTagStack()
  endif
  lspserver.peekSymbol = peek
  var req = lspserver.createRequest('textDocument/definition')
  # interface DefinitionParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())
  lspserver.sendMessage(req)

  lspserver.waitForResponse(req)
enddef

# Request: "textDocument/switchSourceHeader"
# Param: TextDocumentIdentifier
# Clangd specific extension
def SwitchSourceHeader(lspserver: dict<any>)
  var req = lspserver.createRequest('textDocument/switchSourceHeader')
  req.params->extend({uri: util.LspFileToUri(@%)})
  lspserver.sendMessage(req)

  lspserver.waitForResponse(req)
enddef

# Request: "textDocument/declaration"
# Param: DeclarationParams
def GotoDeclaration(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports jumping to a declaration
  if !lspserver.caps->has_key('declarationProvider')
			|| !lspserver.caps.declarationProvider
    util.ErrMsg("Error: LSP server does not support jumping to a declaration")
    return
  endif

  if !peek
    util.PushCursorToTagStack()
  endif
  lspserver.peekSymbol = peek
  var req = lspserver.createRequest('textDocument/declaration')

  # interface DeclarationParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())

  lspserver.sendMessage(req)

  lspserver.waitForResponse(req)
enddef

# Request: "textDocument/typeDefinition"
# Param: TypeDefinitionParams
def GotoTypeDef(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports jumping to a type definition
  if !lspserver.caps->has_key('typeDefinitionProvider')
			|| !lspserver.caps.typeDefinitionProvider
    util.ErrMsg("Error: LSP server does not support jumping to a type definition")
    return
  endif

  if !peek
    util.PushCursorToTagStack()
  endif
  lspserver.peekSymbol = peek
  var req = lspserver.createRequest('textDocument/typeDefinition')

  # interface TypeDefinitionParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())

  lspserver.sendMessage(req)

  lspserver.waitForResponse(req)
enddef

# Request: "textDocument/implementation"
# Param: ImplementationParams
def GotoImplementation(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports jumping to a implementation
  if !lspserver.caps->has_key('implementationProvider')
			|| !lspserver.caps.implementationProvider
    util.ErrMsg("Error: LSP server does not support jumping to an implementation")
    return
  endif

  if !peek
    util.PushCursorToTagStack()
  endif
  lspserver.peekSymbol = peek
  var req = lspserver.createRequest('textDocument/implementation')

  # interface ImplementationParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())

  lspserver.sendMessage(req)

  lspserver.waitForResponse(req)
enddef

# get symbol signature help.
# Request: "textDocument/signatureHelp"
# Param: SignatureHelpParams
def ShowSignature(lspserver: dict<any>): void
  # Check whether LSP server supports signature help
  if !lspserver.caps->has_key('signatureHelpProvider')
    util.ErrMsg("Error: LSP server does not support signature help")
    return
  endif

  var req = lspserver.createRequest('textDocument/signatureHelp')
  # interface SignatureHelpParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())

  lspserver.sendMessage(req)

  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

def DidSaveFile(lspserver: dict<any>, bnr: number): void
  # Check whether the LSP server supports the didSave notification
  if !lspserver.caps->has_key('textDocumentSync')
		|| lspserver.caps.textDocumentSync->type() == v:t_number
		|| !lspserver.caps.textDocumentSync->has_key('save')
		|| !lspserver.caps.textDocumentSync.save
    # LSP server doesn't support text document synchronization
    return
  endif

  var notif: dict<any> = lspserver.createNotification('textDocument/didSave')
  # interface: DidSaveTextDocumentParams
  notif.params->extend({textDocument: {uri: util.LspBufnrToUri(bnr)}})
  lspserver.sendMessage(notif)
enddef

# get the hover information
# Request: "textDocument/hover"
# Param: HoverParams
def ShowHoverInfo(lspserver: dict<any>): void
  # Check whether LSP server supports getting hover information
  if !lspserver.caps->has_key('hoverProvider')
			|| !lspserver.caps.hoverProvider
    return
  endif

  var req = lspserver.createRequest('textDocument/hover')
  # interface HoverParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/references"
# Param: ReferenceParams
def ShowReferences(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports getting reference information
  if !lspserver.caps->has_key('referencesProvider')
			|| !lspserver.caps.referencesProvider
    util.ErrMsg("Error: LSP server does not support showing references")
    return
  endif

  var req = lspserver.createRequest('textDocument/references')
  # interface ReferenceParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())
  req.params->extend({context: {includeDeclaration: true}})

  lspserver.peekSymbol = peek
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/documentHighlight"
# Param: DocumentHighlightParams
def DocHighlight(lspserver: dict<any>): void
  # Check whether LSP server supports getting highlight information
  if !lspserver.caps->has_key('documentHighlightProvider')
			|| !lspserver.caps.documentHighlightProvider
    util.ErrMsg("Error: LSP server does not support document highlight")
    return
  endif

  var req = lspserver.createRequest('textDocument/documentHighlight')
  # interface DocumentHighlightParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/documentSymbol"
# Param: DocumentSymbolParams
def GetDocSymbols(lspserver: dict<any>, fname: string): void
  # Check whether LSP server supports getting document symbol information
  if !lspserver.caps->has_key('documentSymbolProvider')
			|| !lspserver.caps.documentSymbolProvider
    util.ErrMsg("Error: LSP server does not support getting list of symbols")
    return
  endif

  var req = lspserver.createRequest('textDocument/documentSymbol')
  # interface DocumentSymbolParams
  # interface TextDocumentIdentifier
  req.params->extend({textDocument: {uri: util.LspFileToUri(fname)}})
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/formatting"
# Param: DocumentFormattingParams
# or
# Request: "textDocument/rangeFormatting"
# Param: DocumentRangeFormattingParams
def TextDocFormat(lspserver: dict<any>, fname: string, rangeFormat: bool,
				start_lnum: number, end_lnum: number)
  # Check whether LSP server supports formatting documents
  if !lspserver.caps->has_key('documentFormattingProvider')
			|| !lspserver.caps.documentFormattingProvider
    util.ErrMsg("Error: LSP server does not support formatting documents")
    return
  endif

  var cmd: string
  if rangeFormat
    cmd = 'textDocument/rangeFormatting'
  else
    cmd = 'textDocument/formatting'
  endif
  var req = lspserver.createRequest(cmd)

  # interface DocumentFormattingParams
  # interface TextDocumentIdentifier
  # interface FormattingOptions
  var fmtopts: dict<any> = {
    tabSize: shiftwidth(),
    insertSpaces: &expandtab ? true : false,
  }
  #req.params->extend({textDocument: {uri: util.LspFileToUri(fname)},
  #							options: fmtopts})
  req.params->extend({textDocument: {uri: util.LspFileToUri(fname)}, options: fmtopts})
  if rangeFormat
    var r: dict<dict<number>> = {
	start: {line: start_lnum - 1, character: 0},
	end: {line: end_lnum, character: 0}}
    req.params->extend({range: r})
  endif

  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/prepareCallHierarchy"
# Param: CallHierarchyPrepareParams
def PrepareCallHierarchy(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports call hierarchy
  if !lspserver.caps->has_key('callHierarchyProvider')
			|| !lspserver.caps.callHierarchyProvider
    util.ErrMsg("Error: LSP server does not support call hierarchy")
    return
  endif

  var req = lspserver.createRequest('textDocument/prepareCallHierarchy')

  # interface CallHierarchyPrepareParams
  #   interface TextDocumentPositionParams
  req.params->extend(GetLspTextDocPosition())
  lspserver.sendMessage(req)
enddef

# Request: "callHierarchy/incomingCalls"
# Param: CallHierarchyItem
def IncomingCalls(lspserver: dict<any>, hierItem: dict<any>)
  # Check whether LSP server supports call hierarchy
  if !lspserver.caps->has_key('callHierarchyProvider')
			|| !lspserver.caps.callHierarchyProvider
    util.ErrMsg("Error: LSP server does not support call hierarchy")
    return
  endif

  var req = lspserver.createRequest('callHierarchy/incomingCalls')

  # interface CallHierarchyIncomingCallsParams
  #   interface CallHierarchyItem
  req.params->extend({item: hierItem})
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "callHierarchy/outgoingCalls"
# Param: CallHierarchyItem
def OutgoingCalls(lspserver: dict<any>, hierItem: dict<any>)
  # Check whether LSP server supports call hierarchy
  if !lspserver.caps->has_key('callHierarchyProvider')
			|| !lspserver.caps.callHierarchyProvider
    util.ErrMsg("Error: LSP server does not support call hierarchy")
    return
  endif

  var req = lspserver.createRequest('callHierarchy/outgoingCalls')

  # interface CallHierarchyOutgoingCallsParams
  #   interface CallHierarchyItem
  req.params->extend({item: hierItem})
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/rename"
# Param: RenameParams
def RenameSymbol(lspserver: dict<any>, newName: string)
  # Check whether LSP server supports rename operation
  if !lspserver.caps->has_key('renameProvider')
			|| !lspserver.caps.renameProvider
    util.ErrMsg("Error: LSP server does not support rename operation")
    return
  endif

  var req = lspserver.createRequest('textDocument/rename')
  # interface RenameParams
  #   interface TextDocumentPositionParams
  req.params = GetLspTextDocPosition()
  req.params.newName = newName
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request: "textDocument/codeAction"
# Param: CodeActionParams
def CodeAction(lspserver: dict<any>, fname_arg: string)
  # Check whether LSP server supports code action operation
  if !lspserver.caps->has_key('codeActionProvider')
			|| !lspserver.caps.codeActionProvider
    util.ErrMsg("Error: LSP server does not support code action operation")
    return
  endif

  var req = lspserver.createRequest('textDocument/codeAction')

  # interface CodeActionParams
  var fname: string = fnamemodify(fname_arg, ':p')
  var bnr: number = fname_arg->bufnr()
  var r: dict<dict<number>> = {
		  start: {line: line('.') - 1, character: charcol('.') - 1},
		  end: {line: line('.') - 1, character: charcol('.') - 1}}
  req.params->extend({textDocument: {uri: util.LspFileToUri(fname)}, range: r})
  var d: list<dict<any>> = []
  var lnum = line('.')
  var diagInfo: dict<any> = diag.GetDiagByLine(lspserver, bnr, lnum)
  if !diagInfo->empty()
    d->add(diagInfo)
  endif
  req.params->extend({context: {diagnostics: d}})

  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# List project-wide symbols matching query string
# Request: "workspace/symbol"
# Param: WorkspaceSymbolParams
def WorkspaceQuerySymbols(lspserver: dict<any>, query: string): bool
  # Check whether the LSP server supports listing workspace symbols
  if !lspserver.caps->has_key('workspaceSymbolProvider')
				|| !lspserver.caps.workspaceSymbolProvider
    util.ErrMsg("Error: LSP server does not support listing workspace symbols")
    return false
  endif

  var req = lspserver.createRequest('workspace/symbol')
  req.params->extend({query: query})
  lspserver.sendMessage(req)

  return true
enddef

# Add a workspace folder to the LSP server.
# Request: "workspace/didChangeWorkspaceFolders"
# Param: DidChangeWorkspaceFoldersParams
def AddWorkspaceFolder(lspserver: dict<any>, dirName: string): void
  if !lspserver.caps->has_key('workspace')
	  || !lspserver.caps.workspace->has_key('workspaceFolders')
	  || !lspserver.caps.workspace.workspaceFolders->has_key('supported')
	  || !lspserver.caps.workspace.workspaceFolders.supported
      util.ErrMsg('Error: LSP server does not support workspace folders')
    return
  endif

  if lspserver.workspaceFolders->index(dirName) != -1
    util.ErrMsg('Error: ' .. dirName .. ' is already part of this workspace')
    return
  endif

  var notif: dict<any> =
	lspserver.createNotification('workspace/didChangeWorkspaceFolders')
  # interface DidChangeWorkspaceFoldersParams
  notif.params->extend({event: {added: [dirName], removed: []}})
  lspserver.sendMessage(notif)

  lspserver.workspaceFolders->add(dirName)
enddef

# Remove a workspace folder from the LSP server.
# Request: "workspace/didChangeWorkspaceFolders"
# Param: DidChangeWorkspaceFoldersParams
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
    util.ErrMsg('Error: ' .. dirName .. ' is not currently part of this workspace')
    return
  endif

  var notif: dict<any> =
	lspserver.createNotification('workspace/didChangeWorkspaceFolders')
  # interface DidChangeWorkspaceFoldersParams
  notif.params->extend({event: {added: [], removed: [dirName]}})
  lspserver.sendMessage(notif)

  lspserver.workspaceFolders->remove(idx)
enddef

# select the text around the current cursor location
# Request: "textDocument/selectionRange"
# Param: SelectionRangeParams
def SelectionRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports selection ranges
  if !lspserver.caps->has_key('selectionRangeProvider')
			|| !lspserver.caps.selectionRangeProvider
    util.ErrMsg("Error: LSP server does not support selection ranges")
    return
  endif

  # clear the previous selection reply
  lspserver.selection = {}

  var req = lspserver.createRequest('textDocument/selectionRange')
  # interface SelectionRangeParams
  # interface TextDocumentIdentifier
  req.params->extend({textDocument: {uri: util.LspFileToUri(fname)}, positions: [GetLspPosition()]})
  lspserver.sendMessage(req)

  lspserver.waitForResponse(req)
enddef

# Expand the previous selection or start a new one
def SelectionExpand(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.caps->has_key('selectionRangeProvider')
			|| !lspserver.caps.selectionRangeProvider
    util.ErrMsg("Error: LSP server does not support selection ranges")
    return
  endif

  selection.SelectionModify(lspserver, true)
enddef

# Shrink the previous selection or start a new one
def SelectionShrink(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.caps->has_key('selectionRangeProvider')
			|| !lspserver.caps.selectionRangeProvider
    util.ErrMsg("Error: LSP server does not support selection ranges")
    return
  endif

  selection.SelectionModify(lspserver, false)
enddef

# fold the entire document
# Request: "textDocument/foldingRange"
# Param: FoldingRangeParams
def FoldRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports fold ranges
  if !lspserver.caps->has_key('foldingRangeProvider')
			|| !lspserver.caps.foldingRangeProvider
    util.ErrMsg("Error: LSP server does not support folding")
    return
  endif

  var req = lspserver.createRequest('textDocument/foldingRange')
  # interface FoldingRangeParams
  # interface TextDocumentIdentifier
  req.params->extend({textDocument: {uri: util.LspFileToUri(fname)}})
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Request the LSP server to execute a command
# Request: workspace/executeCommand
# Params: ExecuteCommandParams
def ExecuteCommand(lspserver: dict<any>, cmd: dict<any>)
  var req = lspserver.createRequest('workspace/executeCommand')
  req.params->extend(cmd)
  lspserver.sendMessage(req)
  if exists('g:LSPTest') && g:LSPTest
    # When running LSP tests, make this a synchronous call
    lspserver.waitForResponse(req)
  endif
enddef

# Display the LSP server capabilities (received during the initialization
# stage).
def ShowCapabilities(lspserver: dict<any>)
  echo "Capabilities of '" .. lspserver.path .. "' LSP server:"
  for k in lspserver.caps->keys()->sort()
    echo k .. ": " .. lspserver.caps[k]->string()
  endfor
enddef

export def NewLspServer(path: string, args: list<string>): dict<any>
  var lspserver: dict<any> = {
    path: path,
    args: args,
    running: false,
    ready: false,
    job: v:none,
    data: '',
    nextID: 1,
    caps: {},
    requests: {},
    completePending: false,
    completionTriggerChars: [],
    signaturePopup: -1,
    diagsMap: {},
    workspaceSymbolPopup: 0,
    workspaceSymbolQuery: '',
    peekSymbol: false,
    callHierarchyType: '',
    selection: {}
  }
  # Add the LSP server functions
  lspserver->extend({
    startServer: function(StartServer, [lspserver]),
    initServer: function(InitServer, [lspserver]),
    stopServer: function(StopServer, [lspserver]),
    shutdownServer: function(ShutdownServer, [lspserver]),
    exitServer: function(ExitServer, [lspserver]),
    setTrace: function(SetTrace, [lspserver]),
    nextReqID: function(NextReqID, [lspserver]),
    createRequest: function(CreateRequest, [lspserver]),
    createResponse: function(CreateResponse, [lspserver]),
    createNotification: function(CreateNotification, [lspserver]),
    sendResponse: function(SendResponse, [lspserver]),
    sendMessage: function(SendMessage, [lspserver]),
    waitForResponse: function(WaitForResponse, [lspserver]),
    processReply: function(handlers.ProcessReply, [lspserver]),
    processNotif: function(handlers.ProcessNotif, [lspserver]),
    processRequest: function(handlers.ProcessRequest, [lspserver]),
    processMessages: function(handlers.ProcessMessages, [lspserver]),
    getDiagByLine: function(diag.GetDiagByLine, [lspserver]),
    textdocDidOpen: function(TextdocDidOpen, [lspserver]),
    textdocDidClose: function(TextdocDidClose, [lspserver]),
    textdocDidChange: function(TextdocDidChange, [lspserver]),
    sendInitializedNotif: function(SendInitializedNotif, [lspserver]),
    getCompletion: function(GetCompletion, [lspserver]),
    gotoDefinition: function(GotoDefinition, [lspserver]),
    switchSourceHeader: function(SwitchSourceHeader, [lspserver]),
    gotoDeclaration: function(GotoDeclaration, [lspserver]),
    gotoTypeDef: function(GotoTypeDef, [lspserver]),
    gotoImplementation: function(GotoImplementation, [lspserver]),
    showSignature: function(ShowSignature, [lspserver]),
    didSaveFile: function(DidSaveFile, [lspserver]),
    hover: function(ShowHoverInfo, [lspserver]),
    showReferences: function(ShowReferences, [lspserver]),
    docHighlight: function(DocHighlight, [lspserver]),
    getDocSymbols: function(GetDocSymbols, [lspserver]),
    textDocFormat: function(TextDocFormat, [lspserver]),
    prepareCallHierarchy: function(PrepareCallHierarchy, [lspserver]),
    incomingCalls: function(IncomingCalls, [lspserver]),
    outgoingCalls: function(OutgoingCalls, [lspserver]),
    renameSymbol: function(RenameSymbol, [lspserver]),
    codeAction: function(CodeAction, [lspserver]),
    workspaceQuery: function(WorkspaceQuerySymbols, [lspserver]),
    addWorkspaceFolder: function(AddWorkspaceFolder, [lspserver]),
    removeWorkspaceFolder: function(RemoveWorkspaceFolder, [lspserver]),
    selectionRange: function(SelectionRange, [lspserver]),
    selectionExpand: function(SelectionExpand, [lspserver]),
    selectionShrink: function(SelectionShrink, [lspserver]),
    foldRange: function(FoldRange, [lspserver]),
    executeCommand: function(ExecuteCommand, [lspserver]),
    showCapabilities: function(ShowCapabilities, [lspserver])
  })

  return lspserver
enddef

# vim: shiftwidth=2 softtabstop=2
