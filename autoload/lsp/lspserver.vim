vim9script

# LSP server functions
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specificaiton.

import './options.vim' as opt
import './handlers.vim'
import './util.vim'
import './diag.vim'
import './selection.vim'
import './symbol.vim'
import './textedit.vim'
import './hover.vim'
import './signature.vim'
import './codeaction.vim'
import './callhierarchy.vim' as callhier

# LSP server standard output handler
def Output_cb(lspserver: dict<any>, chan: channel, msg: any): void
  util.TraceLog(false, $'Received [{strftime("%m/%d/%y %T")}]: {msg->string()}')
  lspserver.data = msg
  lspserver.processMessages()
enddef

# LSP server error output handler
def Error_cb(lspserver: dict<any>, chan: channel, emsg: string,): void
  util.TraceLog(true, emsg)
enddef

# LSP server exit callback
def Exit_cb(lspserver: dict<any>, job: job, status: number): void
  util.WarnMsg($'LSP server exited with status {status}')
  lspserver.running = false
  lspserver.ready = false
  lspserver.requests = {}
enddef

# Start a LSP server
#
def StartServer(lspserver: dict<any>): number
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
  lspserver.workspaceFolders = [getcwd()]

  var job = job_start(cmd, opts)
  if job->job_status() == 'fail'
    util.ErrMsg($'Error: Failed to start LSP server {lspserver.path}')
    return 1
  endif

  # wait a little for the LSP server to start
  sleep 10m

  lspserver.job = job
  lspserver.running = true

  lspserver.initServer()

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

  if opt.lspOptions.autoComplete && caps->has_key('completionProvider')
    lspserver.completionTriggerChars = caps.completionProvider->get('triggerCharacters', [])
    lspserver.completionLazyDoc =
		lspserver.caps.completionProvider->get('resolveProvider', false)
  endif

  # send a "initialized" notification to server
  lspserver.sendInitializedNotif()
  lspserver.ready = true
  if exists($'#User#LspServerReady{lspserver.name}')
    exe $'doautocmd <nomodeline> User LspServerReady{lspserver.name}'
  endif

  # if the outline window is opened, then request the symbols for the current
  # buffer
  if bufwinid('LSP-Outline') != -1
    lspserver.getDocSymbols(@%)
  endif
enddef

