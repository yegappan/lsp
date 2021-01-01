vim9script

import {WarnMsg, ErrMsg, LspUriToFile} from './util.vim'

# process the 'initialize' method reply from the LSP server
def s:processInitializeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->len() <= 0
    return
  endif

  # interface 'InitializeResult'
  var caps: dict<any> = reply.result.capabilities
  lspserver.caps = caps

  # TODO: Check all the buffers with filetype corresponding to this LSP server
  # and then setup the below mapping for those buffers.

  # map characters that trigger signature help
  if caps->has_key('signatureHelpProvider')
    var triggers = caps.signatureHelpProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch .. "<C-R>=lsp#showSignature()<CR>"
    endfor
  endif

  # map characters that trigger insert mode completion
  if caps->has_key('completionProvider')
    var triggers = caps.completionProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch .. "<C-X><C-U>"
    endfor
  endif

  # send a "initialized" notification to server
  lspserver.sendInitializedNotif()
enddef

# process the 'textDocument/definition' / 'textDocument/declaration' /
# 'textDocument/typeDefinition' and 'textDocument/implementation' replies from
# the LSP server
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

  var result: dict<any> = reply.result[0]
  var file = LspUriToFile(result.uri)
  var wid = bufwinid(file)
  if wid != -1
    win_gotoid(wid)
  else
    exe 'split ' .. file
  endif
  # Set the previous cursor location mark
  setpos("'`", getcurpos())
  cursor(result.range.start.line + 1, result.range.start.character + 1)
  redraw!
enddef

# process the 'textDocument/signatureHelp' reply from the LSP server
def s:processSignaturehelpReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  var result: dict<any> = reply.result
  if result.signatures->len() <= 0
    WarnMsg('No signature help available')
    return
  endif

  var sig: dict<any> = result.signatures[result.activeSignature]
  var text = sig.label
  var hllen = 0
  var startcol = 0
  if sig->has_key('parameters')
    var params_len = sig.parameters->len()
    if params_len > 0 && result.activeParameter < params_len
      var label = sig.parameters[result.activeParameter].label
      hllen = label->len()
      startcol = text->stridx(label)
    endif
  endif
  var popupID = popup_atcursor(text, {})
  prop_type_add('signature', {bufnr: winbufnr(popupID), highlight: 'Title'})
  if hllen > 0
    prop_add(1, startcol + 1, {bufnr: winbufnr(popupID), length: hllen, type: 'signature'})
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
def s:processCompletionReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void

  var items: list<dict<any>>
  if type(reply.result) == v:t_list
    items = reply.result
  else
    items = reply.result.items
  endif

  for item in items
    var d: dict<any> = {}
    if item->has_key('insertText')
      d.word = item.insertText
    elseif item->has_key('textEdit')
      d.word = item.textEdit.newText
    else
      d.word = item.label
    endif
    if item->has_key('kind')
      # namespace CompletionItemKind
      # map LSP kind to complete-item-kind
      d.kind = LspCompleteItemKindChar(item.kind)
    endif
    if item->has_key('detail')
      d.info = item.detail
    endif
    if item->has_key('documentation')
      d.menu = item.documentation
    endif
    lspserver.completeItems->add(d)
  endfor

  lspserver.completePending = v:false
enddef

# process the 'textDocument/hover' reply from the LSP server
def s:processHoverReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if type(reply.result) == v:t_none
    return
  endif

  var hoverText: list<string>

  if type(reply.result.contents) == v:t_dict
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
      hoverText = reply.result.contents.value
    else
      ErrMsg('Error: Unsupported hover contents (' .. reply.result.contents .. ')')
      return
    endif
  elseif type(reply.result.contents) == v:t_list
    # interface MarkedString[]
    for e in reply.result.contents
      if type(e) == v:t_string
	hoverText->extend(e->split("\n"))
      else
	hoverText->extend(e.value->split("\n"))
      endif
    endfor
  elseif type(reply.result.contents) == v:t_string
    if reply.result.contents->empty()
      return
    endif
    hoverText->add(reply.result.contents)
  else
    ErrMsg('Error: Unsupported hover contents (' .. reply.result.contents .. ')')
    return
  endif
  hoverText->popup_atcursor({moved: 'word'})
