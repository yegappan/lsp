vim9script

# Vim9 LSP client

import NewLspServer from './lspserver.vim'
import {WarnMsg,
	ErrMsg,
	lsp_server_trace,
	ClearTraceLogs,
	GetLineByteFromPos,
	PushCursorToTagStack} from './util.vim'
import {LspDiagsUpdated} from './buf.vim'

# Needs Vim 8.2.2342 and higher
if v:version < 802 || !has('patch-8.2.2342')
  finish
endif

# LSP server information
var lspServers: list<dict<any>> = []

# filetype to LSP server map
var ftypeServerMap: dict<dict<any>> = {}

# per-filetype omni-completion enabled/disabled table
var ftypeOmniCtrlMap: dict<bool> = {}

# Buffer number to LSP server map
var bufnrToServer: dict<dict<any>> = {}

var lspInitializedOnce = false

def s:lspInitOnce()
  # Signs used for LSP diagnostics
  sign_define([{name: 'LspDiagError', text: 'E ', texthl: 'ErrorMsg',
						linehl: 'MatchParen'},
		{name: 'LspDiagWarning', text: 'W ', texthl: 'Search',
						linehl: 'MatchParen'},
		{name: 'LspDiagInfo', text: 'I ', texthl: 'Pmenu',
						linehl: 'MatchParen'},
		{name: 'LspDiagHint', text: 'H ', texthl: 'Question',
						linehl: 'MatchParen'}])

  prop_type_add('LspTextRef', {'highlight': 'Search'})
  prop_type_add('LspReadRef', {'highlight': 'DiffChange'})
  prop_type_add('LspWriteRef', {'highlight': 'DiffDelete'})
  set ballooneval balloonevalterm
  lspInitializedOnce = true
enddef

# Return the LSP server for the a specific filetype. Returns a null dict if
# the server is not found.
def s:lspGetServer(ftype: string): dict<any>
  return ftypeServerMap->get(ftype, {})
enddef

# Add a LSP server for a filetype
def s:lspAddServer(ftype: string, lspserver: dict<any>)
  ftypeServerMap->extend({[ftype]: lspserver})
enddef

# Returns true if omni-completion is enabled for filetype 'ftype'.
# Otherwise, returns false.
def s:lspOmniComplEnabled(ftype: string): bool
  return ftypeOmniCtrlMap->get(ftype, v:false)
enddef

# Enables or disables omni-completion for filetype 'fype'
def s:lspOmniComplSet(ftype: string, enabled: bool)
  ftypeOmniCtrlMap->extend({[ftype]: enabled})
enddef

def lsp#enableServerTrace()
  ClearTraceLogs()
  lsp_server_trace = true
enddef

# Show information about all the LSP servers
def lsp#showServers()
  for [ftype, lspserver] in ftypeServerMap->items()
    var msg = ftype .. "    "
    if lspserver.running
      msg ..= 'running'
    else
      msg ..= 'not running'
    endif
    msg ..= '    ' .. lspserver.path
    :echomsg msg
  endfor
enddef

# Go to a definition using "textDocument/definition" LSP request
def lsp#gotoDefinition()
  var ftype: string = &filetype
  if ftype == '' || @% == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoDefinition()
enddef

# Go to a declaration using "textDocument/declaration" LSP request
def lsp#gotoDeclaration()
  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoDeclaration()
enddef

# Go to a type definition using "textDocument/typeDefinition" LSP request
def lsp#gotoTypedef()
  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoTypeDef()
enddef

# Go to a implementation using "textDocument/implementation" LSP request
def lsp#gotoImplementation()
  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoImplementation()
enddef

# Show the signature using "textDocument/signatureHelp" LSP method
# Invoked from an insert-mode mapping, so return an empty string.
def lsp#showSignature(): string
  var ftype: string = &filetype
  if ftype == ''
    return ''
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return ''
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return ''
  endif

  var fname: string = @%
  if fname == ''
    return ''
  endif

  # first send all the changes in the current buffer to the LSP server
  listener_flush()
  lspserver.showSignature()
  return ''
