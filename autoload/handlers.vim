vim9script

# Handlers for messages from the LSP server
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specificaiton.

import lspOptions from './lspoptions.vim'
import {WarnMsg,
	ErrMsg,
	TraceLog,
	LspUriToFile,
	GetLineByteFromPos} from './util.vim'
import {LspDiagsUpdated} from './buf.vim'

# process the 'initialize' method reply from the LSP server
# Result: InitializeResult
def s:processInitializeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->len() <= 0
    return
  endif

  var caps: dict<any> = reply.result.capabilities
  lspserver.caps = caps

  # TODO: Check all the buffers with filetype corresponding to this LSP server
  # and then setup the below mapping for those buffers.

  # map characters that trigger signature help
  if lspOptions.showSignature && caps->has_key('signatureHelpProvider')
    var triggers = caps.signatureHelpProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch .. "<C-R>=lsp#showSignature()<CR>"
    endfor
  endif

  if lspOptions.autoComplete && caps->has_key('completionProvider')
    var triggers = caps.completionProvider.triggerCharacters
    lspserver.completionTriggerChars = triggers
  endif

  if lspOptions.autoHighlight && caps->has_key('documentHighlightProvider')
			      && caps.documentHighlightProvider
    # Highlight all the occurrences of the current keyword
    augroup LSPBufferAutocmds
      autocmd CursorMoved <buffer> call lsp#docHighlightClear()
						| call lsp#docHighlight()
    augroup END
  endif

  # send a "initialized" notification to server
  lspserver.sendInitializedNotif()

  # if the outline window is opened, then request the symbols for the current
  # buffer
  lspserver.getDocSymbols(@%)
enddef

# process the 'textDocument/definition' / 'textDocument/declaration' /
# 'textDocument/typeDefinition' and 'textDocument/implementation' replies from
# the LSP server
# Result: Location | Location[] | LocationLink[] | null
def s:processDefDeclReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    WarnMsg("Error: definition is not found")
    # pop the tag stack
    var tagstack: dict<any> = gettagstack()
    if tagstack.length > 0
      settagstack(winnr(), {curidx: tagstack.length}, 't')
    endif
    return
  endif

  var location: dict<any>
  if reply.result->type() == v:t_list
    location = reply.result[0]
  else
    location = reply.result
  endif
  var fname = LspUriToFile(location.uri)
  var wid = fname->bufwinid()
  if wid != -1
    wid->win_gotoid()
  else
    var bnr: number = fname->bufnr()
    if bnr != -1
      if &modified || &buftype != ''
	exe 'sb ' .. bnr
      else
	exe 'buf ' .. bnr
      endif
    else
      if &modified || &buftype != ''
	# if the current buffer has unsaved changes, then open the file in a
	# new window
	exe 'split ' .. fname
      else
	exe 'edit  ' .. fname
      endif
    endif
  endif
  # Set the previous cursor location mark
  setpos("'`", getcurpos())
  setcursorcharpos(location.range.start.line + 1,
			location.range.start.character + 1)
  redraw!
enddef