enddef

# process the 'textDocument/references' reply from the LSP server
def s:processReferencesReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if type(reply.result) == v:t_none || reply.result->empty()
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
      bnr->bufload()
    endif
    var text: string = bnr->getbufline(loc.range.start.line + 1)[0]
						->trim("\t ", 1)
    qflist->add({filename: fname,
			lnum: loc.range.start.line + 1,
			col: loc.range.start.character + 1,
			text: text})
  endfor
  setqflist([], ' ', {title: 'Language Server', items: qflist})
  var save_winid = win_getid()
  copen
  win_gotoid(save_winid)
enddef

# process the 'textDocument/documentHighlight' reply from the LSP server
def s:processDocHighlightReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    return
  endif

  var fname: string = LspUriToFile(req.params.textDocument.uri)
  var bnr = bufnr(fname)

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
    prop_add(docHL.range.start.line + 1, docHL.range.start.character + 1,
		{end_lnum: docHL.range.end.line + 1,
		  end_col: docHL.range.end.character + 1,
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

# jump to a symbol selected in the symbols window
def handlers#jumpToSymbol()
  var lnum: number = line('.') - 1
  if w:lsp_info.data[lnum]->empty()
    return
  endif

  var slnum: number = w:lsp_info.data[lnum].lnum
  var scol: number = w:lsp_info.data[lnum].col
  var fname: string = w:lsp_info.filename

  # If the file is already opened in a window, jump to it. Otherwise open it
  # in another window
  var wid: number = fname->bufwinid()
  if wid == -1
    # Find a window showing a normal buffer and use it
    for w in getwininfo()
      if w.winid->getwinvar('&buftype') == ''
	wid = w.winid
	wid->win_gotoid()
	break
      endif
    endfor
    if wid == -1
      var symWinid: number = win_getid()
      :rightbelow vnew
      # retain the fixed symbol window width
      win_execute(symWinid, 'vertical resize 20')
    endif

    exe 'edit ' .. fname
  else
    wid->win_gotoid()
  endif
  [slnum, scol]->cursor()
enddef

# display the list of document symbols from the LSP server in a window as a
# tree
def s:showSymbols(symTable: list<dict<any>>)
  var symbols: dict<list<dict<any>>>
  var symbolType: string
  var fname: string

  for symbol in symTable
    if symbol->has_key('location')
      fname = LspUriToFile(symbol.location.uri)
      symbolType = LspSymbolKindToName(symbol.kind)
      if !symbols->has_key(symbolType)
	symbols[symbolType] = []
      endif
      var name: string = symbol.name
      if symbol->has_key('containerName')
	if symbol.containerName != ''
	  name ..= ' [' .. symbol.containerName .. ']'
	endif
      endif
      symbols[symbolType]->add({name: name,
			lnum: symbol.location.range.start.line + 1,
			col: symbol.location.range.start.character + 1})
    endif
  endfor

  var wid: number = bufwinid('LSP-Symbols')
  if wid == -1
    :20vnew LSP-Symbols
  else
    win_gotoid(wid)
  endif

  :setlocal modifiable
  :setlocal noreadonly
  :silent! :%d _
  :setlocal buftype=nofile
  :setlocal bufhidden=delete
  :setlocal noswapfile nobuflisted
  :setlocal nonumber norelativenumber fdc=0 nowrap winfixheight winfixwidth
  setline(1, ['# Language Server Symbols', '# ' .. fname])
  # First two lines in the buffer display comment information
  var lnumMap: list<dict<number>> = [{}, {}]
  var text: list<string> = []
  for [symType, syms] in items(symbols)
    text->extend(['', symType])
    lnumMap->extend([{}, {}])
    for s in syms
      text->add('  ' .. s.name)
      lnumMap->add({lnum: s.lnum, col: s.col})
    endfor
  endfor
  append(line('$'), text)
  w:lsp_info = {filename: fname, data: lnumMap}
  :nnoremap <silent> <buffer> q :quit<CR>
  :nnoremap <silent> <buffer> <CR> :call handlers#jumpToSymbol()<CR>
  :setlocal nomodifiable
enddef

# process the 'textDocument/documentSymbol' reply from the LSP server
# Open a symbols window and display the symbols as a tree
def s:processDocSymbolReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>): void
  if reply.result->empty()
    WarnMsg('No symbols are found')
    return
  endif

  s:showSymbols(reply.result)
enddef

# Returns the byte number of the specified line/col position.  Returns a
# zero-indexed column.  'pos' is LSP "interface position".
def s:get_line_byte_from_position(bnr: number, pos: dict<number>): number
  # LSP's line and characters are 0-indexed
  # Vim's line and columns are 1-indexed
  var col: number = pos.character
  # When on the first character, we can ignore the difference between byte and
  # character
  if col > 0
    if !bnr->bufloaded()
      bnr->bufload()
    endif

    var ltext: list<string> = bnr->getbufline(pos.line + 1)
    if !ltext->empty()
      var bidx = ltext[0]->byteidx(col)
      if bidx != -1
	return bidx
      endif
    endif
  endif

  return col
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
    WarnMsg("set_lines: Invalid range, A = " .. string(A)
		.. ", B = " ..  string(B) .. ", numlines = " .. numlines
		.. ", new lines = " .. string(new_lines))
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
  bnr->setbufvar('&buflisted', v:true)

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
    start_col = s:get_line_byte_from_position(bnr, e.range.start)
    end_row = e.range.end.line
    end_col = s:get_line_byte_from_position(bnr, e.range.end)
    start_line = [e.range.start.line, start_line]->min()
    finish_line = [e.range.end.line, finish_line]->max()

    updated_edits->add({A: [start_row, start_col],
			B: [end_row, end_col],
			lines: e.newText->split("\n", v:true)})
  endfor

  # Reverse sort the edit operations by descending line and column numbers so
  # that they can be applied without interfering with each other.
  updated_edits->sort('s:edit_sort_func')

  var lines: list<string> = bnr->getbufline(start_line + 1, finish_line + 1)
  var fix_eol: number = bnr->getbufvar('&fixeol')
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
  var dellastline: bool = v:false
  if start_line == 0 && bnr->getbufinfo()[0].linecount == 1 &&
						bnr->getbufline(1)[0] == ''
    dellastline = v:true
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
  for [uri, changes] in items(workspaceEdit.changes)
    var fname: string = LspUriToFile(uri)
    var bnr: number = bufnr(fname)
    if bnr == -1
      # file is already removed
      continue
    endif

    # interface TextEdit
    s:applyTextEdits(bnr, changes)
  endfor
  save_cursor->setpos('.')
enddef

# process the 'textDocument/formatting' reply from the LSP server
def s:processFormatReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # nothing to format
    return
  endif

  # result: TextEdit[]

  var fname: string = LspUriToFile(req.params.textDocument.uri)
  var bnr: number = bufnr(fname)
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

# process the 'textDocument/rename' reply from the LSP server
def s:processRenameReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    # nothing to rename
    return
  endif

  # result: WorkspaceEdit
  s:applyWorkspaceEdit(reply.result)
enddef

# interface ExecuteCommandParams
def s:executeCommand(lspserver: dict<any>, cmd: dict<any>)
  var req = lspserver.createRequest('workspace/executeCommand')
  req.params->extend(cmd)
  lspserver.sendMessage(req)
enddef

# process the 'textDocument/codeAction' reply from the LSP server
# params: interface Command[] | interface CodeAction[]
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

# process the 'textDocument/selectionRange' reply from the LSP server
def s:processSelectionRangeReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    return
  endif

  var r: dict<dict<number>> = reply.result[0].range

  setpos("'<", [0, r.start.line + 1, r.start.character + 1, 0])
  setpos("'>", [0, r.end.line + 1, r.end.character, 0])
  :normal gv
enddef

# process the 'textDocument/foldingRange' reply from the LSP server
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
    :foldopen!
  endfor

  if &foldcolumn == 0
    :setlocal foldcolumn=2
  endif
enddef

# process the 'workspace/executeCommand' reply from the LSP server
def s:processWorkspaceExecuteReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    return
  endif

  # Nothing to do for the reply
enddef

# process the 'workspace/symbol' reply from the LSP server
def s:processWorkspaceSymbolReply(lspserver: dict<any>, req: dict<any>, reply: dict<any>)
  if reply.result->empty()
    WarnMsg('Error: Symbol not found')
    return
  endif

  s:showSymbols(reply.result)
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
      'workspace/symbol': function('s:processWorkspaceSymbolReply')
    }

  if lsp_reply_handlers->has_key(req.method)
    lsp_reply_handlers[req.method](lspserver, req, reply)
  else
    ErrMsg("Error: Unsupported reply received from LSP server: " .. string(reply))
  endif
