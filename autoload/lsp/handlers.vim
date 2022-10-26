vim9script

# Handlers for messages from the LSP server
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specification.

import './options.vim' as opt
import './util.vim'
import './diag.vim'
import './outline.vim'
import './textedit.vim'
import './symbol.vim'
import './codeaction.vim'
import './callhierarchy.vim' as callhier
import './signature.vim'

# process the 'initialize' method reply from the LSP server
# Result: InitializeResult
def ProcessInitializeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var caps: dict<any> = reply.result.capabilities
  lspserver.caps = caps

  if opt.lspOptions.autoComplete && caps->has_key('completionProvider')
    lspserver.completionTriggerChars = caps.completionProvider->get('triggerCharacters', [])
    lspserver.completionLazyDoc =
		lspserver.caps.completionProvider->has_key('resolveProvider')
		&& lspserver.caps.completionProvider.resolveProvider
  endif

  # send a "initialized" notification to server
  lspserver.sendInitializedNotif()
  lspserver.ready = true
  if exists('#User#LspServerReady' .. lspserver.name)
    exe $'doautocmd <nomodeline> User LspServerReady{lspserver.name}'
  endif

  # if the outline window is opened, then request the symbols for the current
  # buffer
  if bufwinid('LSP-Outline') != -1
    lspserver.getDocSymbols(@%)
  endif
enddef

# process the 'textDocument/signatureHelp' reply from the LSP server
# Result: SignatureHelp | null
def ProcessSignaturehelpReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif
  signature.SignatureDisplay(lspserver, reply.result)
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

# process the 'textDocument/completion' reply from the LSP server
# Result: CompletionItem[] | CompletionList | null
def ProcessCompletionReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var items: list<dict<any>>
  if reply.result->type() == v:t_list
    items = reply.result
  else
    items = reply.result.items
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
      if item->has_key('detail')
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

    if mode() != 'i' && mode() != 'R' && mode() != 'Rv'
      # If not in insert or replace mode, then don't start the completion
      return
    endif

    if completeItems->len() == 1
	&& matchstr(getline('.'), completeItems[0].word .. '\>') != ''
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

# process the 'completionItem/resolve' reply from the LSP server
# Result: CompletionItem
def ProcessResolveReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  # check if completion item is still selected
  var cInfo = complete_info()
  if cInfo->empty()
      || !cInfo.pum_visible
      || cInfo.selected == -1
      || cInfo.items[cInfo.selected].user_data.label != reply.result.label
    return
  endif

  var infoText: list<string>
  var infoKind: string

  if reply.result->has_key('detail')
    # Solve a issue where if a server send the detail field with "\n",
    # on the completion popup, everything will be joined with "^@"
    # (example: typescript-language-server)
    infoText->extend(split(reply.result.detail, "\n"))
  endif

  if reply.result->has_key('documentation')
    if !infoText->empty()
      infoText->extend(['- - -'])
    endif
    if reply.result.documentation->type() == v:t_dict
      # MarkupContent
      if reply.result.documentation.kind == 'plaintext'
        infoText->extend(reply.result.documentation.value->split("\n"))
        infoKind = 'text'
      elseif reply.result.documentation.kind == 'markdown'
        infoText->extend(reply.result.documentation.value->split("\n"))
        infoKind = 'markdown'
      else
        util.ErrMsg($'Error: Unsupported documentation type ({reply.result.documentation.kind})')
        return
      endif
    elseif reply.result.documentation->type() == v:t_string
      infoText->extend(reply.result.documentation->split("\n"))
    else
      util.ErrMsg($'Error: Unsupported documentation ({reply.result.documentation->string()})')
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
      || cInfo.items[cInfo.selected].user_data.label != reply.result.label
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