enddef

# buffer change notification listener
def lsp#bufchange_listener(bnr: number, start: number, end: number, added: number, changes: list<dict<number>>)
  var ftype = bnr->getbufvar('&filetype')
  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return
  endif

  lspserver.textdocDidChange(bnr, start, end, added, changes)
enddef

# A buffer is saved. Send the "textDocument/didSave" LSP notification
def s:lspSavedFile()
  var bnr: number = str2nr(expand('<abuf>'))
  var ftype: string = bnr->getbufvar('&filetype')
  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return
  endif

  lspserver.didSaveFile(bnr)
enddef

# Return the diagnostic text from the LSP server for the current mouse line to
# display in a balloon
var lspDiagPopupID: number = 0
var lspDiagPopupInfo: dict<any> = {}
def g:LspDiagExpr(): string
  var lspserver: dict<any> = bufnrToServer->get(v:beval_bufnr, {})
  if lspserver->empty() || !lspserver.running
    return ''
  endif

  var diagInfo: dict<any> = lspserver.getDiagByLine(v:beval_bufnr,
								v:beval_lnum)
  if diagInfo->empty()
    # No diagnostic for the current cursor location
    return ''
  endif

  return diagInfo.message
enddef

# Called after leaving insert mode. Used to process diag messages (if any)
def lsp#leftInsertMode()
  if !exists('b:LspDiagsUpdatePending')
    return
  endif
  :unlet b:LspDiagsUpdatePending

  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return
  endif
  LspDiagsUpdated(lspserver, bufnr())
enddef

# A new buffer is opened. If LSP is supported for this buffer, then add it
def lsp#addFile(bnr: number): void
  if bufnrToServer->has_key(bnr)
    # LSP server for this buffer is already initialized and running
    return
  endif

  var ftype: string = bnr->getbufvar('&filetype')
  if ftype == ''
    return
  endif
  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    return
  endif
  if !lspserver.running
    if !lspInitializedOnce
      s:lspInitOnce()
    endif
    lspserver.startServer()
  endif
  lspserver.textdocDidOpen(bnr, ftype)

  # file saved notification handler
  autocmd BufWritePost <buffer> call s:lspSavedFile()

  # add a listener to track changes to this buffer
  listener_add(function('lsp#bufchange_listener'), bnr)

  # set options for insert mode completion
  if g:LSP_24x7_Complete
    setbufvar(bnr, '&completeopt', 'menuone,popup,noinsert,noselect')
    setbufvar(bnr, '&completepopup', 'border:off')
    # autocmd for 24x7 insert mode completion
    autocmd TextChangedI <buffer> call lsp#complete()
    # <Enter> in insert mode stops completion and inserts a <Enter>
    inoremap <expr> <buffer> <CR> pumvisible() ? "\<C-Y>\<CR>" : "\<CR>"
  else
    if s:lspOmniComplEnabled(ftype)
      setbufvar(bnr, '&omnifunc', 'lsp#omniFunc')
    endif
  endif

  setbufvar(bnr, '&balloonexpr', 'LspDiagExpr()')
  exe 'autocmd InsertLeave <buffer=' .. bnr .. '> call lsp#leftInsertMode()'

  # map characters that trigger signature help
  if g:LSP_Show_Signature && lspserver.caps->has_key('signatureHelpProvider')
    var triggers = lspserver.caps.signatureHelpProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch
				.. "<C-R>=lsp#showSignature()<CR>"
    endfor
  endif

  bufnrToServer[bnr] = lspserver
enddef

# Notify LSP server to remove a file
def lsp#removeFile(bnr: number): void
  if !bufnrToServer->has_key(bnr)
    # LSP server for this buffer is not running
    return
  endif

  var fname: string = bnr->bufname()
  var ftype: string = bnr->getbufvar('&filetype')
  if fname == '' || ftype == ''
    return
  endif
  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return
  endif
  lspserver.textdocDidClose(bnr)
  if lspserver.diagsMap->has_key(bnr)
    lspserver.diagsMap->remove(bnr)
  endif
  bufnrToServer->remove(bnr)