# process the 'textDocument/signatureHelp' reply from the LSP server
# Result: SignatureHelp | null
def s:processSignaturehelpReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var result: dict<any> = reply.result
  if result.signatures->len() <= 0
    WarnMsg('No signature help available')
    return
  endif

  var sigidx: number = 0
  if result->has_key('activeSignature')
    sigidx = result.activeSignature
  endif

  var sig: dict<any> = result.signatures[sigidx]
  var text = sig.label
  var hllen = 0
  var startcol = 0
  if sig->has_key('parameters') && result->has_key('activeParameter')
    var params_len = sig.parameters->len()
    if params_len > 0 && result.activeParameter < params_len
      var label = ''
      if sig.parameters[result.activeParameter]->has_key('documentation')
        label = sig.parameters[result.activeParameter].documentation
      else
        label = sig.parameters[result.activeParameter].label
      endif
      hllen = label->len()
      startcol = text->stridx(label)
    endif
  endif
  if lspOptions.showSignature
    echon "\r\r"
    echon ''
    echon strpart(text, 0, startcol)
    echoh LineNr
    echon strpart(text, startcol, hllen)
    echoh None
    echon strpart(text, startcol + hllen)
  else
    var popupID = text->popup_atcursor({moved: 'any'})
    prop_type_add('signature', {bufnr: popupID->winbufnr(), highlight: 'LineNr'})
    if hllen > 0
      prop_add(1, startcol + 1, {bufnr: popupID->winbufnr(), length: hllen, type: 'signature'})
    endif
  endif
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
def s:processCompletionReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
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

  if lspOptions.autoComplete
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
def s:processHoverReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var hoverText: list<string>

  if reply.result.contents->type() == v:t_dict
    if reply.result.contents->has_key('kind')
      # MarkupContent
      if reply.result.contents.kind == 'plaintext'
	hoverText = reply.result.contents.value->split("\n")
      elseif reply.result.contents.kind == 'markdown'
	hoverText = reply.result.contents.value->split("\n")
      else
	ErrMsg('Error: Unsupported hover contents type (' .. reply.result.contents.kind .. ')')
	return
      endif
    elseif reply.result.contents->has_key('value')
      # MarkedString
      hoverText = reply.result.contents.value->split("\n")
    else
      ErrMsg('Error: Unsupported hover contents (' .. reply.result.contents .. ')')
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
    ErrMsg('Error: Unsupported hover contents (' .. reply.result.contents .. ')')
    return
  endif
  hoverText->popup_atcursor({moved: 'word'})
enddef

# process the 'textDocument/references' reply from the LSP server
# Result: Location[] | null
def s:processReferencesReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    WarnMsg('Error: No references found')
    return
  endif

  # create a quickfix list with the location of the references
  var locations: list<dict<any>> = reply.result
  var qflist: list<dict<any>> = []
  for loc in locations
    var fname: string = LspUriToFile(loc.uri)
    var bnr: number = fname->bufnr()
    if bnr == -1
      bnr = fname->bufadd()
    endif
    if !bnr->bufloaded()
      bnr->bufload()
    endif
    var text: string = bnr->getbufline(loc.range.start.line + 1)[0]
						->trim("\t ", 1)
    qflist->add({filename: fname,
			lnum: loc.range.start.line + 1,
			col: GetLineByteFromPos(bnr, loc.range.start) + 1,
			text: text})
  endfor
  setloclist(0, [], ' ', {title: 'Symbol Reference', items: qflist})
  var save_winid = win_getid()
  :lopen
  save_winid->win_gotoid()
enddef