# process the 'textDocument/hover' reply from the LSP server
# Result: Hover | null
def ProcessHoverReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var hoverText: list<string>
  var hoverKind: string

  if reply.result.contents->type() == v:t_dict
    if reply.result.contents->has_key('kind')
      # MarkupContent
      if reply.result.contents.kind == 'plaintext'
        hoverText = reply.result.contents.value->split("\n")
        hoverKind = 'text'
      elseif reply.result.contents.kind == 'markdown'
        hoverText = reply.result.contents.value->split("\n")
        hoverKind = 'markdown'
      else
        util.ErrMsg($'Error: Unsupported hover contents type ({reply.result.contents.kind})')
        return
      endif
    elseif reply.result.contents->has_key('value')
      # MarkedString
      hoverText = reply.result.contents.value->split("\n")
    else
      util.ErrMsg($'Error: Unsupported hover contents ({reply.result.contents})')
      return
    endif
  elseif reply.result.contents->type() == v:t_list
    # interface MarkedString[]
    for e in reply.result.contents
      if e->type() == v:t_string
        hoverText->extend(e->split("\n"))
      else
        hoverText->extend(e.value->split("\n"))
      endif
    endfor
  elseif reply.result.contents->type() == v:t_string
    if reply.result.contents->empty()
      return
    endif
    hoverText->extend(reply.result.contents->split("\n"))
  else
    util.ErrMsg($'Error: Unsupported hover contents ({reply.result.contents})')
    return
  endif
  if opt.lspOptions.hoverInPreview
    silent! pedit HoverReply
    wincmd P
    setlocal buftype=nofile
    setlocal bufhidden=delete
    exe $'setlocal ft={hoverKind}'
    deletebufline(bufnr(), 1, '$')
    append(0, hoverText)
    cursor(1, 1)
    wincmd p
  else
    hoverText->popup_atcursor({moved: 'word'})
  endif
enddef

# process the 'textDocument/documentHighlight' reply from the LSP server
# Result: DocumentHighlight[] | null
def ProcessDocHighlightReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var fname: string = util.LspUriToFile(req.params.textDocument.uri)
  var bnr = fname->bufnr()

  for docHL in reply.result
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

# process SymbolInformation[]
def ProcessSymbolInfoTable(symbolInfoTable: list<dict<any>>,
				symbolTypeTable: dict<list<dict<any>>>,
				symbolLineTable: list<dict<any>>)
  var fname: string
  var symbolType: string
  var name: string
  var r: dict<dict<number>>
  var symInfo: dict<any>

  for syminfo in symbolInfoTable
    fname = util.LspUriToFile(syminfo.location.uri)
    symbolType = symbol.SymbolKindToName(syminfo.kind)
    name = syminfo.name
    if syminfo->has_key('containerName')
      if syminfo.containerName != ''
	name ..= $' [{syminfo.containerName}]'
      endif
    endif
    r = syminfo.location.range

    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    symInfo = {name: name, range: r}
    symbolTypeTable[symbolType]->add(symInfo)
    symbolLineTable->add(symInfo)
  endfor
enddef

# process DocumentSymbol[]
def ProcessDocSymbolTable(docSymbolTable: list<dict<any>>,
				symbolTypeTable: dict<list<dict<any>>>,
				symbolLineTable: list<dict<any>>)
  var symbolType: string
  var name: string
  var r: dict<dict<number>>
  var symInfo: dict<any>
  var symbolDetail: string
  var childSymbols: dict<list<dict<any>>>

  for syminfo in docSymbolTable
    name = syminfo.name
    symbolType = symbol.SymbolKindToName(syminfo.kind)
    r = syminfo.range
    if syminfo->has_key('detail')
      symbolDetail = syminfo.detail
    endif
    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    childSymbols = {}
    if syminfo->has_key('children')
      ProcessDocSymbolTable(syminfo.children, childSymbols, symbolLineTable)
    endif
    symInfo = {name: name, range: r, detail: symbolDetail,
						children: childSymbols}
    symbolTypeTable[symbolType]->add(symInfo)
    symbolLineTable->add(symInfo)
  endfor
enddef