enddef

# Stop all the LSP servers
def lsp#stopAllServers()
  for lspserver in lspServers
    if lspserver.running
      lspserver.stopServer()
    endif
  endfor
enddef

# Register a LSP server for one or more file types
def lsp#addServer(serverList: list<dict<any>>)
  for server in serverList
    if !server->has_key('filetype') || !server->has_key('path') || !server->has_key('args')
      ErrMsg('Error: LSP server information is missing filetype or path or args')
      continue
    endif
    if !server->has_key('omnicompl')
      # Enable omni-completion by default
      server['omnicompl'] = v:true
    endif

    if !server.path->filereadable()
      ErrMsg('Error: LSP server ' .. server.path .. ' is not found')
      return
    endif
    if server.args->type() != v:t_list
      ErrMsg('Error: Arguments for LSP server ' .. server.args .. ' is not a List')
      return
    endif
    if server.omnicompl->type() != v:t_bool
      ErrMsg('Error: Setting of omnicompl ' .. server.omnicompl .. ' is not a Boolean')
      return
    endif

    var lspserver: dict<any> = NewLspServer(server.path, server.args)

    if server.filetype->type() == v:t_string
      s:lspAddServer(server.filetype, lspserver)
      s:lspOmniComplSet(server.filetype, server.omnicompl)
    elseif server.filetype->type() == v:t_list
      for ftype in server.filetype
        s:lspAddServer(ftype, lspserver)
        s:lspOmniComplSet(ftype, server.omnicompl)
      endfor
    else
      ErrMsg('Error: Unsupported file type information "' ..
		server.filetype->string() .. '" in LSP server registration')
      continue
    endif
  endfor
enddef

# set the LSP server trace level for the current buffer
# Params: SetTraceParams
def lsp#setTraceServer(traceVal: string)
  if ['off', 'message', 'verbose']->index(traceVal) == -1
    ErrMsg("Error: Unsupported LSP server trace value " .. traceVal)
    return
  endif

  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.setTrace(traceVal)
enddef

# Map the LSP DiagnosticSeverity to a quickfix type character
def s:lspDiagSevToQfType(severity: number): string
  var typeMap: list<string> = ['E', 'W', 'I', 'N']

  if severity > 4
    return ''
  endif

  return typeMap[severity - 1]
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a quickfix list
def lsp#showDiagnostics(): void
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname: string = expand('%:p')
  if fname == ''
    return
  endif
  var bnr: number = bufnr()

  if !lspserver.diagsMap->has_key(bnr) || lspserver.diagsMap[bnr]->empty()
    WarnMsg('No diagnostic messages found for ' .. fname)
    return
  endif

  var qflist: list<dict<any>> = []
  var text: string

  for [lnum, diag] in lspserver.diagsMap[bnr]->items()
    text = diag.message->substitute("\n\\+", "\n", 'g')
    qflist->add({'filename': fname,
		    'lnum': diag.range.start.line + 1,
		    'col': GetLineByteFromPos(bnr, diag.range.start) + 1,
		    'text': text,
		    'type': s:lspDiagSevToQfType(diag.severity)})
  endfor
  setloclist(0, [], ' ', {'title': 'Language Server Diagnostics',
							'items': qflist})
  :lopen
enddef

# Show the diagnostic message for the current line
def lsp#showCurrentDiag()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var bnr: number = bufnr()
  var lnum: number = line('.')
  var diag: dict<any> = lspserver.getDiagByLine(bnr, lnum)
  if diag->empty()
    WarnMsg('No diagnostic messages found for current line')
  else
    echo diag.message
  endif
enddef

