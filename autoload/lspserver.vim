vim9script

# LSP server functions
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specificaiton.

import {ProcessReply,
	ProcessNotif,
	ProcessRequest,
	ProcessMessages} from './handlers.vim'
import {WarnMsg,
	ErrMsg,
	TraceLog,
	LspUriToFile,
	LspBufnrToUri,
	LspFileToUri} from './util.vim'

# LSP server standard output handler
def s:output_cb(lspserver: dict<any>, chan: channel, msg: string): void
  TraceLog(false, msg)
  lspserver.data = lspserver.data .. msg
  lspserver.processMessages()
enddef

# LSP server error output handler
def s:error_cb(lspserver: dict<any>, chan: channel, emsg: string,): void
  TraceLog(true, emsg)
enddef

# LSP server exit callback
def s:exit_cb(lspserver: dict<any>, job: job, status: number): void
  WarnMsg("LSP server exited with status " .. status)
  lspserver.job = v:none
  lspserver.running = false
  lspserver.requests = {}
enddef

# Start a LSP server
def s:startServer(lspserver: dict<any>): number
  if lspserver.running
    WarnMsg("LSP server for is already running")
    return 0
  endif

  var cmd = [lspserver.path]
  cmd->extend(lspserver.args)

  var opts = {in_mode: 'raw',
		out_mode: 'raw',
		err_mode: 'raw',
		noblock: 1,
		out_cb: function('s:output_cb', [lspserver]),
		err_cb: function('s:error_cb', [lspserver]),
		exit_cb: function('s:exit_cb', [lspserver])}

  lspserver.data = ''
  lspserver.caps = {}
  lspserver.nextID = 1
  lspserver.requests = {}
  lspserver.workspaceFolders = [getcwd()]

  var job = job_start(cmd, opts)
  if job->job_status() == 'fail'
    ErrMsg("Error: Failed to start LSP server " .. lspserver.path)
    return 1
  endif

  # wait for the LSP server to start
  sleep 10m

  lspserver.job = job
  lspserver.running = true

  lspserver.initServer()

  return 0
enddef