# Request: 'initialize'
# Param: InitializeParams
def InitServer(lspserver: dict<any>)
  # client capabilities (ClientCapabilities)
  var clientCaps: dict<any> = {
    workspace: {
      workspaceFolders: true,
      applyEdit: true
    },
    textDocument: {
      callHierarchy: {
	dynamicRegistration: false
      },
      codeAction: {
	dynamicRegistration: false,
	codeActionLiteralSupport: {
	  codeActionKind: {
	    valueSet: ['', 'quickfix', 'refactor', 'refactor.extract',
			'refactor.inline', 'refactor.rewrite', 'source',
			'source.organizeImports']
	  }
	},
        isPreferredSupport: true,
	disabledSupport: true
      },
      codeLens: {
	dynamicRegistration: false
      },
      completion: {
	dynamicRegistration: false,
	completionItem: {
	  documentationFormat: ['plaintext', 'markdown'],
	  resolveSupport: {properties: ['detail', 'documentation']},
	  snippetSupport: opt.lspOptions.snippetSupport
	},
	completionItemKind: {valueSet: range(1, 25)}
      },
      documentSymbol: {
	dynamicRegistration: false,
	hierarchicalDocumentSymbolSupport: true,
	symbolKind: {valueSet: range(1, 25)}
      },
      hover: {
        contentFormat: ['plaintext', 'markdown']
      },
      foldingRange: {lineFoldingOnly: true},
      synchronization: {
	didSave: true
      }
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
  if !empty(lspserver.initializationOptions)
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

# Set the language server trace level using the '$/setTrace' notification.
# Supported values for "traceVal" are "off", "messages" and "verbose".
def SetTrace(lspserver: dict<any>, traceVal: string)
  # Notification: '$/setTrace'
  # Params: SetTraceParams
  var params = {value: traceVal}
  lspserver.sendNotification('$/setTrace', params)
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
  var ch = lspserver.job->job_getchannel()
  if ch_status(ch) != 'open'
    # LSP server has exited
    return
  endif
  ch->ch_sendexpr(content)
  if content->has_key('id')
    util.TraceLog(false, $'Sent [{strftime("%m/%d/%y %T")}]: {content->string()}')
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
def Rpc(lspserver: dict<any>, method: string, params: any): dict<any>
  var req = {}
  req.method = method
  req.params = {}
  req.params->extend(params)

  var ch = lspserver.job->job_getchannel()
  if ch_status(ch) != 'open'
    # LSP server has exited
    return {}
  endif

  util.TraceLog(false, $'Sent [{strftime("%m/%d/%y %T")}]: {req->string()}')

  # Do the synchronous RPC call
  var reply = ch->ch_evalexpr(req)

  util.TraceLog(false, $'Received [{strftime("%m/%d/%y %T")}]: {reply->string()}')

  if reply->has_key('result')
    # successful reply
    return reply
  endif

  if reply->has_key('error')
    # request failed
    var emsg: string = reply.error.message
    emsg ..= ', code = ' .. reply.error.code
    if reply.error->has_key('data')
      emsg ..= ', data = ' .. reply.error.data->string()
    endif
    util.ErrMsg($'Error(LSP): request {method} failed ({emsg})')
  endif

  return {}
enddef

# LSP server asynchronous RPC callback
def AsyncRpcCb(lspserver: dict<any>, method: string, RpcCb: func, chan: channel, reply: dict<any>)
  util.TraceLog(false, $'Received [{strftime("%m/%d/%y %T")}]: {reply->string()}')

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

  var ch = lspserver.job->job_getchannel()
  if ch_status(ch) != 'open'
    # LSP server has exited
    return -1
  endif

  util.TraceLog(false, $'Sent [{strftime("%m/%d/%y %T")}]: {req->string()}')

  # Do the asynchronous RPC call
  var Fn = function('AsyncRpcCb', [lspserver, method, Cbfunc])

  var reply: dict<any>
  if get(g:, 'LSPTest')
    # When running LSP tests, make this a synchronous RPC call
    reply = Rpc(lspserver, method, params)
    Fn(test_null_channel(), reply)
  else
    # Otherwise, make an asynchronous RPC call
    reply = ch->ch_sendexpr(req, {callback: Fn})
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

# Send a file/document opened notification to the language server.
def TextdocDidOpen(lspserver: dict<any>, bnr: number, ftype: string): void
  # Notification: 'textDocument/didOpen'
  # Params: DidOpenTextDocumentParams
  var tdi = {}
  tdi.uri = util.LspBufnrToUri(bnr)
  tdi.languageId = ftype
  tdi.version = 1
  tdi.text = getbufline(bnr, 1, '$')->join("\n") .. "\n"
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

  changeset->add({text: getbufline(bnr, 1, '$')->join("\n") .. "\n"})
  var params = {textDocument: vtdid, contentChanges: changeset}
  lspserver.sendNotification('textDocument/didChange', params)
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

# Map LSP complete item kind to a character
def LspCompleteItemKindChar(kind: number): string
  var kindMap: list<string> = ['',
		't', # Text
		'm', # Method
		'f', # Function
		'C', # Constructor
		'F', # Field
		'v', # Variable
		'c', # Class
		'i', # Interface
		'M', # Module
		'p', # Property
		'u', # Unit
		'V', # Value
		'e', # Enum
		'k', # Keyword
		'S', # Snippet
		'C', # Color
		'f', # File
		'r', # Reference
		'F', # Folder
		'E', # EnumMember
		'd', # Contant
		's', # Struct
		'E', # Event
		'o', # Operator
		'T'  # TypeParameter
	]
  if kind > 25
    return ''
  endif
  return kindMap[kind]
enddef

# Remove all the snippet placeholders from 'str' and return the value.
# Based on a similar function in the vim-lsp plugin.
def MakeValidWord(str_arg: string): string
  var str = substitute(str_arg, '\$[0-9]\+\|\${\%(\\.\|[^}]\)\+}', '', 'g')
  str = substitute(str, '\\\(.\)', '\1', 'g')
  var valid = matchstr(str, '^[^"'' (<{\[\t\r\n]\+')
  if empty(valid)
    return str
  endif
  if valid =~# ':$'
    return valid[: -2]
  endif
  return valid
enddef

# process the 'textDocument/completion' reply from the LSP server
# Result: CompletionItem[] | CompletionList | null
def CompletionReply(lspserver: dict<any>, cItems: any)
  if cItems->empty()
    return
  endif

  var items: list<dict<any>>
  if cItems->type() == v:t_list
    items = cItems
  else
    items = cItems.items
  endif

  var completeItems: list<dict<any>> = []
  for item in items
    var d: dict<any> = {}
    if item->has_key('textEdit') && item.textEdit->has_key('newText')
      d.word = item.textEdit.newText
    elseif item->has_key('insertText')
      d.word = item.insertText
    else
      d.word = item.label
    endif
    if item->get('insertTextFormat', 1) == 2
      # snippet completion.  Needs a snippet plugin to expand the snippet.
      # Remove all the snippet placeholders
      d.word = MakeValidWord(d.word)
    endif
    d.abbr = item.label
    d.dup = 1
    if item->has_key('kind')
      # namespace CompletionItemKind
      # map LSP kind to complete-item-kind
      d.kind = LspCompleteItemKindChar(item.kind)
    endif
    if lspserver.completionLazyDoc
      d.info = 'Lazy doc'
    else
      if item->has_key('detail') && item.detail != ''
        # Solve a issue where if a server send a detail field
        # with a "\n", on the menu will be everything joined with
        # a "^@" separating it. (example: clangd)
        d.menu = item.detail->split("\n")[0]
      endif
      if item->has_key('documentation')
        if item.documentation->type() == v:t_string && item.documentation != ''
          d.info = item.documentation
        elseif item.documentation->type() == v:t_dict
            && item.documentation.value->type() == v:t_string
          d.info = item.documentation.value
        endif
      endif
    endif
    d.user_data = item
    completeItems->add(d)
  endfor

  if opt.lspOptions.autoComplete && !lspserver.omniCompletePending
    if completeItems->empty()
      # no matches
      return
    endif

    var m = mode()
    if m != 'i' && m != 'R' && m != 'Rv'
      # If not in insert or replace mode, then don't start the completion
      return
    endif

    if completeItems->len() == 1
	&& getline('.')->matchstr(completeItems[0].word .. '\>') != ''
      # only one complete match. No need to show the completion popup
      return
    endif

    var start_col: number = 0

    # FIXME: The following doesn't work with typescript as one of the
    # completion item has a start column that is before the special character.
    # For example, when completing the methods for "str.", the dot is removed.
    #
    # # Find the start column for the completion.  If any of the entries
    # # returned by the LSP server has a starting position, then use that.
    # for item in items
    #   if item->has_key('textEdit')
    #     start_col = item.textEdit.range.start.character + 1
    #     break
    #   endif
    # endfor

    # LSP server didn't return a starting position for completion, search
    # backwards from the current cursor position for a non-keyword character.
    if start_col == 0
      var line: string = getline('.')
      var start = col('.') - 1
      while start > 0 && line[start - 1] =~ '\k'
	start -= 1
      endwhile
      start_col = start + 1
    endif

    complete(start_col, completeItems)
  else
    lspserver.completeItems = completeItems
    lspserver.omniCompletePending = false
  endif
enddef

# Get a list of completion items.
# Request: "textDocument/completion"
# Param: CompletionParams
def GetCompletion(lspserver: dict<any>, triggerKind_arg: number, triggerChar: string): void
  # Check whether LSP server supports completion
  if !lspserver.caps->has_key('completionProvider')
    util.ErrMsg("Error: LSP server does not support completion")
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  # interface CompletionParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition()
  #   interface CompletionContext
  params.context = {triggerKind: triggerKind_arg, triggerCharacter: triggerChar}

  lspserver.rpc_a('textDocument/completion', params, CompletionReply)
enddef

# process the 'completionItem/resolve' reply from the LSP server
# Result: CompletionItem
def CompletionResolveReply(lspserver: dict<any>, cItem: dict<any>)
  if cItem->empty()
    return
  endif

  # check if completion item is still selected
  var cInfo = complete_info()
  if cInfo->empty()
      || !cInfo.pum_visible
      || cInfo.selected == -1
      || cInfo.items[cInfo.selected].user_data.label != cItem.label
    return
  endif

  var infoText: list<string>
  var infoKind: string

  if cItem->has_key('detail')
    # Solve a issue where if a server send the detail field with "\n",
    # on the completion popup, everything will be joined with "^@"
    # (example: typescript-language-server)
    infoText->extend(cItem.detail->split("\n"))
  endif

  if cItem->has_key('documentation')
    if !infoText->empty()
      infoText->extend(['- - -'])
    endif
    if cItem.documentation->type() == v:t_dict
      # MarkupContent
      if cItem.documentation.kind == 'plaintext'
        infoText->extend(cItem.documentation.value->split("\n"))
        infoKind = 'text'
      elseif cItem.documentation.kind == 'markdown'
        infoText->extend(cItem.documentation.value->split("\n"))
        infoKind = 'markdown'
      else
        util.ErrMsg($'Error: Unsupported documentation type ({cItem.documentation.kind})')
        return
      endif
    elseif cItem.documentation->type() == v:t_string
      infoText->extend(cItem.documentation->split("\n"))
    else
      util.ErrMsg($'Error: Unsupported documentation ({cItem.documentation->string()})')
      return
    endif
  endif

  if infoText->empty()
    return
  endif

  # check if completion item is changed in meantime
  cInfo = complete_info()
  if cInfo->empty()
      || !cInfo.pum_visible
      || cInfo.selected == -1
      || cInfo.items[cInfo.selected].user_data.label != cItem.label
    return
  endif

  var id = popup_findinfo()
  if id > 0
    var bufnr = id->winbufnr()
    infoKind->setbufvar(bufnr, '&ft')
    if infoKind == 'markdown'
      3->setwinvar(id, '&conceallevel')
    else
      0->setwinvar(id, '&conceallevel')
    endif
    id->popup_settext(infoText)
    id->popup_show()
  endif
enddef

# Get lazy properties for a completion item.
# Request: "completionItem/resolve"
# Param: CompletionItem
def ResolveCompletion(lspserver: dict<any>, item: dict<any>): void
  # Check whether LSP server supports completion item resolve
  if !lspserver.caps->has_key('completionProvider')
      || !lspserver.caps.completionProvider->get('resolveProvider', false)
    util.ErrMsg("Error: LSP server does not support completion item resolve")
    return
  endif

  # interface CompletionItem
  var params = item

  lspserver.rpc_a('completionItem/resolve', params, CompletionResolveReply)
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
  var reply = lspserver.rpc(msg, GetLspTextDocPosition())
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
  if !lspserver.caps->has_key('definitionProvider')
	|| (lspserver.caps.definitionProvider->type() == v:t_bool
	    && !lspserver.caps.definitionProvider)
    util.ErrMsg("Error: Jumping to a symbol definition is not supported")
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
  if !lspserver.caps->has_key('declarationProvider')
	|| (lspserver.caps.declarationProvider->type() == v:t_bool
	    && !lspserver.caps.declarationProvider)
    util.ErrMsg("Error: Jumping to a symbol declaration is not supported")
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
  if !lspserver.caps->has_key('typeDefinitionProvider')
	|| (lspserver.caps.typeDefinitionProvider->type() == v:t_bool
	    && !lspserver.caps.typeDefinitionProvider)
    util.ErrMsg("Error: Jumping to a symbol type definition is not supported")
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
  if !lspserver.caps->has_key('implementationProvider')
	|| (lspserver.caps.implementationProvider->type() == v:t_bool
	    && !lspserver.caps.implementationProvider)
    util.ErrMsg("Error: Jumping to a symbol implementation is not supported")
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
  if !lspserver.caps->has_key('signatureHelpProvider')
    util.ErrMsg("Error: LSP server does not support signature help")
    return
  endif

  # interface SignatureHelpParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition()
  lspserver.rpc_a('textDocument/signatureHelp', params,
			signature.SignatureHelp)
enddef

# Send a file/document saved notification to the language server
def DidSaveFile(lspserver: dict<any>, bnr: number): void
  # Check whether the LSP server supports the didSave notification
  if !lspserver.caps->has_key('textDocumentSync')
	|| !lspserver.caps.textDocumentSync->has_key('save')
	|| (lspserver.caps.textDocumentSync.save->type() == v:t_bool
	     && !lspserver.caps.textDocumentSync.save)
    # LSP server doesn't support text document synchronization
    return
  endif

  # Notification: 'textDocument/didSave'
  # Params: DidSaveTextDocumentParams
  var params = {textDocument: {uri: util.LspBufnrToUri(bnr)}}
  lspserver.sendNotification('textDocument/didSave', params)
enddef

# get the hover information
# Request: "textDocument/hover"
# Param: HoverParams
def ShowHoverInfo(lspserver: dict<any>): void
  # Check whether LSP server supports getting hover information.
  # caps->hoverProvider can be a "boolean" or "HoverOptions"
  if !lspserver.caps->has_key('hoverProvider')
	|| (lspserver.caps.hoverProvider->type() == v:t_bool
	    && !lspserver.caps.hoverProvider)
    return
  endif

  # interface HoverParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition()
  lspserver.rpc_a('textDocument/hover', params, hover.HoverReply)
enddef

# Request: "textDocument/references"
# Param: ReferenceParams
def ShowReferences(lspserver: dict<any>, peek: bool): void
  # Check whether LSP server supports getting reference information
  if !lspserver.caps->has_key('referencesProvider')
	|| (lspserver.caps.referencesProvider->type() == v:t_bool
	    && !lspserver.caps.referencesProvider)
    util.ErrMsg("Error: LSP server does not support showing references")
    return
  endif

  # interface ReferenceParams
  #   interface TextDocumentPositionParams
  var param: dict<any>
  param = GetLspTextDocPosition()
  param.context = {includeDeclaration: true}
  var reply = lspserver.rpc('textDocument/references', param)

  # Result: Location[] | null
  if reply->empty()
    return
  endif

  if reply.result->empty()
    util.WarnMsg('Error: No references found')
    return
  endif

  symbol.ShowReferences(lspserver, reply.result, peek)
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
  if !lspserver.caps->has_key('documentHighlightProvider')
	|| (lspserver.caps.documentHighlightProvider->type() == v:t_bool
	    && !lspserver.caps.documentHighlightProvider)
    util.ErrMsg("Error: LSP server does not support document highlight")
    return
  endif

  # interface DocumentHighlightParams
  #   interface TextDocumentPositionParams
  var params = GetLspTextDocPosition()
  lspserver.rpc_a('textDocument/documentHighlight', params,
			function('DocHighlightReply', [bufnr()]))
enddef

# Request: "textDocument/documentSymbol"
# Param: DocumentSymbolParams
def GetDocSymbols(lspserver: dict<any>, fname: string): void
  # Check whether LSP server supports getting document symbol information
  if !lspserver.caps->has_key('documentSymbolProvider')
	|| (lspserver.caps.documentSymbolProvider->type() == v:t_bool
	    && !lspserver.caps.documentSymbolProvider)
    util.ErrMsg("Error: LSP server does not support getting list of symbols")
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
  if !lspserver.caps->has_key('documentFormattingProvider')
	|| (lspserver.caps.documentFormattingProvider->type() == v:t_bool
	    && !lspserver.caps.documentFormattingProvider)
    util.ErrMsg("Error: LSP server does not support formatting documents")
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
	end: {line: end_lnum - 1, character: 99999}}
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
  param = GetLspTextDocPosition()
  var reply = lspserver.rpc('textDocument/prepareCallHierarchy', param)
  if reply->empty() || reply.result->empty()
    return {}
  endif

  # Result: CallHierarchyItem[] | null
  var choice: number = 1
  if reply.result->len() > 1
    var items: list<string> = ['Select a Call Hierarchy Item:']
    for i in range(reply.result->len())
      items->add(printf("%d. %s", i + 1, reply.result[i].name))
    endfor
    choice = inputlist(items)
    if choice < 1 || choice > items->len()
      return {}
    endif
  endif

  return reply.result[choice - 1]
enddef

# Request: "callHierarchy/incomingCalls"
def IncomingCalls(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports call hierarchy
  if !lspserver.caps->has_key('callHierarchyProvider')
	|| (lspserver.caps.callHierarchyProvider->type() == v:t_bool
	    && !lspserver.caps.callHierarchyProvider)
    util.ErrMsg("Error: LSP server does not support call hierarchy")
    return
  endif

  var reply = PrepareCallHierarchy(lspserver)
  if reply->empty()
    util.WarnMsg('No incoming calls')
    return
  endif

  # Request: "callHierarchy/incomingCalls"
  # Param: CallHierarchyIncomingCallsParams
  var param = {}
  param.item = reply
  reply = lspserver.rpc('callHierarchy/incomingCalls', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg('No incoming calls')
    return
  endif

  callhier.IncomingCalls(reply.result)
enddef

# Request: "callHierarchy/outgoingCalls"
def OutgoingCalls(lspserver: dict<any>, fname: string)
  # Check whether LSP server supports call hierarchy
  if !lspserver.caps->has_key('callHierarchyProvider')
	|| (lspserver.caps.callHierarchyProvider->type() == v:t_bool
	    && !lspserver.caps.callHierarchyProvider)
    util.ErrMsg("Error: LSP server does not support call hierarchy")
    return
  endif

  var reply = PrepareCallHierarchy(lspserver)
  if reply->empty()
    util.WarnMsg('No outgoing calls')
    return
  endif

  # Request: "callHierarchy/outgoingCalls"
  # Param: CallHierarchyOutgoingCallsParams
  var param = {}
  param.item = reply
  reply = lspserver.rpc('callHierarchy/outgoingCalls', param)
  if reply->empty() || reply.result->empty()
    util.WarnMsg('No outgoing calls')
    return
  endif

  callhier.OutgoingCalls(reply.result)
enddef

# Request: "textDocument/rename"
# Param: RenameParams
def RenameSymbol(lspserver: dict<any>, newName: string)
  # Check whether LSP server supports rename operation
  if !lspserver.caps->has_key('renameProvider')
	|| (lspserver.caps.renameProvider->type() == v:t_bool
	    && !lspserver.caps.renameProvider)
    util.ErrMsg("Error: LSP server does not support rename operation")
    return
  endif

  # interface RenameParams
  #   interface TextDocumentPositionParams
  var param: dict<any> = {}
  param = GetLspTextDocPosition()
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
def CodeAction(lspserver: dict<any>, fname_arg: string)
  # Check whether LSP server supports code action operation
  if !lspserver.caps->has_key('codeActionProvider')
	|| (lspserver.caps.codeActionProvider->type() == v:t_bool
	     && !lspserver.caps.codeActionProvider)
    util.ErrMsg("Error: LSP server does not support code action operation")
    return
  endif

  # interface CodeActionParams
  var params: dict<any> = {}
  var fname: string = fnamemodify(fname_arg, ':p')
  var bnr: number = fname_arg->bufnr()
  var r: dict<dict<number>> = {
		  start: {line: line('.') - 1, character: charcol('.') - 1},
		  end: {line: line('.') - 1, character: charcol('.') - 1}}
  params->extend({textDocument: {uri: util.LspFileToUri(fname)}, range: r})
  var d: list<dict<any>> = []
  var lnum = line('.')
  var diagInfo: dict<any> = diag.GetDiagByLine(lspserver, bnr, lnum)
  if !diagInfo->empty()
    d->add(diagInfo)
  endif
  params->extend({context: {diagnostics: d, triggerKind: 1}})

  var reply = lspserver.rpc('textDocument/codeAction', params)

  # Result: (Command | CodeAction)[] | null
  if reply->empty() || reply.result->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  codeaction.ApplyCodeAction(lspserver, reply.result)
enddef

# List project-wide symbols matching query string
# Request: "workspace/symbol"
# Param: WorkspaceSymbolParams
def WorkspaceQuerySymbols(lspserver: dict<any>, query: string)
  # Check whether the LSP server supports listing workspace symbols
  if !lspserver.caps->has_key('workspaceSymbolProvider')
	|| (lspserver.caps.workspaceSymbolProvider->type() == v:t_bool
	     && !lspserver.caps.workspaceSymbolProvider)
    util.ErrMsg("Error: LSP server does not support listing workspace symbols")
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
  if !lspserver.caps->has_key('selectionRangeProvider')
	|| (lspserver.caps.selectionRangeProvider->type() == v:t_bool
	     && !lspserver.caps.selectionRangeProvider)
    util.ErrMsg("Error: LSP server does not support selection ranges")
    return
  endif

  # clear the previous selection reply
  lspserver.selection = {}

  # interface SelectionRangeParams
  # interface TextDocumentIdentifier
  var param = {}
  param.textDocument = {}
  param.textDocument.uri = util.LspFileToUri(fname)
  param.positions = [GetLspPosition()]
  var reply = lspserver.rpc('textDocument/selectionRange', param)

  if reply->empty() || reply.result->empty()
    return
  endif

  selection.SelectionStart(lspserver, reply.result)
enddef

# Expand the previous selection or start a new one
def SelectionExpand(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.caps->has_key('selectionRangeProvider')
	|| (lspserver.caps.selectionRangeProvider->type() == v:t_bool
	     && !lspserver.caps.selectionRangeProvider)
    util.ErrMsg("Error: LSP server does not support selection ranges")
    return
  endif

  selection.SelectionModify(lspserver, true)
enddef

# Shrink the previous selection or start a new one
def SelectionShrink(lspserver: dict<any>)
  # Check whether LSP server supports selection ranges
  if !lspserver.caps->has_key('selectionRangeProvider')
	|| (lspserver.caps.selectionRangeProvider->type() == v:t_bool
	     && !lspserver.caps.selectionRangeProvider)
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
	|| (lspserver.caps.foldingRangeProvider->type() == v:t_bool
	     && !lspserver.caps.foldingRangeProvider)
    util.ErrMsg("Error: LSP server does not support folding")
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
  echo $"Capabilities of '{lspserver.path}' LSP server:"
  for k in lspserver.caps->keys()->sort()
    echo $'{k}: {lspserver.caps[k]->string()}'
  endfor
enddef

# Send a 'textDocument/definition' request to the LSP server to get the
# location where the symbol under the cursor is defined and return a list of
# Dicts in a format accepted by the 'tagfunc' option.
# Returns null if the LSP server doesn't support getting the location of a
# symbol definition or the symbol is not defined.
def TagFunc(lspserver: dict<any>, pat: string, flags: string, info: dict<any>): any
  # Check whether LSP server supports getting the location of a definition
  if !lspserver.caps->has_key('definitionProvider')
	|| (lspserver.caps.definitionProvider->type() == v:t_bool
	    && !lspserver.caps.definitionProvider)
    return null
  endif

  # interface DefinitionParams
  #   interface TextDocumentPositionParams
  var reply = lspserver.rpc('textDocument/definition', GetLspTextDocPosition())
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

export def NewLspServer(path: string, args: list<string>, isSync: bool, initializationOptions: any): dict<any>
  var lspserver: dict<any> = {
    path: path,
    args: args,
    syncInit: isSync,
    initializationOptions: initializationOptions,
    running: false,
    ready: false,
    job: v:none,
    data: '',
    nextID: 1,
    caps: {},
    requests: {},
    omniCompletePending: false,
    completionTriggerChars: [],
    signaturePopup: -1,
    diagsMap: {},
    workspaceSymbolPopup: -1,
    workspaceSymbolQuery: '',
    peekSymbolPopup: -1,
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
    getDiagByLine: function(diag.GetDiagByLine, [lspserver]),
    textdocDidOpen: function(TextdocDidOpen, [lspserver]),
    textdocDidClose: function(TextdocDidClose, [lspserver]),
    textdocDidChange: function(TextdocDidChange, [lspserver]),
    sendInitializedNotif: function(SendInitializedNotif, [lspserver]),
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

# vim: tabstop=8 shiftwidth=2 softtabstop=2