# get the count of error in the current buffer
def lsp#errorCount():dict<number>
  var res = {'E': 0, 'W': 0, 'I': 0, 'H': 0}
  var ftype = &filetype
  if ftype == ''
    return res
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    return res
  endif
  if !lspserver.running
    return res
  endif

  var bnr: number = bufnr()
  if lspserver.diagsMap->has_key(bnr)
      for item in lspserver.diagsMap[bnr]->values()
          if item->has_key('severity')
              if item.severity == 1
                  res.E = res.E + 1
              elseif item.severity == 2
                  res.W = res.W + 1
              elseif item.severity == 3
                  res.I = res.I + 1
              elseif item.severity == 4
                  res.H = res.H + 1
              endif
          endif
      endfor
  endif

  return res
enddef

# sort the diaganostics messages for a buffer by line number
def s:getSortedDiagLines(lspserver: dict<any>, bnr: number): list<number>
  # create a list of line numbers from the diag map keys
  var lnums: list<number> =
		lspserver.diagsMap[bnr]->keys()->mapnew((_, v) => v->str2nr())
  return lnums->sort((a, b) => a - b)
enddef

# jump to the next/previous/first diagnostic message in the current buffer
def lsp#jumpToDiag(which: string): void
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname: string = expand('%:p')
  if fname == ''
    return
  endif
  var bnr: number = bufnr()

  if !lspserver.diagsMap->has_key(bnr) || lspserver.diagsMap[bnr]->empty()
    WarnMsg('No diagnostic messages found for ' .. fname)
    return
  endif

  # sort the diagnostics by line number
  var sortedDiags: list<number> = s:getSortedDiagLines(lspserver, bnr)

  if which == 'first'
    cursor(sortedDiags[0], 1)
    return
  endif

  # Find the entry just before the current line (binary search)
  var curlnum: number = line('.')
  for lnum in (which == 'next') ? sortedDiags : sortedDiags->reverse()
    if (which == 'next' && lnum > curlnum)
	  || (which == 'prev' && lnum < curlnum)
      cursor(lnum, 1)
      return
    endif
  endfor

  WarnMsg('Error: No more diagnostics found')
enddef

# Insert mode completion handler. Used when 24x7 completion is enabled
# (default).
def lsp#complete()
  var cur_col: number = col('.')
  var line: string = getline('.')

  if cur_col == 0 || line->empty()
    return
  endif

  var ftype: string = &filetype
  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running || lspserver.caps->empty()
    return
  endif

  # Trigger kind is 1 for 24x7 code complete or manual invocation
  var triggerKind: number = 1

  # If the character before the cursor is not a keyword character or is not
  # one of the LSP completion trigger characters, then do nothing.
  if line[cur_col - 2] !~ '\k'
    if lspserver.completionTriggerChars->index(line[cur_col - 2]) == -1
      return
    endif
    # completion triggered by one of the trigger characters
    triggerKind = 2
  endif

  # first send all the changes in the current buffer to the LSP server
  listener_flush()

  # initiate a request to LSP server to get list of completions
  lspserver.getCompletion(triggerKind)

  return
enddef

# omni complete handler
def lsp#omniFunc(findstart: number, base: string): any
  var ftype: string = &filetype
  var lspserver: dict<any> = s:lspGetServer(ftype)

  if findstart
    if lspserver->empty()
      ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
      return -2
    endif
    if !lspserver.running
      ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
      return -2
    endif

    # first send all the changes in the current buffer to the LSP server
    listener_flush()

    lspserver.completePending = v:true
    lspserver.completeItems = []
    # initiate a request to LSP server to get list of completions
    lspserver.getCompletion(1)

    # locate the start of the word
    var line = getline('.')
    var start = charcol('.') - 1
    while start > 0 && line[start - 1] =~ '\k'
      start -= 1
    endwhile
    return start
  else
    var count: number = 0
    while !complete_check() && lspserver.completePending
				&& count < 1000
      sleep 2m
      count += 1
    endwhile

    var res: list<dict<any>> = []
    for item in lspserver.completeItems
      res->add(item)
    endfor
    return res->empty() ? v:none : res
  endif
enddef

# Display the hover message from the LSP server for the current cursor
# location
def lsp#hover()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.hover()
enddef

