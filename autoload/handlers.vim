vim9script

# Handlers for messages from the LSP server
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specificaiton.

var opt = {}
var util = {}
var diag = {}
var outline = {}
var textedit = {}
var symbol = {}
var codeaction = {}
var callhier = {}
var selection = {}
var signature = {}

if has('patch-8.2.4019')
  import './lspoptions.vim' as opt_import
  import './util.vim' as util_import
  import './diag.vim' as diag_import
  import './outline.vim' as outline_import
  import './textedit.vim' as textedit_import
  import './symbol.vim' as symbol_import
  import './codeaction.vim' as codeaction_import
  import './callhierarchy.vim' as callhierarchy_import
  import './selection.vim' as selection_import
  import './signature.vim' as signature_import

  opt.lspOptions = opt_import.lspOptions
  util.WarnMsg = util_import.WarnMsg
  util.ErrMsg = util_import.ErrMsg
  util.TraceLog = util_import.TraceLog
  util.LspUriToFile = util_import.LspUriToFile
  util.GetLineByteFromPos = util_import.GetLineByteFromPos
  diag.DiagNotification = diag_import.DiagNotification
  outline.UpdateOutlineWindow = outline_import.UpdateOutlineWindow
  textedit.ApplyTextEdits = textedit_import.ApplyTextEdits
  textedit.ApplyWorkspaceEdit = textedit_import.ApplyWorkspaceEdit
  symbol.ShowReferences = symbol_import.ShowReferences
  symbol.GotoSymbol = symbol_import.GotoSymbol
  codeaction.ApplyCodeAction = codeaction_import.ApplyCodeAction
  callhier.IncomingCalls = callhierarchy_import.IncomingCalls
  callhier.OutgoingCalls = callhierarchy_import.OutgoingCalls
  selection.SelectionStart = selection_import.SelectionStart
  signature.SignatureInit = signature_import.SignatureInit
  signature.SignatureDisplay = signature_import.SignatureDisplay
else
  import lspOptions from './lspoptions.vim'
  import {WarnMsg,
	ErrMsg,
	TraceLog,
	LspUriToFile,
	GetLineByteFromPos} from './util.vim'
  import DiagNotification from './diag.vim'
  import UpdateOutlineWindow from './outline.vim'
  import {ApplyTextEdits, ApplyWorkspaceEdit} from './textedit.vim'
  import {ShowReferences, GotoSymbol} from './symbol.vim'
  import ApplyCodeAction from './codeaction.vim'
  import {IncomingCalls, OutgoingCalls} from './callhierarchy.vim'
  import {SelectionStart} from './selection.vim'
  import {SignatureInit, SignatureDisplay} from './signature.vim'

  opt.lspOptions = lspOptions
  util.WarnMsg = WarnMsg
  util.ErrMsg = ErrMsg
  util.TraceLog = TraceLog
  util.LspUriToFile = LspUriToFile
  util.GetLineByteFromPos = GetLineByteFromPos
  diag.DiagNotification = DiagNotification
  outline.UpdateOutlineWindow = UpdateOutlineWindow
  textedit.ApplyTextEdits = ApplyTextEdits
  textedit.ApplyWorkspaceEdit = ApplyWorkspaceEdit
  symbol.ShowReferences = ShowReferences
  symbol.GotoSymbol = GotoSymbol
  codeaction.ApplyCodeAction = ApplyCodeAction
  callhier.IncomingCalls = IncomingCalls
  callhier.OutgoingCalls = OutgoingCalls
  selection.SelectionStart = SelectionStart
  signature.SignatureInit = SignatureInit
  signature.SignatureDisplay = SignatureDisplay
endif