# Request: 'initialize'
# Param: InitializeParams
def s:initServer(lspserver: dict<any>)
  var req = lspserver.createRequest('initialize')

  # client capabilities (ClientCapabilities)
  var clientCaps: dict<any> = {
    workspace: {
      workspaceFolders: true,
      applyEdit: true,
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
  initparams.rootUri = LspFileToUri(curdir)
  initparams.workspaceFolders = {
	name: fnamemodify(curdir, ':t'),
	uri: LspFileToUri(curdir)
      }
  initparams.trace = 'off'
  initparams.capabilities = clientCaps
  req.params->extend(initparams)

  lspserver.sendMessage(req)
enddef

# Send a "initialized" LSP notification
# Params: InitializedParams
def s:sendInitializedNotif(lspserver: dict<any>)
  var notif: dict<any> = lspserver.createNotification('initialized')
  lspserver.sendMessage(notif)
enddef

# Request: shutdown
# Param: void
def s:shutdownServer(lspserver: dict<any>): void
  var req = lspserver.createRequest('shutdown')
  lspserver.sendMessage(req)
enddef

# Send a 'exit' notification to the LSP server
# Params: void
def s:exitServer(lspserver: dict<any>): void
  var notif: dict<any> = lspserver.createNotification('exit')
  lspserver.sendMessage(notif)
enddef

# Stop a LSP server
def s:stopServer(lspserver: dict<any>): number
  if !lspserver.running
    WarnMsg("LSP server is not running")
    return 0
  endif

  lspserver.shutdownServer()

  # Wait for the server to process the shutodwn request
  sleep 1

  lspserver.exitServer()

  lspserver.job->job_stop()
  lspserver.job = v:none
  lspserver.running = false
  lspserver.requests = {}
  return 0
enddef

# set the LSP server trace level using $/setTrace notification
def s:setTrace(lspserver: dict<any>, traceVal: string)
  var notif: dict<any> = lspserver.createNotification('$/setTrace')
  notif.params->extend({value: traceVal})
  lspserver.sendMessage(notif)
enddef

# Return the next id for a LSP server request message
def s:nextReqID(lspserver: dict<any>): number
  var id = lspserver.nextID
  lspserver.nextID = id + 1
  return id
enddef

# create a LSP server request message
def s:createRequest(lspserver: dict<any>, method: string): dict<any>
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
def s:createResponse(lspserver: dict<any>, req_id: number): dict<any>
  var resp = {}
  resp.jsonrpc = '2.0'
  resp.id = req_id

  return resp
enddef

# create a LSP server notification message
def s:createNotification(lspserver: dict<any>, notif: string): dict<any>
  var req = {}
  req.jsonrpc = '2.0'
  req.method = notif
  req.params = {}

  return req
enddef

# send a response message to the server
def s:sendResponse(lspserver: dict<any>, request: dict<any>, result: dict<any>, error: dict<any>)
  var resp: dict<any> = lspserver.createResponse(request.id)
  if result->type() != v:t_none
    resp->extend({result: result})
  else
    resp->extend({error: error})
  endif
  lspserver.sendMessage(resp)
enddef

# Send a request message to LSP server
def s:sendMessage(lspserver: dict<any>, content: dict<any>): void
  var payload_js: string = content->json_encode()
  var msg = "Content-Length: " .. payload_js->len() .. "\r\n\r\n"
  var ch = lspserver.job->job_getchannel()
  ch->ch_sendraw(msg)
  ch->ch_sendraw(payload_js)
enddef

# Send a LSP "textDocument/didOpen" notification
# Params: DidOpenTextDocumentParams
def s:textdocDidOpen(lspserver: dict<any>, bnr: number, ftype: string): void
  var notif: dict<any> = lspserver.createNotification('textDocument/didOpen')

  # interface DidOpenTextDocumentParams
  # interface TextDocumentItem
  var tdi = {}
  tdi.uri = LspBufnrToUri(bnr)
  tdi.languageId = ftype
  tdi.version = 1
  tdi.text = getbufline(bnr, 1, '$')->join("\n") .. "\n"
  notif.params->extend({textDocument: tdi})

  lspserver.sendMessage(notif)
enddef

# Send a LSP "textDocument/didClose" notification
def s:textdocDidClose(lspserver: dict<any>, bnr: number): void
  var notif: dict<any> = lspserver.createNotification('textDocument/didClose')

  # interface DidCloseTextDocumentParams
  #   interface TextDocumentIdentifier
  var tdid = {}
  tdid.uri = LspBufnrToUri(bnr)
  notif.params->extend({textDocument: tdid})

  lspserver.sendMessage(notif)
enddef

# Send a LSP "textDocument/didChange" notification
# Params: DidChangeTextDocumentParams
def s:textdocDidChange(lspserver: dict<any>, bnr: number, start: number,
			end: number, added: number,
			changes: list<dict<number>>): void
  var notif: dict<any> = lspserver.createNotification('textDocument/didChange')

  # interface DidChangeTextDocumentParams
  #   interface VersionedTextDocumentIdentifier
  var vtdid: dict<any> = {}
  vtdid.uri = LspBufnrToUri(bnr)
  # Use Vim 'changedtick' as the LSP document version number
  vtdid.version = bnr->getbufvar('changedtick')
  notif.params->extend({textDocument: vtdid})
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
  notif.params->extend({contentChanges: changeset})

  lspserver.sendMessage(notif)
enddef

# Return the current cursor position as a LSP position.
# LSP line and column numbers start from zero, whereas Vim line and column
# numbers start from one. The LSP column number is the character index in the
# line and not the byte index in the line.
def s:getLspPosition(): dict<number>
  var lnum: number = line('.') - 1
  var col: number = charcol('.') - 1
  return {line: lnum, character: col}
enddef

# Return the current file name and current cursor position as a LSP
# TextDocumentPositionParams structure
def s:getLspTextDocPosition(): dict<dict<any>>
  # interface TextDocumentIdentifier
  # interface Position
  return {textDocument: {uri: LspFileToUri(@%)},
	  position: s:getLspPosition()}
enddef

# Get a list of completion items.
# Request: "textDocument/completion"
# Param: CompletionParams
def s:getCompletion(lspserver: dict<any>): void
  # Check whether LSP server supports completion
  if !lspserver.caps->has_key('completionProvider')
    ErrMsg("Error: LSP server does not support completion")
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  var req = lspserver.createRequest('textDocument/completion')

  # interface CompletionParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())
  #   interface CompletionContext
  req.params->extend({context: {triggerKind: 1}})

  lspserver.sendMessage(req)
enddef

# push the current location on to the tag stack
def s:pushCursorToTagStack()
  settagstack(winnr(), {items: [
			 {
			   bufnr: bufnr(),
			   from: getpos('.'),
			   matchnr: 1,
			   tagname: expand('<cword>')
			 }]}, 'a')
enddef

# Request: "textDocument/definition"
# Param: DefinitionParams
def s:gotoDefinition(lspserver: dict<any>): void
  # Check whether LSP server supports jumping to a definition
  if !lspserver.caps->has_key('definitionProvider')
				|| !lspserver.caps.definitionProvider
    ErrMsg("Error: LSP server does not support jumping to a definition")
    return
  endif

  s:pushCursorToTagStack()
  var req = lspserver.createRequest('textDocument/definition')
  # interface DefinitionParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())
  lspserver.sendMessage(req)
enddef

# Request: "textDocument/declaration"
# Param: DeclarationParams
def s:gotoDeclaration(lspserver: dict<any>): void
  # Check whether LSP server supports jumping to a declaration
  if !lspserver.caps->has_key('declarationProvider')
			|| !lspserver.caps.declarationProvider
    ErrMsg("Error: LSP server does not support jumping to a declaration")
    return
  endif

  s:pushCursorToTagStack()
  var req = lspserver.createRequest('textDocument/declaration')

  # interface DeclarationParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())

  lspserver.sendMessage(req)
enddef

# Request: "textDocument/typeDefinition"
# Param: TypeDefinitionParams
def s:gotoTypeDef(lspserver: dict<any>): void
  # Check whether LSP server supports jumping to a type definition
  if !lspserver.caps->has_key('typeDefinitionProvider')
			|| !lspserver.caps.typeDefinitionProvider
    ErrMsg("Error: LSP server does not support jumping to a type definition")
    return
  endif

  s:pushCursorToTagStack()
  var req = lspserver.createRequest('textDocument/typeDefinition')

  # interface TypeDefinitionParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())

  lspserver.sendMessage(req)
enddef

# Request: "textDocument/implementation"
# Param: ImplementationParams
def s:gotoImplementation(lspserver: dict<any>): void
  # Check whether LSP server supports jumping to a implementation
  if !lspserver.caps->has_key('implementationProvider')
			|| !lspserver.caps.implementationProvider
    ErrMsg("Error: LSP server does not support jumping to an implementation")
    return
  endif

  s:pushCursorToTagStack()
  var req = lspserver.createRequest('textDocument/implementation')

  # interface ImplementationParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())

  lspserver.sendMessage(req)
enddef

# get symbol signature help.
# Request: "textDocument/signatureHelp"
# Param: SignatureHelpParams
def s:showSignature(lspserver: dict<any>): void
  # Check whether LSP server supports signature help
  if !lspserver.caps->has_key('signatureHelpProvider')
    ErrMsg("Error: LSP server does not support signature help")
    return
  endif

  var req = lspserver.createRequest('textDocument/signatureHelp')
  # interface SignatureHelpParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())

  lspserver.sendMessage(req)
enddef

def s:didSaveFile(lspserver: dict<any>, bnr: number): void
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
  notif.params->extend({textDocument: {uri: LspBufnrToUri(bnr)}})
  lspserver.sendMessage(notif)
enddef

# get the hover information
# Request: "textDocument/hover"
# Param: HoverParams
def s:hover(lspserver: dict<any>): void
  # Check whether LSP server supports getting hover information
  if !lspserver.caps->has_key('hoverProvider')
			|| !lspserver.caps.hoverProvider
    return
  endif

  var req = lspserver.createRequest('textDocument/hover')
  # interface HoverParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())
  lspserver.sendMessage(req)
enddef

# Request: "textDocument/references"
# Param: ReferenceParams
def s:showReferences(lspserver: dict<any>): void
  # Check whether LSP server supports getting reference information
  if !lspserver.caps->has_key('referencesProvider')
			|| !lspserver.caps.referencesProvider
    ErrMsg("Error: LSP server does not support showing references")
    return
  endif

  var req = lspserver.createRequest('textDocument/references')
  # interface ReferenceParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())
  req.params->extend({context: {includeDeclaration: true}})

  lspserver.sendMessage(req)
enddef

# Request: "textDocument/documentHighlight"
# Param: DocumentHighlightParams
def s:docHighlight(lspserver: dict<any>): void
  # Check whether LSP server supports getting highlight information
  if !lspserver.caps->has_key('documentHighlightProvider')
			|| !lspserver.caps.documentHighlightProvider
    ErrMsg("Error: LSP server does not support document highlight")
    return
  endif

  var req = lspserver.createRequest('textDocument/documentHighlight')
  # interface DocumentHighlightParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())
  lspserver.sendMessage(req)
enddef

# Request: "textDocument/documentSymbol"
# Param: DocumentSymbolParams
def s:getDocSymbols(lspserver: dict<any>, fname: string): void
  # Check whether LSP server supports getting document symbol information
  if !lspserver.caps->has_key('documentSymbolProvider')
			|| !lspserver.caps.documentSymbolProvider
    ErrMsg("Error: LSP server does not support getting list of symbols")
    return
  endif

  var req = lspserver.createRequest('textDocument/documentSymbol')
  # interface DocumentSymbolParams
  # interface TextDocumentIdentifier
  req.params->extend({textDocument: {uri: LspFileToUri(fname)}})
  lspserver.sendMessage(req)
enddef

# Request: "textDocument/formatting"
# Param: DocumentFormattingParams
# or
# Request: "textDocument/rangeFormatting"
# Param: DocumentRangeFormattingParams
def s:textDocFormat(lspserver: dict<any>, fname: string, rangeFormat: bool,
				start_lnum: number, end_lnum: number)
  # Check whether LSP server supports formatting documents
  if !lspserver.caps->has_key('documentFormattingProvider')
			|| !lspserver.caps.documentFormattingProvider
    ErrMsg("Error: LSP server does not support formatting documents")
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
  req.params->extend({textDocument: {uri: LspFileToUri(fname)}})
  var tabsz: number
  if &sts > 0
    tabsz = &sts
  elseif &sts < 0
    tabsz = &shiftwidth
  else
    tabsz = &tabstop
  endif
  # interface FormattingOptions
  var fmtopts: dict<any> = {
    tabSize: tabsz,
    insertSpaces: &expandtab ? true : false,
  }
  req.params->extend({options: fmtopts})
  if rangeFormat
    var r: dict<dict<number>> = {
	start: {line: start_lnum - 1, character: 0},
	end: {line: end_lnum, character: 0}}
    req.params->extend({range: r})
  endif

  lspserver.sendMessage(req)
enddef

# Request: "textDocument/rename"
# Param: RenameParams
def s:renameSymbol(lspserver: dict<any>, newName: string)
  # Check whether LSP server supports rename operation
  if !lspserver.caps->has_key('renameProvider')
			|| !lspserver.caps.renameProvider
    ErrMsg("Error: LSP server does not support rename operation")
    return
  endif

  var req = lspserver.createRequest('textDocument/rename')
  # interface RenameParams
  #   interface TextDocumentPositionParams
  req.params->extend(s:getLspTextDocPosition())
  req.params->extend({newName: newName})
  lspserver.sendMessage(req)
enddef

# Get the diagnostic from the LSP server for a particular line in a file
def s:getDiagByLine(lspserver: dict<any>, bnr: number, lnum: number): dict<any>
  if lspserver.diagsMap->has_key(bnr) &&
				lspserver.diagsMap[bnr]->has_key(lnum)
    return lspserver.diagsMap[bnr][lnum]
  endif
  return {}
enddef

# Request: "textDocument/codeAction"
# Param: CodeActionParams
def s:codeAction(lspserver: dict<any>, fname_arg: string)
  # Check whether LSP server supports code action operation
  if !lspserver.caps->has_key('codeActionProvider')
			|| !lspserver.caps.codeActionProvider
    ErrMsg("Error: LSP server does not support code action operation")
    return
  endif

  var req = lspserver.createRequest('textDocument/codeAction')

  # interface CodeActionParams
  var fname: string = fnamemodify(fname_arg, ':p')
  var bnr: number = fname_arg->bufnr()
  req.params->extend({textDocument: {uri: LspFileToUri(fname)}})
  var r: dict<dict<number>> = {
		  start: {line: line('.') - 1, character: charcol('.') - 1},
		  end: {line: line('.') - 1, character: charcol('.') - 1}}
  req.params->extend({range: r})
  var diag: list<dict<any>> = []
  var lnum = line('.')
  var diagInfo: dict<any> = lspserver.getDiagByLine(bnr, lnum)
  if !diagInfo->empty()
    diag->add(diagInfo)
  endif
  req.params->extend({context: {diagnostics: diag}})

  lspserver.sendMessage(req)
enddef

# List project-wide symbols matching query string
# Request: "workspace/symbol"
# Param: WorkspaceSymbolParams
def s:workspaceQuerySymbols(lspserver: dict<any>, query: string): bool
  # Check whether the LSP server supports listing workspace symbols
  if !lspserver.caps->has_key('workspaceSymbolProvider')
				|| !lspserver.caps.workspaceSymbolProvider
    ErrMsg("Error: LSP server does not support listing workspace symbols")
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
def s:addWorkspaceFolder(lspserver: dict<any>, dirName: string): void
  if !lspserver.caps->has_key('workspace')
	  || !lspserver.caps.workspace->has_key('workspaceFolders')
	  || !lspserver.caps.workspace.workspaceFolders->has_key('supported')
	  || !lspserver.caps.workspace.workspaceFolders.supported
      ErrMsg('Error: LSP server does not support workspace folders')
    return
  endif

  if lspserver.workspaceFolders->index(dirName) != -1
    ErrMsg('Error: ' .. dirName .. ' is already part of this workspace')
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
def s:removeWorkspaceFolder(lspserver: dict<any>, dirName: string): void
  if !lspserver.caps->has_key('workspace')
	  || !lspserver.caps.workspace->has_key('workspaceFolders')
	  || !lspserver.caps.workspace.workspaceFolders->has_key('supported')
	  || !lspserver.caps.workspace.workspaceFolders.supported
      ErrMsg('Error: LSP server does not support workspace folders')
    return
  endif

  var idx: number = lspserver.workspaceFolders->index(dirName)
  if idx == -1
    ErrMsg('Error: ' .. dirName .. ' is not currently part of this workspace')
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
def s:selectionRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports selection ranges
  if !lspserver.caps->has_key('selectionRangeProvider')
			|| !lspserver.caps.selectionRangeProvider
    ErrMsg("Error: LSP server does not support selection ranges")
    return
  endif

  var req = lspserver.createRequest('textDocument/selectionRange')
  # interface SelectionRangeParams
  # interface TextDocumentIdentifier
  req.params->extend({textDocument: {uri: LspFileToUri(fname)}})
  req.params->extend({positions: [s:getLspPosition()]})
  lspserver.sendMessage(req)
enddef

# fold the entire document
# Request: "textDocument/foldingRange"
# Param: FoldingRangeParams
def s:foldRange(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports fold ranges
  if !lspserver.caps->has_key('foldingRangeProvider')
			|| !lspserver.caps.foldingRangeProvider
    ErrMsg("Error: LSP server does not support folding")
    return
  endif

  var req = lspserver.createRequest('textDocument/foldingRange')
  # interface FoldingRangeParams
  # interface TextDocumentIdentifier
  req.params->extend({textDocument: {uri: LspFileToUri(fname)}})
  lspserver.sendMessage(req)
enddef

export def NewLspServer(path: string, args: list<string>): dict<any>
  var lspserver: dict<any> = {
    path: path,
    args: args,
    running: false,
    job: v:none,
    data: '',
    nextID: 1,
    caps: {},
    requests: {},
    diagsMap: {},
    completionTriggerChars: [],
    workspaceSymbolPopup: 0,
    workspaceSymbolQuery: ''
  }
  # Add the LSP server functions
  lspserver->extend({
    startServer: function('s:startServer', [lspserver]),
    initServer: function('s:initServer', [lspserver]),
    stopServer: function('s:stopServer', [lspserver]),
    shutdownServer: function('s:shutdownServer', [lspserver]),
    exitServer: function('s:exitServer', [lspserver]),
    setTrace: function('s:setTrace', [lspserver]),
    nextReqID: function('s:nextReqID', [lspserver]),
    createRequest: function('s:createRequest', [lspserver]),
    createResponse: function('s:createResponse', [lspserver]),
    createNotification: function('s:createNotification', [lspserver]),
    sendResponse: function('s:sendResponse', [lspserver]),
    sendMessage: function('s:sendMessage', [lspserver]),
    processReply: function('ProcessReply', [lspserver]),
    processNotif: function('ProcessNotif', [lspserver]),
    processRequest: function('ProcessRequest', [lspserver]),
    processMessages: function('ProcessMessages', [lspserver]),
    getDiagByLine: function('s:getDiagByLine', [lspserver]),
    textdocDidOpen: function('s:textdocDidOpen', [lspserver]),
    textdocDidClose: function('s:textdocDidClose', [lspserver]),
    textdocDidChange: function('s:textdocDidChange', [lspserver]),
    sendInitializedNotif: function('s:sendInitializedNotif', [lspserver]),
    getCompletion: function('s:getCompletion', [lspserver]),
    gotoDefinition: function('s:gotoDefinition', [lspserver]),
    gotoDeclaration: function('s:gotoDeclaration', [lspserver]),
    gotoTypeDef: function('s:gotoTypeDef', [lspserver]),
    gotoImplementation: function('s:gotoImplementation', [lspserver]),
    showSignature: function('s:showSignature', [lspserver]),
    didSaveFile: function('s:didSaveFile', [lspserver]),
    hover: function('s:hover', [lspserver]),
    showReferences: function('s:showReferences', [lspserver]),
    docHighlight: function('s:docHighlight', [lspserver]),
    getDocSymbols: function('s:getDocSymbols', [lspserver]),
    textDocFormat: function('s:textDocFormat', [lspserver]),
    renameSymbol: function('s:renameSymbol', [lspserver]),
    codeAction: function('s:codeAction', [lspserver]),
    workspaceQuery: function('s:workspaceQuerySymbols', [lspserver]),
    addWorkspaceFolder: function('s:addWorkspaceFolder', [lspserver]),
    removeWorkspaceFolder: function('s:removeWorkspaceFolder', [lspserver]),
    selectionRange: function('s:selectionRange', [lspserver]),
    foldRange: function('s:foldRange', [lspserver])
  })

  return lspserver
enddef

# vim: shiftwidth=2 softtabstop=2