# show symbol references
def lsp#showReferences()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.showReferences()
enddef

# highlight all the places where a symbol is referenced
def lsp#docHighlight()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.docHighlight()
enddef

# clear the symbol reference highlight
def lsp#docHighlightClear()
  prop_remove({'type': 'LspTextRef', 'all': true}, 1, line('$'))
  prop_remove({'type': 'LspReadRef', 'all': true}, 1, line('$'))
  prop_remove({'type': 'LspWriteRef', 'all': true}, 1, line('$'))
enddef

# jump to a symbol selected in the outline window
def s:outlineJumpToSymbol()
  var lnum: number = line('.') - 1
  if w:lspSymbols.lnumTable[lnum]->empty()
    return
  endif

  var slnum: number = w:lspSymbols.lnumTable[lnum].lnum
  var scol: number = w:lspSymbols.lnumTable[lnum].col
  var fname: string = w:lspSymbols.filename

  # Highlight the selected symbol
  prop_remove({type: 'LspOutlineHighlight'})
  var col: number = getline('.')->match('\S') + 1
  prop_add(line('.'), col, {type: 'LspOutlineHighlight',
			length: w:lspSymbols.lnumTable[lnum].name->len()})

  # disable the outline window refresh
  skipOutlineRefresh = true

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
  skipOutlineRefresh = false
enddef

var skipOutlineRefresh: bool = false

def s:addSymbolText(bnr: number,
			symbolTypeTable: dict<list<dict<any>>>,
			pfx: string,
			text: list<string>,
			lnumMap: list<dict<any>>,
			children: bool)
  var prefix: string = pfx .. '  '
  for [symType, symbols] in symbolTypeTable->items()
    if !children
      # Add an empty line for the top level symbol types. For types in the
      # children symbols, don't add the empty line.
      text->extend([''])
      lnumMap->extend([{}])
    endif
    if children
      text->extend([prefix .. symType])
      prefix ..= '  '
    else
      text->extend([symType])
    endif
    lnumMap->extend([{}])
    for s in symbols
      text->add(prefix .. s.name)
      # remember the line number for the symbol
      var start_col: number = GetLineByteFromPos(bnr, s.range.start) + 1
      lnumMap->add({name: s.name, lnum: s.range.start.line + 1,
			col: start_col})
      s.outlineLine = lnumMap->len()
      if s->has_key('children') && !s.children->empty()
	s:addSymbolText(bnr, s.children, prefix, text, lnumMap, true)
      endif
    endfor
  endfor
enddef

# update the symbols displayed in the outline window
def lsp#updateOutlineWindow(fname: string,
				symbolTypeTable: dict<list<dict<any>>>,
				symbolLineTable: list<dict<any>>)
  var wid: number = bufwinid('LSP-Outline')
  if wid == -1
    return
  endif

  # stop refreshing the outline window recursively
  skipOutlineRefresh = true

  var prevWinID: number = win_getid()
  wid->win_gotoid()

  # if the file displayed in the outline window is same as the new file, then
  # save and restore the cursor position
  var symbols = wid->getwinvar('lspSymbols', {})
  var saveCursor: list<number> = []
  if !symbols->empty() && symbols.filename == fname
    saveCursor = getcurpos()
  endif

  :setlocal modifiable
  :silent! :%d _
  setline(1, ['# LSP Outline View',
		'# ' .. fname->fnamemodify(':t') .. ' ('
				.. fname->fnamemodify(':h') .. ')'])

  # First two lines in the buffer display comment information
  var lnumMap: list<dict<any>> = [{}, {}]
  var text: list<string> = []
  s:addSymbolText(fname->bufnr(), symbolTypeTable, '', text, lnumMap, false)
  append('$', text)
  w:lspSymbols = {filename: fname, lnumTable: lnumMap,
				symbolsByLine: symbolLineTable}
  :setlocal nomodifiable

  if !saveCursor->empty()
    saveCursor->setpos('.')
  endif

  prevWinID->win_gotoid()

  # Highlight the current symbol
  s:outlineHighlightCurrentSymbol()

  # re-enable refreshing the outline window
  skipOutlineRefresh = false
