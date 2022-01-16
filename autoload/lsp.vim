vim9script

# Vim9 LSP client

# Needs Vim 8.2.2342 and higher
if v:version < 802 || !has('patch-8.2.2342')
  finish
endif

var opt = {}
var lserver = {}
var util = {}
var diag = {}
var symbol = {}
var outline = {}

if has('patch-8.2.4019')
  import './lspoptions.vim' as opt_import
  import './lspserver.vim' as server_import
  import './util.vim' as util_import
  import './diag.vim' as diag_import
  import './symbol.vim' as symbol_import
  import './outline.vim' as outline_import

  opt.LspOptionsSet = opt_import.LspOptionsSet
  opt.lspOptions = opt_import.lspOptions
  lserver.NewLspServer = server_import.NewLspServer
  util.WarnMsg = util_import.WarnMsg
  util.ErrMsg = util_import.ErrMsg
  util.ServerTrace = util_import.ServerTrace
  util.ClearTraceLogs = util_import.ClearTraceLogs
  util.GetLineByteFromPos = util_import.GetLineByteFromPos
  util.PushCursorToTagStack = util_import.PushCursorToTagStack
  diag.UpdateDiags = diag_import.UpdateDiags
  diag.DiagsGetErrorCount = diag_import.DiagsGetErrorCount
  diag.ShowAllDiags = diag_import.ShowAllDiags
  diag.ShowCurrentDiag = diag_import.ShowCurrentDiag
  diag.LspDiagsJump = diag_import.LspDiagsJump
  diag.DiagRemoveFile = diag_import.DiagRemoveFile
  symbol.ShowSymbolMenu = symbol_import.ShowSymbolMenu
  outline.OpenOutlineWindow = outline_import.OpenOutlineWindow
  outline.SkipOutlineRefresh = outline_import.SkipOutlineRefresh
else
  import {lspOptions, LspOptionsSet} from './lspoptions.vim'
  import NewLspServer from './lspserver.vim'
  import {WarnMsg,
        ErrMsg,
        ServerTrace,
        ClearTraceLogs,
        GetLineByteFromPos,
        PushCursorToTagStack} from './util.vim'
  import {DiagRemoveFile,
	UpdateDiags,
	DiagsGetErrorCount,
	ShowAllDiags,
	ShowCurrentDiag,
	LspDiagsJump} from './diag.vim'
  import ShowSymbolMenu from './symbol.vim'
  import {OpenOutlineWindow, SkipOutlineRefresh} from './outline.vim'

  opt.LspOptionsSet = LspOptionsSet
  opt.lspOptions = lspOptions
  lserver.NewLspServer = NewLspServer
  util.WarnMsg = WarnMsg
  util.ErrMsg = ErrMsg
  util.ServerTrace = ServerTrace
  util.ClearTraceLogs = ClearTraceLogs
  util.GetLineByteFromPos = GetLineByteFromPos
  util.PushCursorToTagStack = PushCursorToTagStack
  diag.DiagRemoveFile = DiagRemoveFile
  diag.UpdateDiags = UpdateDiags
  diag.DiagsGetErrorCount = DiagsGetErrorCount
  diag.ShowAllDiags = ShowAllDiags
  diag.ShowCurrentDiag = ShowCurrentDiag
  diag.LspDiagsJump = LspDiagsJump
  symbol.ShowSymbolMenu = ShowSymbolMenu
  outline.OpenOutlineWindow = OpenOutlineWindow
  outline.SkipOutlineRefresh = SkipOutlineRefresh
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

# Set user configurable LSP options
def lsp#setOptions(lspOpts: dict<any>)
  opt.LspOptionsSet(lspOpts)
enddef

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
def s:lspAddServer(ftype: string, lspsrv: dict<any>)
  ftypeServerMap->extend({[ftype]: lspsrv})
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
  util.ClearTraceLogs()
  util.ServerTrace(true)
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
def lsp#gotoDefinition(peek: bool)
  var ftype: string = &filetype
  if ftype == '' || @% == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoDefinition(peek)
enddef

# Go to a declaration using "textDocument/declaration" LSP request
def lsp#gotoDeclaration(peek: bool)
  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoDeclaration(peek)
enddef

# Go to a type definition using "textDocument/typeDefinition" LSP request
def lsp#gotoTypedef(peek: bool)
  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoTypeDef(peek)
enddef