enddef

# process a diagnostic notification message from the LSP server
# params: interface PublishDiagnosticsParams
def s:processDiagNotif(lspserver: dict<any>, reply: dict<any>): void
  var fname: string = LspUriToFile(reply.params.uri)

  # store the diagnostic for each line separately
  var diag_by_lnum: dict<dict<any>> = {}
  for diag in reply.params.diagnostics
    diag_by_lnum[diag.range.start.line + 1] = diag
  endfor

  lspserver.diagsMap->extend({[fname]: diag_by_lnum})
enddef

# process a log notification message from the LSP server
def s:processLogMsgNotif(lspserver: dict<any>, reply: dict<any>)
  # interface LogMessageParams
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

# process notification messages from the LSP server
export def ProcessNotif(lspserver: dict<any>, reply: dict<any>): void
  var lsp_notif_handlers: dict<func> =
    {
      'textDocument/publishDiagnostics': function('s:processDiagNotif'),
      'window/showMessage': function('s:processLogMsgNotif'),
      'window/logMessage': function('s:processLogMsgNotif')
    }

  if lsp_notif_handlers->has_key(reply.method)
    lsp_notif_handlers[reply.method](lspserver, reply)
  else
    ErrMsg('Error: Unsupported notification received from LSP server ' .. string(reply))
  endif