enddef

def s:outlineHighlightCurrentSymbol()
  var fname: string = expand('%')->fnamemodify(':p')
  if fname == '' || &filetype == ''
    return
  endif

  var wid: number = bufwinid('LSP-Outline')
  if wid == -1
    return
  endif

  # Check whether the symbols for this file are displayed in the outline
  # window
  var lspSymbols = wid->getwinvar('lspSymbols', {})
  if lspSymbols->empty() || lspSymbols.filename != fname
    return
  endif

  var symbolTable: list<dict<any>> = lspSymbols.symbolsByLine

  # line number to locate the symbol
  var lnum: number = line('.')

  # Find the symbol for the current line number (binary search)
  var left: number = 0
  var right: number = symbolTable->len() - 1
  var mid: number
  while left <= right
    mid = (left + right) / 2
    if lnum >= (symbolTable[mid].range.start.line + 1) &&
		lnum <= (symbolTable[mid].range.end.line + 1)
      break
    endif
    if lnum > (symbolTable[mid].range.start.line + 1)
      left = mid + 1
    else
      right = mid - 1
    endif
  endwhile

  # clear the highlighting in the outline window
  var bnr: number = wid->winbufnr()
  prop_remove({bufnr: bnr, type: 'LspOutlineHighlight'})

  if left > right
    # symbol not found
    return
  endif

  # Highlight the selected symbol
  var col: number =
	match(getbufline(bnr, symbolTable[mid].outlineLine)[0], '\S') + 1
  prop_add(symbolTable[mid].outlineLine, col,
			{bufnr: bnr, type: 'LspOutlineHighlight',
			length: symbolTable[mid].name->len()})

  # if the line is not visible, then scroll the outline window to make the
  # line visible
  var wininfo = wid->getwininfo()
  if symbolTable[mid].outlineLine < wininfo[0].topline
			|| symbolTable[mid].outlineLine > wininfo[0].botline
    var cmd: string = 'call cursor(' ..
			symbolTable[mid].outlineLine .. ', 1) | normal z.'
    win_execute(wid, cmd)
  endif
enddef

# when the outline window is closed, do the cleanup
def s:outlineCleanup()
  # Remove the outline autocommands
  :silent! autocmd! LSPOutline

  :silent! syntax clear LSPTitle
enddef

# open the symbol outline window
def s:openOutlineWindow()
  var wid: number = bufwinid('LSP-Outline')
  if wid != -1
    return
  endif

  var prevWinID: number = win_getid()

  :topleft :20vnew LSP-Outline
  :setlocal modifiable
  :setlocal noreadonly
  :silent! :%d _
  :setlocal buftype=nofile
  :setlocal bufhidden=delete
  :setlocal noswapfile nobuflisted
  :setlocal nonumber norelativenumber fdc=0 nowrap winfixheight winfixwidth
  :setlocal shiftwidth=2
  :setlocal foldenable
  :setlocal foldcolumn=4
  :setlocal foldlevel=4
  :setlocal foldmethod=indent
  setline(1, ['# File Outline'])
  :nnoremap <silent> <buffer> q :quit<CR>
  :nnoremap <silent> <buffer> <CR> :call <SID>outlineJumpToSymbol()<CR>
  :setlocal nomodifiable

  # highlight all the symbol types
  :syntax keyword LSPTitle File Module Namespace Package Class Method Property
  :syntax keyword LSPTitle Field Constructor Enum Interface Function Variable
  :syntax keyword LSPTitle Constant String Number Boolean Array Object Key Null
  :syntax keyword LSPTitle EnumMember Struct Event Operator TypeParameter

  if str2nr(&t_Co) > 2
    highlight clear LSPTitle
    highlight default link LSPTitle Title
  endif

  prop_type_add('LspOutlineHighlight', {bufnr: bufnr(), highlight: 'Search'})

  augroup LSPOutline
    au!
    autocmd BufEnter * call s:requestDocSymbols()
    # when the outline window is closed, do the cleanup
    autocmd BufUnload LSP-Outline call s:outlineCleanup()
    autocmd CursorHold * call s:outlineHighlightCurrentSymbol()
  augroup END

  prevWinID->win_gotoid()