# process the 'initialize' method reply from the LSP server
# Result: InitializeResult
def ProcessInitializeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->len() <= 0
    return
  endif

  var caps: dict<any> = reply.result.capabilities
  lspserver.caps = caps

  # TODO: Check all the buffers with filetype corresponding to this LSP server
  # and then setup the below mapping for those buffers.

  # initialize signature help
  signature.SignatureInit(lspserver)

  if opt.lspOptions.autoComplete && caps->has_key('completionProvider')
    var triggers = caps.completionProvider.triggerCharacters
    lspserver.completionTriggerChars = triggers
  endif

  if opt.lspOptions.autoHighlight && caps->has_key('documentHighlightProvider')
			      && caps.documentHighlightProvider
    # Highlight all the occurrences of the current keyword
    augroup LSPBufferAutocmds
      autocmd CursorMoved <buffer> call g:LspDocHighlightClear()
						| call g:LspDocHighlight()
    augroup END
  endif

  # send a "initialized" notification to server
  lspserver.sendInitializedNotif()
  lspserver.ready = true

  # if the outline window is opened, then request the symbols for the current
  # buffer
  if bufwinid('LSP-Outline') != -1
    lspserver.getDocSymbols(@%)
  endif
enddef

# process the 'textDocument/definition' / 'textDocument/declaration' /
# 'textDocument/typeDefinition' and 'textDocument/implementation' replies from
# the LSP server
# Result: Location | Location[] | LocationLink[] | null
def ProcessDefDeclReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var location: dict<any>
  if reply.result->type() == v:t_list
    if !reply.result->empty()
      location = reply.result[0]
    else
      location = {}
    endif
  else
    location = reply.result
  endif

  symbol.GotoSymbol(lspserver, location, req.method)
enddef

# process the 'textDocument/signatureHelp' reply from the LSP server
# Result: SignatureHelp | null
def ProcessSignaturehelpReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
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
    if item->has_key('kind')
      # namespace CompletionItemKind
      # map LSP kind to complete-item-kind
      d.kind = LspCompleteItemKindChar(item.kind)
    endif
    if item->has_key('detail')
      d.menu = item.detail
    endif
    if item->has_key('documentation')
      if item.documentation->type() == v:t_string && item.documentation != ''
	d.info = item.documentation
      elseif item.documentation->type() == v:t_dict
			&& item.documentation.value->type() == v:t_string
	d.info = item.documentation.value
      endif
    endif
    d.user_data = item
    completeItems->add(d)
  endfor

  if opt.lspOptions.autoComplete
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

    # Find the start column for the completion.  If any of the entries
    # returned by the LSP server has a starting position, then use that.
    var start_col: number = 0
    for item in items
      if item->has_key('textEdit')
	start_col = item.textEdit.range.start.character + 1
	break
      endif
    endfor

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
    lspserver.completePending = false
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
        util.ErrMsg('Error: Unsupported hover contents type (' .. reply.result.contents.kind .. ')')
        return
      endif
    elseif reply.result.contents->has_key('value')
      # MarkedString
      hoverText = reply.result.contents.value->split("\n")
    else
      util.ErrMsg('Error: Unsupported hover contents (' .. reply.result.contents .. ')')
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
    util.ErrMsg('Error: Unsupported hover contents (' .. reply.result.contents .. ')')
    return
  endif
  if opt.lspOptions.hoverInPreview
    silent! pedit HoverReply
    wincmd P
    setlocal buftype=nofile
    setlocal bufhidden=delete
    exe 'setlocal ft=' .. hoverKind
    deletebufline(bufnr(), 1, '$')
    append(0, hoverText)
    cursor(1, 1)
    wincmd p
  else
    hoverText->popup_atcursor({moved: 'word'})
  endif
enddef

# process the 'textDocument/references' reply from the LSP server
# Result: Location[] | null
def ProcessReferencesReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  symbol.ShowReferences(lspserver, reply.result)
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