# Go to a implementation using "textDocument/implementation" LSP request
def lsp#gotoImplementation(peek: bool)
  var ftype: string = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.gotoImplementation(peek)
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return ''
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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

  # Display the diagnostic message only if the mouse is over the first two
  # columns
  if v:beval_col >= 3
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
  diag.UpdateDiags(lspserver, bufnr())
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

  # add a listener to track changes to this buffer
  listener_add(function('lsp#bufchange_listener'), bnr)

  # set options for insert mode completion
  if opt.lspOptions.autoComplete
    setbufvar(bnr, '&completeopt', 'menuone,popup,noinsert,noselect')
    setbufvar(bnr, '&completepopup', 'border:off')
    # <Enter> in insert mode stops completion and inserts a <Enter>
    inoremap <expr> <buffer> <CR> pumvisible() ? "\<C-Y>\<CR>" : "\<CR>"
  else
    if s:lspOmniComplEnabled(ftype)
      setbufvar(bnr, '&omnifunc', 'lsp#omniFunc')
    endif
  endif

  setbufvar(bnr, '&balloonexpr', 'LspDiagExpr()')

  # map characters that trigger signature help
  if opt.lspOptions.showSignature &&
			lspserver.caps->has_key('signatureHelpProvider')
    var triggers = lspserver.caps.signatureHelpProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch
				.. "<C-R>=lsp#showSignature()<CR>"
    endfor
  endif

  # Set buffer local autocmds
  augroup LSPBufferAutocmds
    # file saved notification handler
    exe 'autocmd BufWritePost <buffer=' .. bnr .. '> call s:lspSavedFile()'

    if opt.lspOptions.autoComplete
      # Trigger 24x7 insert mode completion when text is changed
      exe 'autocmd TextChangedI <buffer=' .. bnr .. '> call lsp#complete()'
    endif

    # Update the diagnostics when insert mode is stopped
    exe 'autocmd InsertLeave <buffer=' .. bnr .. '> call lsp#leftInsertMode()'

    if opt.lspOptions.autoHighlight &&
			lspserver.caps->has_key('documentHighlightProvider')
			&& lspserver.caps.documentHighlightProvider
      # Highlight all the occurrences of the current keyword
      exe 'autocmd CursorMoved <buffer=' .. bnr .. '> '
		  .. 'call lsp#docHighlightClear() | call lsp#docHighlight()'
    endif
  augroup END

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
  diag.DiagRemoveFile(lspserver, bnr)
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
      util.ErrMsg('Error: LSP server information is missing filetype or path or args')
      continue
    endif
    if !server->has_key('omnicompl')
      # Enable omni-completion by default
      server['omnicompl'] = v:true
    endif

    if !executable(server.path)
      util.ErrMsg('Error: LSP server ' .. server.path .. ' is not found')
      return
    endif
    if server.args->type() != v:t_list
      util.ErrMsg('Error: Arguments for LSP server ' .. server.args .. ' is not a List')
      return
    endif
    if server.omnicompl->type() != v:t_bool
      util.ErrMsg('Error: Setting of omnicompl ' .. server.omnicompl .. ' is not a Boolean')
      return
    endif

    var lspserver: dict<any> = lserver.NewLspServer(server.path, server.args)

    if server.filetype->type() == v:t_string
      s:lspAddServer(server.filetype, lspserver)
      s:lspOmniComplSet(server.filetype, server.omnicompl)
    elseif server.filetype->type() == v:t_list
      for ftype in server.filetype
        s:lspAddServer(ftype, lspserver)
        s:lspOmniComplSet(ftype, server.omnicompl)
      endfor
    else
      util.ErrMsg('Error: Unsupported file type information "' ..
		server.filetype->string() .. '" in LSP server registration')
      continue
    endif
  endfor
enddef

# set the LSP server trace level for the current buffer
# Params: SetTraceParams
def lsp#setTraceServer(traceVal: string)
  if ['off', 'message', 'verbose']->index(traceVal) == -1
    util.ErrMsg("Error: Unsupported LSP server trace value " .. traceVal)
    return
  endif

  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  lspserver.setTrace(traceVal)
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a quickfix list
def lsp#showDiagnostics(): void
  var ftype = &filetype
  if ftype == '' || @% == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  diag.ShowAllDiags(lspserver)
enddef

# Show the diagnostic message for the current line
def lsp#showCurrentDiag()
  var ftype = &filetype
  if ftype == '' || @% == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  diag.ShowCurrentDiag(lspserver)
enddef

# get the count of error in the current buffer
def lsp#errorCount(): dict<number>
  var res = {'Error': 0, 'Warn': 0, 'Info': 0, 'Hint': 0}
  var ftype = &filetype
  if ftype == ''
    return res
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return res
  endif

  return diag.DiagsGetErrorCount(lspserver)
enddef

# jump to the next/previous/first diagnostic message in the current buffer
def lsp#jumpToDiag(which: string): void
  var ftype = &filetype
  if ftype == '' || @% == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  diag.LspDiagsJump(lspserver, which)
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
      util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
      return -2
    endif
    if !lspserver.running
      util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
def lsp#showReferences(peek: bool)
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.showReferences(peek)
enddef

# highlight all the places where a symbol is referenced
def lsp#docHighlight()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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

def lsp#requestDocSymbols()
  if outline.SkipOutlineRefresh()
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
  outline.OpenOutlineWindow()
  lsp#requestDocSymbols()
enddef

# Format the entire file
def lsp#textDocFormat(range_args: number, line1: number, line2: number)
  if !&modifiable
    util.ErrMsg('Error: Current file is not a modifiable file')
    return
  endif

  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  var newName: string = input("Rename symbol: ", expand('<cword>'))
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  lspserver.codeAction(fname)
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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

  symbol.ShowSymbolMenu(lspserver, query)

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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
    util.ErrMsg('Error: ' .. dirName .. ' is not a directory')
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
    util.ErrMsg('Error: ' .. dirName .. ' is not a directory')
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
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
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not found')
    return
  endif
  if !lspserver.running
    util.ErrMsg('Error: LSP server for "' .. ftype .. '" filetype is not running')
    return
  endif

  var fname = @%
  if fname == ''
    return
  endif

  if &foldmethod != 'manual'
    util.ErrMsg("Error: Only works when 'foldmethod' is 'manual'")
    return
  endif

  lspserver.foldRange(fname)
enddef

# vim: shiftwidth=2 softtabstop=2