enddef

def s:requestDocSymbols()
  if skipOutlineRefresh
    return
  endif

  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    return
  endif
  if !lspserver.running || lspserver.caps->empty()
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.getDocSymbols(fname)
enddef

# open a window and display all the symbols in a file (outline)
def lsp#outline()
  s:openOutlineWindow()
  s:requestDocSymbols()
enddef

# Format the entire file
def lsp#textDocFormat(range_args: number, line1: number, line2: number)
  if !&modifiable
    ErrMsg('Error: Current file is not a modifiable file')
    return
  endif

  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  if range_args > 0
    lspserver.textDocFormat(fname, true, line1, line2)
  else
    lspserver.textDocFormat(fname, false, 0, 0)
  endif
enddef

# TODO: Add support for textDocument.onTypeFormatting?
# Will this slow down Vim?

# Display all the locations where the current symbol is called from.
# Uses LSP "callHierarchy/incomingCalls" request
def lsp#incomingCalls()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.incomingCalls(fname)
enddef

# Display all the symbols used by the current symbol.
# Uses LSP "callHierarchy/outgoingCalls" request
def lsp#outgoingCalls()
  :echomsg 'Error: Not implemented yet'
enddef

# Rename a symbol
# Uses LSP "textDocument/rename" request
def lsp#rename()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  var newName: string = input("Enter new name: ", expand('<cword>'))
  if newName == ''
    return
  endif

  lspserver.renameSymbol(newName)
enddef

# Perform a code action
# Uses LSP "textDocument/codeAction" request
def lsp#codeAction()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.codeAction(fname)
enddef

# Handle keys pressed when the workspace symbol popup menu is displayed
def s:filterSymbols(lspserver: dict<any>, popupID: number, key: string): bool
  var key_handled: bool = false
  var update_popup: bool = false
  var query: string = lspserver.workspaceSymbolQuery

  if key == "\<BS>" || key == "\<C-H>"
    # Erase one character from the filter text
    if query->len() >= 1
      query = query[: -2]
      update_popup = true
    endif
    key_handled = true
  elseif key == "\<C-U>"
    # clear the filter text
    query = ''
    update_popup = true
    key_handled = true
  elseif key == "\<C-F>"
        || key == "\<C-B>"
        || key == "\<PageUp>"
        || key == "\<PageDown>"
        || key == "\<C-Home>"
        || key == "\<C-End>"
        || key == "\<C-N>"
        || key == "\<C-P>"
    # scroll the popup window
    var cmd: string = 'normal! ' .. (key == "\<C-N>" ? 'j' : key == "\<C-P>" ? 'k' : key)
    win_execute(popupID, cmd)
    key_handled = true
  elseif key == "\<Up>" || key == "\<Down>"
    # Use native Vim handling for these keys
    key_handled = false
  elseif key =~ '^\f$' || key == "\<Space>"
    # Filter the names based on the typed key and keys typed before
    query ..= key
    update_popup = true
    key_handled = true
  endif

  if update_popup
    # Update the popup with the new list of symbol names
    popupID->popup_settext('')
    if query != ''
      lspserver.workspaceQuery(query)
    else
      []->setwinvar(popupID, 'LspSymbolTable')
    endif
    echo 'Symbol: ' .. query
  endif

  # Update the workspace symbol query string
  lspserver.workspaceSymbolQuery = query

  if key_handled
    return true
  endif

  return popupID->popup_filter_menu(key)
enddef