# map the LSP symbol kind number to string
def LspSymbolKindToName(symkind: number): string
  var symbolMap: list<string> = ['', 'File', 'Module', 'Namespace', 'Package',
	'Class', 'Method', 'Property', 'Field', 'Constructor', 'Enum',
	'Interface', 'Function', 'Variable', 'Constant', 'String', 'Number',
	'Boolean', 'Array', 'Object', 'Key', 'Null', 'EnumMember', 'Struct',
	'Event', 'Operator', 'TypeParameter']
  if symkind > 26
    return ''
  endif
  return symbolMap[symkind]
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

  for symbol in symbolInfoTable
    fname = util.LspUriToFile(symbol.location.uri)
    symbolType = LspSymbolKindToName(symbol.kind)
    name = symbol.name
    if symbol->has_key('containerName')
      if symbol.containerName != ''
	name ..= ' [' .. symbol.containerName .. ']'
      endif
    endif
    r = symbol.location.range

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

  for symbol in docSymbolTable
    name = symbol.name
    symbolType = LspSymbolKindToName(symbol.kind)
    r = symbol.range
    if symbol->has_key('detail')
      symbolDetail = symbol.detail
    endif
    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    childSymbols = {}
    if symbol->has_key('children')
      s:ProcessDocSymbolTable(symbol.children, childSymbols, symbolLineTable)
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
    s:ProcessSymbolInfoTable(reply.result, symbolTypeTable, symbolLineTable)
  else
    # DocumentSymbol[]
    s:ProcessDocSymbolTable(reply.result, symbolTypeTable, symbolLineTable)
  endif

  # sort the symbols by line number
  symbolLineTable->sort((a, b) => a.range.start.line - b.range.start.line)
  outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
enddef

# process the 'textDocument/formatting' reply from the LSP server
# Result: TextEdit[] | null
def ProcessFormatReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # nothing to format
    return
  endif

  # result: TextEdit[]

  var fname: string = util.LspUriToFile(req.params.textDocument.uri)
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

# Reply: 'textDocument/rename'
# Result: Range | { range: Range, placeholder: string }
#	        | { defaultBehavior: boolean } | null
def ProcessRenameReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # nothing to rename
    return
  endif

  # result: WorkspaceEdit
  textedit.ApplyWorkspaceEdit(reply.result)
enddef

# process the 'textDocument/codeAction' reply from the LSP server
# Result: (Command | CodeAction)[] | null
def ProcessCodeActionReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  codeaction.ApplyCodeAction(lspserver, reply.result)
enddef

# Reply: 'textDocument/selectionRange'
# Result: SelectionRange[] | null
def ProcessSelectionRangeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  selection.SelectionStart(lspserver, reply.result)
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
    exe ':' .. (foldRange.startLine + 2) .. ',' .. end_lnum .. 'fold'
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

# Convert a file name <filename> (<dirname>) format.
# Make sure the popup does't occupy the entire screen by reducing the width.
def MakeMenuName(popupWidth: number, fname: string): string
  var filename: string = fname->fnamemodify(':t')
  var flen: number = filename->len()
  var dirname: string = fname->fnamemodify(':h')

  if fname->len() > popupWidth && flen < popupWidth
    # keep the full file name and reduce directory name length
    # keep some characters at the beginning and end (equally).
    # 6 spaces are used for "..." and " ()"
    var dirsz = (popupWidth - flen - 6) / 2
    dirname = dirname[: dirsz] .. '...' .. dirname[-dirsz : ]
  endif
  var str: string = filename
  if dirname != '.'
    str ..= ' (' .. dirname .. '/)'
  endif
  return str
enddef

# process the 'workspace/symbol' reply from the LSP server
# Result: SymbolInformation[] | null
def ProcessWorkspaceSymbolReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  var symbols: list<dict<any>> = []
  var symbolType: string
  var fileName: string
  var r: dict<dict<number>>
  var symName: string

  if reply.result->type() != v:t_list
    return
  endif

  for symbol in reply.result
    if !symbol->has_key('location')
      # ignore entries without location information
      continue
    endif

    # interface SymbolInformation
    fileName = util.LspUriToFile(symbol.location.uri)
    r = symbol.location.range

    symName = symbol.name
    if symbol->has_key('containerName') && symbol.containerName != ''
      symName = symbol.containerName .. '::' .. symName
    endif
    symName ..= ' [' .. LspSymbolKindToName(symbol.kind) .. ']'
    symName ..= ' ' .. s:MakeMenuName(
		lspserver.workspaceSymbolPopup->popup_getpos().core_width,
		fileName)

    symbols->add({name: symName,
			file: fileName,
			pos: r.start})
  endfor
  symbols->setwinvar(lspserver.workspaceSymbolPopup, 'LspSymbolTable')
  lspserver.workspaceSymbolPopup->popup_settext(
				symbols->copy()->mapnew('v:val.name'))
enddef