enddef

# process the workspace/applyEdit LSP server request
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
  lspserver.sendResponse(request, {applied: v:true}, v:null)
enddef

# process a request message from the server
export def ProcessRequest(lspserver: dict<any>, request: dict<any>)
  var lspRequestHandlers: dict<func> =
    {
      'workspace/applyEdit': function('s:processApplyEditReq')
    }

  if lspRequestHandlers->has_key(request.method)
    lspRequestHandlers[request.method](lspserver, request)
  else
    ErrMsg('Error: Unsupported request received from LSP server ' ..
							string(request))
  endif
enddef

# process LSP server messages
export def ProcessMessages(lspserver: dict<any>): void
  while lspserver.data->len() > 0
    var idx = stridx(lspserver.data, 'Content-Length: ')
    if idx == -1
      return
    endif

    var len = str2nr(lspserver.data[idx + 16:])
    if len == 0
      ErrMsg("Error: Content length is zero")
      return
    endif

    # Header and contents are separated by '\r\n\r\n'
    idx = stridx(lspserver.data, "\r\n\r\n")
    if idx == -1
      ErrMsg("Error: Content separator is not found")
      return
    endif

    idx = idx + 4

    if lspserver.data->len() - idx < len
      # message is not fully received. Process the message after more data is
      # received
      return
    endif

    var content = lspserver.data[idx : idx + len - 1]
    var msg = content->json_decode()

    if msg->has_key('result') || msg->has_key('error')
      # response message from the server
      var req = lspserver.requests->get(string(msg.id))
      # Remove the corresponding stored request message
      lspserver.requests->remove(string(msg.id))

      if msg->has_key('result')
	lspserver.processReply(req, msg)
      else
	# request failed
	var emsg: string = msg.error.message
	emsg ..= ', code = ' .. msg.code
	if msg.error->has_key('data')
	  emsg = emsg .. ', data = ' .. string(msg.error.data)
	endif
	ErrMsg("Error: request " .. req.method .. " failed (" .. emsg .. ")")
      endif
    elseif msg->has_key('id')
      # request message from the server
      lspserver.processRequest(msg)
    else
      # notification message from the server
      lspserver.processNotif(msg)
    endif

    lspserver.data = lspserver.data[idx + len :]
  endwhile
enddef

# vim: shiftwidth=2 softtabstop=2