# Jump to the location of a symbol selected in the popup menu
def s:jumpToWorkspaceSymbol(popupID: number, result: number): void
  # clear the message displayed at the command-line
  echo ''

  if result <= 0
    # popup is canceled
    return
  endif

  var symTbl: list<dict<any>> = popupID->getwinvar('LspSymbolTable', [])
  if symTbl->empty()
    return
  endif
  try
    # Save the current location in the tag stack
    PushCursorToTagStack()

    # if the selected file is already present in a window, then jump to it
    var fname: string = symTbl[result - 1].file
    var winList: list<number> = fname->bufnr()->win_findbuf()
    if winList->len() == 0
      # Not present in any window
      if &modified || &buftype != ''
	# the current buffer is modified or is not a normal buffer, then open
	# the file in a new window
	exe "split " .. symTbl[result - 1].file
      else
	exe "confirm edit " .. symTbl[result - 1].file
      endif
    else
      winList[0]->win_gotoid()
    endif
    setcursorcharpos(symTbl[result - 1].pos.line + 1,
			symTbl[result - 1].pos.character + 1)
  catch
    # ignore exceptions
  endtry
enddef

# display a list of symbols from the workspace
def s:showSymbolMenu(lspserver: dict<any>, query: string)
  # Create the popup menu
  var lnum = &lines - &cmdheight - 2 - 10
  var popupAttr = {
      title: 'Workspace Symbol Search',
      wrap: 0,
      pos: 'topleft',
      line: lnum,
      col: 2,
      minwidth: 60,
      minheight: 10,
      maxheight: 10,
      maxwidth: 60,
      mapping: false,
      fixed: 1,
      close: "button",
      filter: function('s:filterSymbols', [lspserver]),
      callback: function('s:jumpToWorkspaceSymbol')
  }
  lspserver.workspaceSymbolPopup = popup_menu([], popupAttr)
  lspserver.workspaceSymbolQuery = query
  prop_type_add('lspworkspacesymbol',
			{bufnr: lspserver.workspaceSymbolPopup->winbufnr(),
			 highlight: 'Title'})
  echo 'Symbol: ' .. query
enddef

# Perform a workspace wide symbol lookup
# Uses LSP "workspace/symbol" request
def lsp#symbolSearch(queryArg: string)
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  var query: string = queryArg
  if query == ''
    query = input("Lookup symbol: ", expand('<cword>'))
    if query == ''
      return
    endif
  endif
  redraw!

  s:showSymbolMenu(lspserver, query)

  if !lspserver.workspaceQuery(query)
    lspserver.workspaceSymbolPopup->popup_close()
  endif
enddef

# Display the list of workspace folders
def lsp#listWorkspaceFolders()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  echomsg 'Workspace Folders: ' .. lspserver.workspaceFolders->string()
enddef

# Add a workspace folder. Default is to use the current folder.
def lsp#addWorkspaceFolder(dirArg: string)
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var dirName: string = dirArg
  if dirName == ''
    dirName = input("Add Workspace Folder: ", getcwd(), 'dir')
    if dirName == ''
      return
    endif
  endif
  :redraw!
  if !dirName->isdirectory()
    ErrMsg('Error: ' .. dirName .. ' is not a directory')
    return
  endif

  lspserver.addWorkspaceFolder(dirName)
enddef

# Remove a workspace folder. Default is to use the current folder.
def lsp#removeWorkspaceFolder(dirArg: string)
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var dirName: string = dirArg
  if dirName == ''
    dirName = input("Remove Workspace Folder: ", getcwd(), 'dir')
    if dirName == ''
      return
    endif
  endif
  :redraw!
  if !dirName->isdirectory()
    ErrMsg('Error: ' .. dirName .. ' is not a directory')
    return
  endif

  lspserver.removeWorkspaceFolder(dirName)
enddef

# visually select a range of positions around the current cursor.
def lsp#selectionRange()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  # TODO: Also support passing a range
  lspserver.selectionRange(fname)
enddef

# fold the entire document
def lsp#foldDocument()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  if &foldmethod != 'manual'
    ErrMsg("Error: Only works when 'foldmethod' is 'manual'")
    return
  endif

  lspserver.foldRange(fname)
enddef

# vim: shiftwidth=2 softtabstop=2