# process the 'textDocument/prepareCallHierarchy' reply from the LSP server
# Result: CallHierarchyItem[] | null
def ProcessPrepareCallHierarchy(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    if lspserver.callHierarchyType == 'incoming'
      util.WarnMsg('No incoming calls')
    else
      util.WarnMsg('No outgoing calls')
    endif
    return
  endif

  var choice: number = 1
  if reply.result->len() > 1
    var items: list<string> = ['Select a Call Hierarchy Item:']
    for i in range(reply.result->len())
      items->add(printf("%d. %s", i + 1, reply.result[i].name))
    endfor
    choice = inputlist(items)
    if choice < 1 || choice > items->len()
      return
    endif
  endif

  if lspserver.callHierarchyType == 'incoming'
    g:LspGetIncomingCalls(reply.result[choice - 1])
  else
    g:LspGetOutgoingCalls(reply.result[choice - 1])
  endif
enddef

# process the 'callHierarchy/incomingCalls' reply from the LSP server
# Result: CallHierarchyIncomingCall[] | null
def ProcessIncomingCalls(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  callhier.IncomingCalls(reply.result)
enddef

# process the 'callHierarchy/outgoingCalls' reply from the LSP server
# Result: CallHierarchyOutgoingCall[] | null
def ProcessOutgoingCalls(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  callhier.OutgoingCalls(reply.result)
enddef

# Process various reply messages from the LSP server
export def ProcessReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var lsp_reply_handlers: dict<func> =
    {
      'initialize': function('s:ProcessInitializeReply'),
      'textDocument/definition': function('s:ProcessDefDeclReply'),
      'textDocument/declaration': function('s:ProcessDefDeclReply'),
      'textDocument/typeDefinition': function('s:ProcessDefDeclReply'),
      'textDocument/implementation': function('s:ProcessDefDeclReply'),
      'textDocument/signatureHelp': function('s:ProcessSignaturehelpReply'),
      'textDocument/completion': function('s:ProcessCompletionReply'),
      'textDocument/hover': function('s:ProcessHoverReply'),
      'textDocument/references': function('s:ProcessReferencesReply'),
      'textDocument/documentHighlight': function('s:ProcessDocHighlightReply'),
      'textDocument/documentSymbol': function('s:ProcessDocSymbolReply'),
      'textDocument/formatting': function('s:ProcessFormatReply'),
      'textDocument/rangeFormatting': function('s:ProcessFormatReply'),
      'textDocument/rename': function('s:ProcessRenameReply'),
      'textDocument/codeAction': function('s:ProcessCodeActionReply'),
      'textDocument/selectionRange': function('s:ProcessSelectionRangeReply'),
      'textDocument/foldingRange': function('s:ProcessFoldingRangeReply'),
      'workspace/executeCommand': function('s:ProcessWorkspaceExecuteReply'),
      'workspace/symbol': function('s:ProcessWorkspaceSymbolReply'),
      'textDocument/prepareCallHierarchy': function('s:ProcessPrepareCallHierarchy'),
      'callHierarchy/incomingCalls': function('s:ProcessIncomingCalls'),
      'callHierarchy/outgoingCalls': function('s:ProcessOutgoingCalls')
    }

  if lsp_reply_handlers->has_key(req.method)
    lsp_reply_handlers[req.method](lspserver, req, reply)
  else
    util.ErrMsg("Error: Unsupported reply received from LSP server: " .. reply->string())
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

  :echomsg 'Lsp ' .. mtype .. reply.params.message
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

  util.TraceLog(false, '[' .. mtype .. ']: ' .. reply.params.message)
enddef

# process unsupported notification messages
def ProcessUnsupportedNotif(lspserver: dict<any>, reply: dict<any>)
  util.ErrMsg('Error: Unsupported notification message received from the LSP server (' .. lspserver.path .. '), message = ' .. reply->string())
enddef

# ignore unsupported notification message
def IgnoreNotif(lspserver: dict<any>, reply: dict<any>)
enddef

# process notification messages from the LSP server
export def ProcessNotif(lspserver: dict<any>, reply: dict<any>): void
  var lsp_notif_handlers: dict<func> =
    {
      'window/showMessage': function('s:ProcessShowMsgNotif'),
      'window/logMessage': function('s:ProcessLogMsgNotif'),
      'textDocument/publishDiagnostics': function('s:ProcessDiagNotif'),
      '$/progress': function('s:ProcessUnsupportedNotif'),
      'telemetry/event': function('s:ProcessUnsupportedNotif'),
      # Java language server sends the 'language/status' notification which is
      # not in the LSP specification
      'language/status': function('s:IgnoreNotif')
    }

  if lsp_notif_handlers->has_key(reply.method)
    lsp_notif_handlers[reply.method](lspserver, reply)
  else
    util.ErrMsg('Error: Unsupported notification received from LSP server ' .. reply->string())
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
    :echomsg "Workspace edit" .. workspaceEditParams.label
  endif
  textedit.ApplyWorkspaceEdit(workspaceEditParams.edit)
  # TODO: Need to return the proper result of the edit operation
  lspserver.sendResponse(request, {applied: true}, {})
enddef

def ProcessUnsupportedReq(lspserver: dict<any>, request: dict<any>)
  util.ErrMsg('Error: Unsupported request message received from the LSP server (' .. lspserver.path .. '), message = ' .. request->string())
enddef

# process a request message from the server
export def ProcessRequest(lspserver: dict<any>, request: dict<any>)
  var lspRequestHandlers: dict<func> =
    {
      'workspace/applyEdit': function('s:ProcessApplyEditReq'),
      'window/workDoneProgress/create': function('s:ProcessUnsupportedReq'),
      'client/registerCapability': function('s:ProcessUnsupportedReq'),
      'client/unregisterCapability': function('s:ProcessUnsupportedReq'),
      'workspace/workspaceFolders': function('s:ProcessUnsupportedReq'),
      'workspace/configuration': function('s:ProcessUnsupportedReq'),
      'workspace/codeLens/refresh': function('s:ProcessUnsupportedReq'),
      'workspace/semanticTokens/refresh': function('s:ProcessUnsupportedReq')
    }

  if lspRequestHandlers->has_key(request.method)
    lspRequestHandlers[request.method](lspserver, request)
  else
    util.ErrMsg('Error: Unsupported request message received from the LSP server (' .. lspserver.path .. '), message = ' .. request->string())
  endif
enddef

# process one or more LSP server messages
export def ProcessMessages(lspserver: dict<any>): void
  var idx: number
  var len: number
  var content: string
  var msg: dict<any>
  var req: dict<any>

  while lspserver.data->len() > 0
    idx = stridx(lspserver.data, 'Content-Length: ')
    if idx == -1
      return
    endif

    if stridx(lspserver.data, "\r\n", idx + 16) == -1
      # not enough data is received. Wait for more data to arrive
      return
    endif

    len = str2nr(lspserver.data[idx + 16 : ])
    if len == 0
      util.ErrMsg("Error(LSP): Invalid content length")
      # Discard the header
      lspserver.data = lspserver.data[idx + 16 :]
      return
    endif

    # Header and contents are separated by '\r\n\r\n'
    idx = stridx(lspserver.data, "\r\n\r\n", idx + 16)
    if idx == -1
      # content separator is not found. Wait for more data to arrive.
      return
    endif

    # skip the separator
    idx = idx + 4

    if lspserver.data->len() - idx < len
      # message is not fully received. Process the message after more data is
      # received
      return
    endif

    content = lspserver.data[idx : idx + len - 1]
    try
      msg = content->json_decode()
    catch
      util.ErrMsg("Error(LSP): Malformed content (" .. content .. ")")
      lspserver.data = lspserver.data[idx + len :]
      continue
    endtry

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
	  util.ErrMsg("Error(LSP): request " .. req.method .. " failed ("
							.. emsg .. ")")
	endif
      endif
    elseif msg->has_key('id') && msg->has_key('method')
      # request message from the server
      lspserver.processRequest(msg)
    elseif msg->has_key('method')
      # notification message from the server
      lspserver.processNotif(msg)
    else
      util.ErrMsg("Error(LSP): Unsupported message (" .. msg->string() .. ")")
    endif

    lspserver.data = lspserver.data[idx + len :]
  endwhile
enddef

# vim: shiftwidth=2 softtabstop=2