# process the 'textDocument/documentHighlight' reply from the LSP server
# Result: DocumentHighlight[] | null
def s:processDocHighlightReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var fname: string = LspUriToFile(req.params.textDocument.uri)
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
		GetLineByteFromPos(bnr, docHL.range.start) + 1,
		{end_lnum: docHL.range.end.line + 1,
		  end_col: GetLineByteFromPos(bnr, docHL.range.end) + 1,
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
def s:processSymbolInfoTable(symbolInfoTable: list<dict<any>>,
				symbolTypeTable: dict<list<dict<any>>>,
				symbolLineTable: list<dict<any>>)
  var fname: string
  var symbolType: string
  var name: string
  var r: dict<dict<number>>
  var symInfo: dict<any>

  for symbol in symbolInfoTable
    fname = LspUriToFile(symbol.location.uri)
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
def s:processDocSymbolTable(docSymbolTable: list<dict<any>>,
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
      s:processDocSymbolTable(symbol.children, childSymbols, symbolLineTable)
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
def s:processDocSymbolReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var fname: string
  var symbolTypeTable: dict<list<dict<any>>> = {}
  var symbolLineTable: list<dict<any>> = []

  if req.params.textDocument.uri != ''
    fname = LspUriToFile(req.params.textDocument.uri)
  endif

  if reply.result->empty()
    # No symbols defined for this file. Clear the outline window.
    lsp#updateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
    return
  endif

  if reply.result[0]->has_key('location')
    # SymbolInformation[]
    s:processSymbolInfoTable(reply.result, symbolTypeTable, symbolLineTable)
  else
    # DocumentSymbol[]
    s:processDocSymbolTable(reply.result, symbolTypeTable, symbolLineTable)
  endif

  # sort the symbols by line number
  symbolLineTable->sort((a, b) => a.range.start.line - b.range.start.line)
  lsp#updateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
enddef

# sort the list of edit operations in the descending order of line and column
# numbers.
# 'a': {'A': [lnum, col], 'B': [lnum, col]}
# 'b': {'A': [lnum, col], 'B': [lnum, col]}
def s:edit_sort_func(a: dict<any>, b: dict<any>): number
  # line number
  if a.A[0] != b.A[0]
    return b.A[0] - a.A[0]
  endif
  # column number
  if a.A[1] != b.A[1]
    return b.A[1] - a.A[1]
  endif

  return 0
enddef

# Replaces text in a range with new text.
#
# CAUTION: Changes in-place!
#
# 'lines': Original list of strings
# 'A': Start position; [line, col]
# 'B': End position [line, col]
# 'new_lines' A list of strings to replace the original
#
# returns the modified 'lines'
def s:set_lines(lines: list<string>, A: list<number>, B: list<number>,
					new_lines: list<string>): list<string>
  var i_0: number = A[0]

  # If it extends past the end, truncate it to the end. This is because the
  # way the LSP describes the range including the last newline is by
  # specifying a line number after what we would call the last line.
  var numlines: number = lines->len()
  var i_n = [B[0], numlines - 1]->min()

  if i_0 < 0 || i_0 >= numlines || i_n < 0 || i_n >= numlines
    WarnMsg("set_lines: Invalid range, A = " .. A->string()
		.. ", B = " ..  B->string() .. ", numlines = " .. numlines
		.. ", new lines = " .. new_lines->string())
    return lines
  endif

  # save the prefix and suffix text before doing the replacements
  var prefix: string = ''
  var suffix: string = lines[i_n][B[1] :]
  if A[1] > 0
    prefix = lines[i_0][0 : A[1] - 1]
  endif

  var new_lines_len: number = new_lines->len()

  #echomsg 'i_0 = ' .. i_0 .. ', i_n = ' .. i_n .. ', new_lines = ' .. string(new_lines)
  var n: number = i_n - i_0 + 1
  if n != new_lines_len
    if n > new_lines_len
      # remove the deleted lines
      lines->remove(i_0, i_0 + n - new_lines_len - 1)
    else
      # add empty lines for newly the added lines (will be replaced with the
      # actual lines below)
      lines->extend(repeat([''], new_lines_len - n), i_0)
    endif
  endif
  #echomsg "lines(1) = " .. string(lines)

  # replace the previous lines with the new lines
  for i in range(new_lines_len)
    lines[i_0 + i] = new_lines[i]
  endfor
  #echomsg "lines(2) = " .. string(lines)

  # append the suffix (if any) to the last line
  if suffix != ''
    var i = i_0 + new_lines_len - 1
    lines[i] = lines[i] .. suffix
  endif
  #echomsg "lines(3) = " .. string(lines)

  # prepend the prefix (if any) to the first line
  if prefix != ''
    lines[i_0] = prefix .. lines[i_0]
  endif
  #echomsg "lines(4) = " .. string(lines)

  return lines
enddef

# Apply set of text edits to the specified buffer
# The text edit logic is ported from the Neovim lua implementation
def s:applyTextEdits(bnr: number, text_edits: list<dict<any>>): void
  if text_edits->empty()
    return
  endif

  # if the buffer is not loaded, load it and make it a listed buffer
  if !bnr->bufloaded()
    bnr->bufload()
  endif
  setbufvar(bnr, '&buflisted', true)

  var start_line: number = 4294967295		# 2 ^ 32
  var finish_line: number = -1
  var updated_edits: list<dict<any>> = []
  var start_row: number
  var start_col: number
  var end_row: number
  var end_col: number

  # create a list of buffer positions where the edits have to be applied.
  for e in text_edits
    # Adjust the start and end columns for multibyte characters
    start_row = e.range.start.line
    start_col = GetLineByteFromPos(bnr, e.range.start)
    end_row = e.range.end.line
    end_col = GetLineByteFromPos(bnr, e.range.end)
    start_line = [e.range.start.line, start_line]->min()
    finish_line = [e.range.end.line, finish_line]->max()

    updated_edits->add({A: [start_row, start_col],
			B: [end_row, end_col],
			lines: e.newText->split("\n", true)})
  endfor

  # Reverse sort the edit operations by descending line and column numbers so
  # that they can be applied without interfering with each other.
  updated_edits->sort('s:edit_sort_func')

  var lines: list<string> = bnr->getbufline(start_line + 1, finish_line + 1)
  var fix_eol: bool = bnr->getbufvar('&fixeol')
  var set_eol = fix_eol && bnr->getbufinfo()[0].linecount <= finish_line + 1
  if set_eol && lines[-1]->len() != 0
    lines->add('')
  endif

  #echomsg 'lines(1) = ' .. string(lines)
  #echomsg updated_edits

  for e in updated_edits
    var A: list<number> = [e.A[0] - start_line, e.A[1]]
    var B: list<number> = [e.B[0] - start_line, e.B[1]]
    lines = s:set_lines(lines, A, B, e.lines)
  endfor

  #echomsg 'lines(2) = ' .. string(lines)

  # If the last line is empty and we need to set EOL, then remove it.
  if set_eol && lines[-1]->len() == 0
    lines->remove(-1)
  endif

  #echomsg 'applyTextEdits: start_line = ' .. start_line .. ', finish_line = ' .. finish_line
  #echomsg 'lines = ' .. string(lines)

  # Delete all the lines that need to be modified
  bnr->deletebufline(start_line + 1, finish_line + 1)

  # if the buffer is empty, appending lines before the first line adds an
  # extra empty line at the end. Delete the empty line after appending the
  # lines.
  var dellastline: bool = false
  if start_line == 0 && bnr->getbufinfo()[0].linecount == 1 &&
						bnr->getbufline(1)[0] == ''
    dellastline = true
  endif

  # Append the updated lines
  appendbufline(bnr, start_line, lines)

  if dellastline
    bnr->deletebufline(bnr->getbufinfo()[0].linecount)
  endif
enddef

# interface TextDocumentEdit
def s:applyTextDocumentEdit(textDocEdit: dict<any>)
  var bnr: number = bufnr(LspUriToFile(textDocEdit.textDocument.uri))
  if bnr == -1
    ErrMsg('Error: Text Document edit, buffer ' .. textDocEdit.textDocument.uri .. ' is not found')
    return
  endif
  s:applyTextEdits(bnr, textDocEdit.edits)
enddef

# interface WorkspaceEdit
def s:applyWorkspaceEdit(workspaceEdit: dict<any>)
  if workspaceEdit->has_key('documentChanges')
    for change in workspaceEdit.documentChanges
      if change->has_key('kind')
	ErrMsg('Error: Unsupported change in workspace edit [' .. change.kind .. ']')
      else
	s:applyTextDocumentEdit(change)
      endif
    endfor
    return
  endif

  if !workspaceEdit->has_key('changes')
    return
  endif

  var save_cursor: list<number> = getcurpos()
  for [uri, changes] in workspaceEdit.changes->items()
    var fname: string = LspUriToFile(uri)
    var bnr: number = fname->bufnr()
    if bnr == -1
      # file is already removed
      continue
    endif

    # interface TextEdit
    s:applyTextEdits(bnr, changes)
  endfor
  # Restore the cursor to the location before the edit
  save_cursor->setpos('.')
enddef

# process the 'textDocument/formatting' reply from the LSP server
# Result: TextEdit[] | null
def s:processFormatReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # nothing to format
    return
  endif

  # result: TextEdit[]

  var fname: string = LspUriToFile(req.params.textDocument.uri)
  var bnr: number = fname->bufnr()
  if bnr == -1
    # file is already removed
    return
  endif

  # interface TextEdit
  # Apply each of the text edit operations
  var save_cursor: list<number> = getcurpos()
  s:applyTextEdits(bnr, reply.result)
  save_cursor->setpos('.')
enddef

# Reply: 'textDocument/rename'
# Result: Range | { range: Range, placeholder: string }
#	        | { defaultBehavior: boolean } | null
def s:processRenameReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # nothing to rename
    return
  endif

  # result: WorkspaceEdit
  s:applyWorkspaceEdit(reply.result)
enddef

# Request the LSP server to execute a command
# Request: workspace/executeCommand
# Params: ExecuteCommandParams
def s:executeCommand(lspserver: dict<any>, cmd: dict<any>)
  var req = lspserver.createRequest('workspace/executeCommand')
  req.params->extend(cmd)
  lspserver.sendMessage(req)
enddef

# process the 'textDocument/codeAction' reply from the LSP server
# Result: (Command | CodeAction)[] | null
def s:processCodeActionReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # no action can be performed
    WarnMsg('No code action is available')
    return
  endif

  var actions: list<dict<any>> = reply.result

  var prompt: list<string> = ['Code Actions:']
  var act: dict<any>
  for i in range(actions->len())
    act = actions[i]
    var t: string = act.title->substitute('\r\n', '\\r\\n', 'g')
    t = t->substitute('\n', '\\n', 'g')
    prompt->add(printf("%d. %s", i + 1, t))
  endfor
  var choice = inputlist(prompt)
  if choice < 1 || choice > prompt->len()
    return
  endif

  var selAction = actions[choice - 1]

  # textDocument/codeAction can return either Command[] or CodeAction[].
  # If it is a CodeAction, it can have either an edit, a command or both.
  # Edits should be executed first.
  if selAction->has_key('edit') || selAction->has_key('command')
    if selAction->has_key('edit')
      # apply edit first
      s:applyWorkspaceEdit(selAction.edit)
    endif
    if selAction->has_key('command')
      s:executeCommand(lspserver, selAction)
    endif
  else
    s:executeCommand(lspserver, selAction)
  endif
enddef

# Reply: 'textDocument/selectionRange'
# Result: SelectionRange[] | null
def s:processSelectionRangeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    return
  endif

  var r: dict<dict<number>> = reply.result[0].range
  var bnr: number = bufnr()
  var start_col: number = GetLineByteFromPos(bnr, r.start) + 1
  var end_col: number = GetLineByteFromPos(bnr, r.end)

  setcharpos("'<", [0, r.start.line + 1, start_col, 0])
  setcharpos("'>", [0, r.end.line + 1, end_col, 0])
  :normal gv
enddef

# Reply: 'textDocument/foldingRange'
# Result: FoldingRange[] | null
def s:processFoldingRangeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
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
def s:processWorkspaceExecuteReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    return
  endif

  # Nothing to do for the reply
enddef

# Convert a file name <filename> (<dirname>) format.
# Make sure the popup does't occupy the entire screen by reducing the width.
def s:makeMenuName(popupWidth: number, fname: string): string
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
def s:processWorkspaceSymbolReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
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
    fileName = LspUriToFile(symbol.location.uri)
    r = symbol.location.range

    symName = symbol.name
    if symbol->has_key('containerName') && symbol.containerName != ''
      symName = symbol.containerName .. '::' .. symName
    endif
    symName ..= ' [' .. LspSymbolKindToName(symbol.kind) .. ']'
    symName ..= ' ' .. s:makeMenuName(
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
def s:processPrepareCallHierarchy(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    return
  endif

  var items: list<string> = ['Select a Call Hierarchy Item:']
  for i in range(reply.result->len())
    items->add(printf("%d. %s", i + 1, reply.result[i].name))
  endfor
  var choice = inputlist(items)
  if choice < 1 || choice > items->len()
    return
  endif

  echomsg reply.result[choice - 1]
enddef

# Process various reply messages from the LSP server
export def ProcessReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var lsp_reply_handlers: dict<func> =
    {
      'initialize': function('s:processInitializeReply'),
      'textDocument/definition': function('s:processDefDeclReply'),
      'textDocument/declaration': function('s:processDefDeclReply'),
      'textDocument/typeDefinition': function('s:processDefDeclReply'),
      'textDocument/implementation': function('s:processDefDeclReply'),
      'textDocument/signatureHelp': function('s:processSignaturehelpReply'),
      'textDocument/completion': function('s:processCompletionReply'),
      'textDocument/hover': function('s:processHoverReply'),
      'textDocument/references': function('s:processReferencesReply'),
      'textDocument/documentHighlight': function('s:processDocHighlightReply'),
      'textDocument/documentSymbol': function('s:processDocSymbolReply'),
      'textDocument/formatting': function('s:processFormatReply'),
      'textDocument/rangeFormatting': function('s:processFormatReply'),
      'textDocument/rename': function('s:processRenameReply'),
      'textDocument/codeAction': function('s:processCodeActionReply'),
      'textDocument/selectionRange': function('s:processSelectionRangeReply'),
      'textDocument/foldingRange': function('s:processFoldingRangeReply'),
      'workspace/executeCommand': function('s:processWorkspaceExecuteReply'),
      'workspace/symbol': function('s:processWorkspaceSymbolReply'),
      'textDocument/prepareCallHierarchy': function('s:processPrepareCallHierarchy')
    }

  if lsp_reply_handlers->has_key(req.method)
    lsp_reply_handlers[req.method](lspserver, req, reply)
  else
    ErrMsg("Error: Unsupported reply received from LSP server: " .. reply->string())
  endif
enddef

# process a diagnostic notification message from the LSP server
# Notification: textDocument/publishDiagnostics
# Param: PublishDiagnosticsParams
def s:processDiagNotif(lspserver: dict<any>, reply: dict<any>): void
  var fname: string = LspUriToFile(reply.params.uri)
  var bnr: number = fname->bufnr()
  if bnr == -1
    # Is this condition possible?
    return
  endif

  # TODO: Is the buffer (bnr) always a loaded buffer? Should we load it here?
  var lastlnum: number = bnr->getbufinfo()[0].linecount
  var lnum: number

  # store the diagnostic for each line separately
  var diag_by_lnum: dict<dict<any>> = {}
  for diag in reply.params.diagnostics
    lnum = diag.range.start.line + 1
    if lnum > lastlnum
      # Make sure the line number is a valid buffer line number
      lnum = lastlnum
    endif
    diag_by_lnum[lnum] = diag
  endfor

  lspserver.diagsMap->extend({['' .. bnr]: diag_by_lnum})
  LspDiagsUpdated(lspserver, bnr)
enddef

# process a show notification message from the LSP server
# Notification: window/showMessage
# Param: ShowMessageParams
def s:processShowMsgNotif(lspserver: dict<any>, reply: dict<any>)
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
def s:processLogMsgNotif(lspserver: dict<any>, reply: dict<any>)
  var msgType: list<string> = ['', 'Error: ', 'Warning: ', 'Info: ', 'Log: ']
  var mtype: string = 'Log: '
  if reply.params.type > 0 && reply.params.type < 5
    mtype = msgType[reply.params.type]
  endif

  TraceLog(false, '[' .. mtype .. ']: ' .. reply.params.message)
enddef

# process unsupported notification messages
def s:processUnsupportedNotif(lspserver: dict<any>, reply: dict<any>)
  ErrMsg('Error: Unsupported notification message received from the LSP server (' .. lspserver.path .. '), message = ' .. reply->string())
enddef

# ignore unsupported notification message
def s:ignoreNotif(lspserver: dict<any>, reply: dict<any>)
enddef

# process notification messages from the LSP server
export def ProcessNotif(lspserver: dict<any>, reply: dict<any>): void
  var lsp_notif_handlers: dict<func> =
    {
      'window/showMessage': function('s:processShowMsgNotif'),
      'window/logMessage': function('s:processLogMsgNotif'),
      'textDocument/publishDiagnostics': function('s:processDiagNotif'),
      '$/progress': function('s:processUnsupportedNotif'),
      'telemetry/event': function('s:processUnsupportedNotif'),
      # Java language server sends the 'language/status' notification which is
      # not in the LSP specification
      'language/status': function('s:ignoreNotif')
    }

  if lsp_notif_handlers->has_key(reply.method)
    lsp_notif_handlers[reply.method](lspserver, reply)
  else
    ErrMsg('Error: Unsupported notification received from LSP server ' .. reply->string())
  endif
enddef

# process the workspace/applyEdit LSP server request
# Request: "workspace/applyEdit"
# Param: ApplyWorkspaceEditParams
def s:processApplyEditReq(lspserver: dict<any>, request: dict<any>)
  # interface ApplyWorkspaceEditParams
  if !request->has_key('params')
    return
  endif
  var workspaceEditParams: dict<any> = request.params
  if workspaceEditParams->has_key('label')
    :echomsg "Workspace edit" .. workspaceEditParams.label
  endif
  s:applyWorkspaceEdit(workspaceEditParams.edit)
  # TODO: Need to return the proper result of the edit operation
  lspserver.sendResponse(request, {applied: true}, v:null)
enddef

def s:processUnsupportedReq(lspserver: dict<any>, request: dict<any>)
  ErrMsg('Error: Unsupported request message received from the LSP server (' .. lspserver.path .. '), message = ' .. request->string())
enddef

# process a request message from the server
export def ProcessRequest(lspserver: dict<any>, request: dict<any>)
  var lspRequestHandlers: dict<func> =
    {
      'workspace/applyEdit': function('s:processApplyEditReq'),
      'window/workDoneProgress/create': function('s:processUnsupportedReq'),
      'client/registerCapability': function('s:processUnsupportedReq'),
      'client/unregisterCapability': function('s:processUnsupportedReq'),
      'workspace/workspaceFolders': function('s:processUnsupportedReq'),
      'workspace/configuration': function('s:processUnsupportedReq'),
      'workspace/codeLens/refresh': function('s:processUnsupportedReq'),
      'workspace/semanticTokens/refresh': function('s:processUnsupportedReq')
    }

  if lspRequestHandlers->has_key(request.method)
    lspRequestHandlers[request.method](lspserver, request)
  else
    ErrMsg('Error: Unsupported request received from LSP server ' ..
							request->string())
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
      ErrMsg("Error(LSP): Invalid content length")
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
      ErrMsg("Error(LSP): Malformed content (" .. content .. ")")
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
	  ErrMsg("Error(LSP): request " .. req.method .. " failed ("
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
      ErrMsg("Error(LSP): Unsupported message (" .. msg->string() .. ")")
    endif

    lspserver.data = lspserver.data[idx + len :]
  endwhile
enddef

# vim: shiftwidth=2 softtabstop=2