# process the 'textDocument/documentSymbol' reply from the LSP server
# Open a symbols window and display the symbols as a tree
# Result: DocumentSymbol[] | SymbolInformation[] | null
def ProcessDocSymbolReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var fname: string
  var symbolTypeTable: dict<list<dict<any>>> = {}
  var symbolLineTable: list<dict<any>> = []

  if req.params.textDocument.uri != ''
    fname = util.LspUriToFile(req.params.textDocument.uri)
  endif

  if reply.result->empty()
    # No symbols defined for this file. Clear the outline window.
    outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
    return
  endif

  if reply.result[0]->has_key('location')
    # SymbolInformation[]
    ProcessSymbolInfoTable(reply.result, symbolTypeTable, symbolLineTable)
  else
    # DocumentSymbol[]
    ProcessDocSymbolTable(reply.result, symbolTypeTable, symbolLineTable)
  endif

  # sort the symbols by line number
  symbolLineTable->sort((a, b) => a.range.start.line - b.range.start.line)
  outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
enddef

# process the 'textDocument/codeAction' reply from the LSP server
# Result: (Command | CodeAction)[] | null
def ProcessCodeActionReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # no action can be performed
    util.WarnMsg('No code action is available')
    return
  endif

  codeaction.ApplyCodeAction(lspserver, reply.result)
enddef

# Reply: 'textDocument/foldingRange'
# Result: FoldingRange[] | null
def ProcessFoldingRangeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
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
def ProcessWorkspaceExecuteReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    return
  endif

  # Nothing to do for the reply
enddef

# Process various reply messages from the LSP server
export def ProcessReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var lsp_reply_handlers: dict<func> =
    {
      'initialize': ProcessInitializeReply,
      'textDocument/signatureHelp': ProcessSignaturehelpReply,
      'textDocument/completion': ProcessCompletionReply,
      'completionItem/resolve': ProcessResolveReply,
      'textDocument/hover': ProcessHoverReply,
      'textDocument/documentHighlight': ProcessDocHighlightReply,
      'textDocument/documentSymbol': ProcessDocSymbolReply,
      'textDocument/codeAction': ProcessCodeActionReply,
      'textDocument/foldingRange': ProcessFoldingRangeReply,
      'workspace/executeCommand': ProcessWorkspaceExecuteReply,
    }

  if lsp_reply_handlers->has_key(req.method)
    lsp_reply_handlers[req.method](lspserver, req, reply)
  else
    util.ErrMsg($'Error: Unsupported reply received from LSP server: {reply->string()} for request: {req->string()}')
  endif
enddef

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
def ProcessDiagNotif(lspserver: dict<any>, reply: dict<any>): void
  diag.DiagNotification(lspserver, reply.params.uri, reply.params.diagnostics)
enddef

# process a show notification message from the LSP server
# Notification: window/showMessage
# Param: ShowMessageParams
def ProcessShowMsgNotif(lspserver: dict<any>, reply: dict<any>)
  var msgType: list<string> = ['', 'Error: ', 'Warning: ', 'Info: ', 'Log: ']
  if reply.params.type == 4
    # ignore log messages from the LSP server (too chatty)
    # TODO: Add a configuration to control the message level that will be
    # displayed. Also store these messages and provide a command to display
    # them.
    return
  endif
  var mtype: string = 'Log: '
  if reply.params.type > 0 && reply.params.type < 5
    mtype = msgType[reply.params.type]
  endif

  :echomsg $'Lsp {mtype} {reply.params.message}'
enddef

# process a log notification message from the LSP server
# Notification: window/logMessage
# Param: LogMessageParams
def ProcessLogMsgNotif(lspserver: dict<any>, reply: dict<any>)
  var msgType: list<string> = ['', 'Error: ', 'Warning: ', 'Info: ', 'Log: ']
  var mtype: string = 'Log: '
  if reply.params.type > 0 && reply.params.type < 5
    mtype = msgType[reply.params.type]
  endif

  util.TraceLog(false, $'[{mtype}]: {reply.params.message}')
enddef

# process unsupported notification messages
def ProcessUnsupportedNotif(lspserver: dict<any>, reply: dict<any>)
  util.ErrMsg($'Error: Unsupported notification message received from the LSP server ({lspserver.path}), message = {reply->string()}')
enddef

# process log trace notification messages
def ProcessLogTraceNotif(lspserver: dict<any>, reply: dict<any>)
  :echomsg $'Log trace notification: {reply->string()}'
enddef

# per-filetype private map inside to record if ntf once or not
var ftypeNtfOnceMap: dict<bool> = {}
# process unsupported notification messages but only notify once
def ProcessUnsupportedNotifOnce(lspserver: dict<any>, reply: dict<any>)
  if !ftypeNtfOnceMap->get(&ft, v:false)
	ProcessUnsupportedNotif(lspserver, reply)
	ftypeNtfOnceMap->extend({[&ft]: v:true})
  endif
enddef

# ignore unsupported notification message
def IgnoreNotif(lspserver: dict<any>, reply: dict<any>)
enddef

# process notification messages from the LSP server
export def ProcessNotif(lspserver: dict<any>, reply: dict<any>): void
  var lsp_notif_handlers: dict<func> =
    {
      'window/showMessage': ProcessShowMsgNotif,
      'window/logMessage': ProcessLogMsgNotif,
      'textDocument/publishDiagnostics': ProcessDiagNotif,
      '$/progress': ProcessUnsupportedNotif,
      '$/logTrace': ProcessLogTraceNotif,
      'telemetry/event': ProcessUnsupportedNotifOnce,
      # Java language server sends the 'language/status' notification which is
      # not in the LSP specification
      'language/status': IgnoreNotif
    }

  if lsp_notif_handlers->has_key(reply.method)
    lsp_notif_handlers[reply.method](lspserver, reply)
  else
    util.ErrMsg($'Error: Unsupported notification received from LSP server {reply->string()}')
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
    :echomsg $'Workspace edit {workspaceEditParams.label}'
  endif
  textedit.ApplyWorkspaceEdit(workspaceEditParams.edit)
  # TODO: Need to return the proper result of the edit operation
  lspserver.sendResponse(request, {applied: true}, {})
enddef

# process the workspace/workspaceFolders LSP server request
# Request: "workspace/workspaceFolders"
# Param: none
def ProcessWorkspaceFoldersReq(lspserver: dict<any>, request: dict<any>)
  lspserver.sendResponse(request, {}, {})
enddef

# process the client/registerCapability LSP server request
# Request: "client/registerCapability"
# Param: RegistrationParams
def ProcessClientRegisterCap(lspserver: dict<any>, request: dict<any>)
  lspserver.sendResponse(request, {}, {})
enddef

# process the client/unregisterCapability LSP server request
# Request: "client/unregisterCapability"
# Param: UnregistrationParams
def ProcessClientUnregisterCap(lspserver: dict<any>, request: dict<any>)
  lspserver.sendResponse(request, {}, {})
enddef

def ProcessUnsupportedReq(lspserver: dict<any>, request: dict<any>)
  util.ErrMsg($'Error: Unsupported request message received from the LSP server ({lspserver.path}), message = {request->string()}')
enddef

# process a request message from the server
export def ProcessRequest(lspserver: dict<any>, request: dict<any>)
  var lspRequestHandlers: dict<func> =
    {
      'workspace/applyEdit': ProcessApplyEditReq,
      'workspace/workspaceFolders': ProcessWorkspaceFoldersReq,
      'window/workDoneProgress/create': ProcessUnsupportedReq,
      'client/registerCapability': ProcessClientRegisterCap,
      'client/unregisterCapability': ProcessClientUnregisterCap,
      'workspace/configuration': ProcessUnsupportedReq,
      'workspace/codeLens/refresh': ProcessUnsupportedReq,
      'workspace/semanticTokens/refresh': ProcessUnsupportedReq
    }

  if lspRequestHandlers->has_key(request.method)
    lspRequestHandlers[request.method](lspserver, request)
  else
    util.ErrMsg($'Error: Unsupported request message received from the LSP server ({lspserver.path}), message = {request->string()}')
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
	emsg ..= ', code = ' .. msg.error.code
	if msg.error->has_key('data')
	  emsg = emsg .. ', data = ' .. msg.error.data->string()
	endif
	util.ErrMsg($'Error(LSP): request {req.method} failed ({emsg})')
      endif
    endif
  elseif msg->has_key('id') && msg->has_key('method')
    # request message from the server
    lspserver.processRequest(msg)
  elseif msg->has_key('method')
    # notification message from the server
    lspserver.processNotif(msg)
  else
    util.ErrMsg($'Error(LSP): Unsupported message ({msg->string()})')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
