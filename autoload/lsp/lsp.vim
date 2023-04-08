vim9script

# Vim9 LSP client
#
# The functions called by plugin/lsp.vim are in this file.

# Needs Vim 9.0 and higher
if v:version < 900
  finish
endif

import './options.vim' as opt
import './lspserver.vim' as lserver
import './util.vim'
import './buffer.vim' as buf
import './completion.vim'
import './textedit.vim'
import './diag.vim'
import './symbol.vim'
import './outline.vim'
import './signature.vim'
import './codeaction.vim'
import './inlayhints.vim'

# LSP server information
var lspServers: list<dict<any>> = []

# filetype to LSP server map
var ftypeServerMap: dict<dict<any>> = {}

var lspInitializedOnce = false

def LspInitOnce()
  prop_type_add('LspTextRef', {highlight: 'Search', override: true})
  prop_type_add('LspReadRef', {highlight: 'DiffChange', override: true})
  prop_type_add('LspWriteRef', {highlight: 'DiffDelete', override: true})

  diag.InitOnce()
  inlayhints.InitOnce()
  signature.InitOnce()

  :set ballooneval balloonevalterm
  lspInitializedOnce = true
enddef

# Returns the LSP server for the a specific filetype. Returns an empty dict if
# the server is not found.
def LspGetServer(ftype: string): dict<any>
  return ftypeServerMap->get(ftype, {})
enddef

# Add a LSP server for a filetype
def LspAddServer(ftype: string, lspsrv: dict<any>)
  ftypeServerMap->extend({[ftype]: lspsrv})
enddef

# Enable/disable the logging of the language server protocol messages
export def ServerDebug(arg: string)
  if arg !=? 'errors' && arg !=? 'messages' && arg !=? 'on' && arg !=? 'off'
    util.ErrMsg($'Error: Invalid argument ("{arg}") for LSP server debug')
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty()
    return
  endif

  if arg ==? 'on'
    util.ClearTraceLogs(lspserver.logfile)
    util.ClearTraceLogs(lspserver.errfile)
    lspserver.debug = true
  elseif arg ==? 'off'
    lspserver.debug = false
  elseif arg ==? 'messages'
    util.ServerMessagesShow(lspserver.logfile)
  else
    util.ServerMessagesShow(lspserver.errfile)
  endif
enddef

# Show information about all the LSP servers
export def ShowAllServers()
  var lines = []
  # Add filetype to server mapping information
  lines->add('Filetype Information')
  lines->add('====================')
  for [ftype, lspserver] in ftypeServerMap->items()
    lines->add($"Filetype: '{ftype}'")
    lines->add($"Server Path: '{lspserver.path}'")
    lines->add($"Status: {lspserver.running ? 'Running' : 'Not running'}")
    lines->add('')
  endfor

  # Add buffer to server mapping information
  lines->add('Buffer Information')
  lines->add('==================')
  for bnr in range(1, bufnr('$'))
    if buf.BufHasLspServer(bnr)
      lines->add($"Buffer: '{bufname(bnr)}'")
      var lspserver = buf.BufLspServerGet(bnr)
      lines->add($"Server Path: '{lspserver.path}'")
      lines->add($"Status: {lspserver.running ? 'Running' : 'Not running'}")
      lines->add('')
    endif
  endfor

  var wid = bufwinid('Language-Servers')
  if wid != -1
    wid->win_gotoid()
    :setlocal modifiable
    :silent! :%d _
  else
    :new Language-Servers
    :setlocal buftype=nofile
    :setlocal bufhidden=wipe
    :setlocal noswapfile
    :setlocal nonumber nornu
    :setlocal fdc=0 signcolumn=no
  endif
  setline(1, lines)
  :setlocal nomodified
  :setlocal nomodifiable
enddef

# Show the status of the LSP server for the current buffer
export def ShowServer()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    :echomsg "LSP Server not found"
    return
  endif

  var msg = $"LSP server '{lspserver.path}' is "
  if lspserver.running
    msg ..= 'running'
  else
    msg ..= 'not running'
  endif
  :echomsg msg
enddef

# Get LSP server running status for filetype 'ftype'
# Return true if running, or false if not found or not running
export def ServerRunning(ftype: string): bool
  for [ft, lspserver] in ftypeServerMap->items()
    if ftype ==# ft
      return lspserver.running
    endif
  endfor
  return v:false
enddef

# Go to a definition using "textDocument/definition" LSP request
export def GotoDefinition(peek: bool, cmdmods: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.gotoDefinition(peek, cmdmods)
enddef

# Go to a declaration using "textDocument/declaration" LSP request
export def GotoDeclaration(peek: bool, cmdmods: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.gotoDeclaration(peek, cmdmods)
enddef

# Go to a type definition using "textDocument/typeDefinition" LSP request
export def GotoTypedef(peek: bool, cmdmods: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.gotoTypeDef(peek, cmdmods)
enddef

# Go to a implementation using "textDocument/implementation" LSP request
export def GotoImplementation(peek: bool, cmdmods: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.gotoImplementation(peek, cmdmods)
enddef

# Switch source header using "textDocument/switchSourceHeader" LSP request
# (Clangd specifc extension)
export def SwitchSourceHeader()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.switchSourceHeader()
enddef

# Show the signature using "textDocument/signatureHelp" LSP method
# Invoked from an insert-mode mapping, so return an empty string.
def g:LspShowSignature(): string
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return ''
  endif

  # first send all the changes in the current buffer to the LSP server
  listener_flush()
  lspserver.showSignature()
  return ''
enddef

# buffer change notification listener
def Bufchange_listener(bnr: number, start: number, end: number, added: number, changes: list<dict<number>>)
  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running
    return
  endif

  lspserver.textdocDidChange(bnr, start, end, added, changes)
enddef

# A buffer is saved. Send the "textDocument/didSave" LSP notification
def LspSavedFile()
  var bnr: number = expand('<abuf>')->str2nr()
  var lspserver: dict<any> = buf.BufLspServerGet(bnr)
  if lspserver->empty() || !lspserver.running
    return
  endif

  lspserver.didSaveFile(bnr)
enddef

# Return the diagnostic text from the LSP server for the current mouse line to
# display in a balloon
var lspDiagPopupID: number = 0
var lspDiagPopupInfo: dict<any> = {}
def g:LspDiagExpr(): any
  var lspserver: dict<any> = buf.BufLspServerGet(v:beval_bufnr)
  if lspserver->empty() || !lspserver.running
    return ''
  endif

  # Display the diagnostic message only if the mouse is over the gutter for
  # the signs.
  if opt.lspOptions.noDiagHoverOnLine && v:beval_col >= 2
    return ''
  endif

  var diagsInfo: list<dict<any>> = lspserver.getDiagsByLine(
    v:beval_bufnr,
    v:beval_lnum
  )
  if diagsInfo->empty()
    # No diagnostic for the current cursor location
    return ''
  endif

  # Include all diagnostics from the current line in the message
  var message: list<string> = []
  for diag in diagsInfo
    message->extend(diag.message->split("\n"))
  endfor

  return message
enddef

# Called after leaving insert mode. Used to process diag messages (if any)
def LspLeftInsertMode()
  if !exists('b:LspDiagsUpdatePending')
    return
  endif
  :unlet b:LspDiagsUpdatePending

  var bnr: number = bufnr()
  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running
    return
  endif
  diag.ProcessNewDiags(lspserver, bnr)
enddef

# Add buffer-local autocmds when attaching a LSP server to a buffer
def AddBufLocalAutocmds(lspserver: dict<any>, bnr: number): void
  var acmds: list<dict<any>> = []

  # file saved notification handler
  acmds->add({bufnr: bnr,
	      event: 'BufWritePost',
	      group: 'LSPBufferAutocmds',
	      cmd: 'LspSavedFile()'})

  # Update the diagnostics when insert mode is stopped
  acmds->add({bufnr: bnr,
	      event: 'InsertLeave',
	      group: 'LSPBufferAutocmds',
	      cmd: 'LspLeftInsertMode()'})

  # Auto highlight all the occurrences of the current keyword
  if opt.lspOptions.autoHighlight &&
			lspserver.isDocumentHighlightProvider
    acmds->add({bufnr: bnr,
		event: 'CursorMoved',
		group: 'LSPBufferAutocmds',
		cmd: 'call LspDocHighlightClear() | call LspDocHighlight()'})
  endif

  # Show diagnostics on the status line
  if opt.lspOptions.showDiagOnStatusLine
    acmds->add({bufnr: bnr,
		event: 'CursorMoved',
		group: 'LSPBufferAutocmds',
		cmd: 'LspShowCurrentDiagInStatusLine()'})
  endif

  autocmd_add(acmds)
enddef

def BufferInit(bnr: number): void
  var lspserver: dict<any> = buf.BufLspServerGet(bnr)
  if lspserver->empty() || !lspserver.running
    return
  endif

  var ftype: string = bnr->getbufvar('&filetype')
  lspserver.textdocDidOpen(bnr, ftype)

  # add a listener to track changes to this buffer
  listener_add(Bufchange_listener, bnr)

  AddBufLocalAutocmds(lspserver, bnr)

  setbufvar(bnr, '&balloonexpr', 'g:LspDiagExpr()')

  completion.BufferInit(lspserver, bnr, ftype)
  signature.BufferInit(lspserver)
  inlayhints.BufferInit(lspserver, bnr)

  if exists('#User#LspAttached')
    doautocmd <nomodeline> User LspAttached
  endif
enddef

# A new buffer is opened. If LSP is supported for this buffer, then add it
export def AddFile(bnr: number): void
  if buf.BufHasLspServer(bnr)
    # LSP server for this buffer is already initialized and running
    return
  endif

  # Skip remote files
  if util.LspUriRemote(bnr->bufname()->fnamemodify(':p'))
    return
  endif

  var ftype: string = bnr->getbufvar('&filetype')
  if ftype == ''
    return
  endif
  var lspserver: dict<any> = LspGetServer(ftype)
  if lspserver->empty()
    return
  endif
  if !lspserver.running
    if !lspInitializedOnce
      LspInitOnce()
    endif
    lspserver.startServer(bnr)
  endif
  buf.BufLspServerSet(bnr, lspserver)

  if lspserver.ready
    BufferInit(bnr)
  else
    augroup LSPBufferAutocmds
      exe $'autocmd User LspServerReady{lspserver.name} ++once BufferInit({bnr})'
    augroup END
  endif

enddef

# Notify LSP server to remove a file
export def RemoveFile(bnr: number): void
  var lspserver: dict<any> = buf.BufLspServerGet(bnr)
  if lspserver->empty()
    return
  endif
  if lspserver.running
    lspserver.textdocDidClose(bnr)
  endif
  diag.DiagRemoveFile(lspserver, bnr)
  buf.BufLspServerRemove(bnr)
enddef

# Stop all the LSP servers
export def StopAllServers()
  for lspserver in lspServers
    if lspserver.running
      lspserver.stopServer()
    endif
  endfor
enddef

# Add all the buffers with 'filetype' set to "ftype" to the language server.
def AddBuffersToLsp(ftype: string)
  # Add all the buffers with the same file type as the current buffer
  for binfo in getbufinfo({bufloaded: 1})
    if binfo.bufnr->getbufvar('&filetype') == ftype
      AddFile(binfo.bufnr)
    endif
  endfor
enddef

# Restart the LSP server for the current buffer
export def RestartServer()
  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty()
    return
  endif

  # Stop the server (if running)
  if lspserver.running
    lspserver.stopServer()
  endif

  # Remove all the buffers with the same file type as the current buffer
  var ftype: string = &filetype
  for binfo in getbufinfo()
    if binfo.bufnr->getbufvar('&filetype') == ftype
      RemoveFile(binfo.bufnr)
    endif
  endfor

  # Start the server again
  lspserver.startServer(bufnr(''))

  AddBuffersToLsp(ftype)
enddef

# Add the LSP server for files with 'filetype' as "ftype".
def AddServerForFiltype(lspserver: dict<any>, ftype: string, omnicompl: bool)
  LspAddServer(ftype, lspserver)
  completion.OmniComplSet(ftype, omnicompl)

  # If a buffer of this file type is already present, then send it to the LSP
  # server now.
  AddBuffersToLsp(ftype)
enddef

# Register a LSP server for one or more file types
export def AddServer(serverList: list<dict<any>>)
  for server in serverList
    if !server->has_key('filetype') || !server->has_key('path')
      util.ErrMsg('Error: LSP server information is missing filetype or path')
      continue
    endif
    if !server->has_key('omnicompl')
      # Enable omni-completion by default
      server['omnicompl'] = v:true
    endif

    if !server.path->executable()
      if !opt.lspOptions.ignoreMissingServer
        util.ErrMsg($'Error: LSP server {server.path} is not found')
      endif
      return
    endif
    var args: list<string> = []
    if server->has_key('args')
      if server.args->type() != v:t_list
        util.ErrMsg($'Error: Arguments for LSP server {server.args} is not a List')
        return
      endif
      args = server.args
    endif

    var initializationOptions: dict<any> = {}
    if server->has_key('initializationOptions')
      initializationOptions = server.initializationOptions
    endif

    var customNotificationHandlers: dict<func> = {}
    if server->has_key('customNotificationHandlers')
      customNotificationHandlers = server.customNotificationHandlers
    endif

    if server.omnicompl->type() != v:t_bool
      util.ErrMsg($'Error: Setting of omnicompl {server.omnicompl} is not a Boolean')
      return
    endif

    if !server->has_key('syncInit')
      server.syncInit = v:false
    endif

    if !server->has_key('name') || server.name->type() != v:t_string
							|| server.name == ''
      # Use the executable name (without the extension) as the language server
      # name.
      server.name = server.path->fnamemodify(':t:r')
    endif

    if !server->has_key('debug') || server.debug->type() != v:t_bool
      server.debug = false
    endif

    if !server->has_key('workspaceConfig')
      server.workspaceConfig = {}
    endif

    if !server->has_key('rootSearch') || server.rootSearch->type() != v:t_list
      server.rootSearch = []
    endif

    var lspserver: dict<any> = lserver.NewLspServer(server.name, server.path,
						    args, server.syncInit,
						    initializationOptions,
						    server.workspaceConfig,
						    server.rootSearch,
						    customNotificationHandlers,
						    server.debug)

    var ftypes = server.filetype
    if ftypes->type() == v:t_string
      AddServerForFiltype(lspserver, ftypes, server.omnicompl)
    elseif ftypes->type() == v:t_list
      for ftype in ftypes
	AddServerForFiltype(lspserver, ftype, server.omnicompl)
      endfor
    else
      util.ErrMsg($'Error: Unsupported file type information "{ftypes->string()}" in LSP server registration')
      continue
    endif
  endfor
enddef

# The LSP server is considered ready when the server capabilities are
# received ('initialize' LSP reply message)
export def ServerReady(): bool
  var fname: string = @%
  if fname == ''
    return false
  endif

  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty()
    return false
  endif
  return lspserver.ready
enddef

# set the LSP server trace level for the current buffer
# Params: SetTraceParams
export def ServerTraceSet(traceVal: string)
  if ['off', 'messages', 'verbose']->index(traceVal) == -1
    util.ErrMsg($'Error: Unsupported LSP server trace value {traceVal}')
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.setTrace(traceVal)
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a quickfix list
export def ShowDiagnostics(): void
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  diag.ShowAllDiags(lspserver)
enddef

# Show the diagnostic message for the current line
export def LspShowCurrentDiag(atPos: bool)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  diag.ShowCurrentDiag(lspserver, atPos)
enddef

# Display the diagnostics for the current line in the status line.
export def LspShowCurrentDiagInStatusLine()
  var fname: string = @%
  if fname == ''
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running
    return
  endif

  diag.ShowCurrentDiagInStatusLine(lspserver)
enddef

# get the count of diagnostics in the current buffer
export def ErrorCount(): dict<number>
  var res = {Error: 0, Warn: 0, Info: 0, Hint: 0}
  var fname: string = @%
  if fname == ''
    return res
  endif

  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running
    return res
  endif

  return diag.DiagsGetErrorCount(lspserver)
enddef

# jump to the next/previous/first diagnostic message in the current buffer
export def JumpToDiag(which: string, count: number = 0): void
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  diag.LspDiagsJump(lspserver, which, count)
enddef

# Display the hover message from the LSP server for the current cursor
# location
export def Hover()
  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  lspserver.hover()
enddef

# show symbol references
export def ShowReferences(peek: bool)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.showReferences(peek)
enddef

# highlight all the places where a symbol is referenced
def g:LspDocHighlight()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.docHighlight()
enddef

# clear the symbol reference highlight
def g:LspDocHighlightClear()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  if has('patch-9.0.0233')
    prop_remove({types: ['LspTextRef', 'LspReadRef', 'LspWriteRef'], all: true})
  else
    prop_remove({type: 'LspTextRef', all: true})
    prop_remove({type: 'LspReadRef', all: true})
    prop_remove({type: 'LspWriteRef', all: true})
  endif
enddef

def g:LspRequestDocSymbols()
  if outline.SkipOutlineRefresh()
    return
  endif

  var fname: string = @%
  if fname == ''
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  lspserver.getDocSymbols(fname)
enddef

# open a window and display all the symbols in a file (outline)
export def Outline()
  outline.OpenOutlineWindow()
  g:LspRequestDocSymbols()
enddef

# Format the entire file
export def TextDocFormat(range_args: number, line1: number, line2: number)
  if !&modifiable
    util.ErrMsg('Error: Current file is not a modifiable file')
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var fname: string = @%
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
export def IncomingCalls()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.incomingCalls(@%)
enddef

# Display all the symbols used by the current symbol.
# Uses LSP "callHierarchy/outgoingCalls" request
export def OutgoingCalls()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.outgoingCalls(@%)
enddef

# Display the type hierarchy for the current symbol.  Direction is 0 for
# sub types and 1 for super types.
export def TypeHierarchy(direction: number)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.typeHierarchy(direction)
enddef

# Rename a symbol
# Uses LSP "textDocument/rename" request
export def Rename(a_newName: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var newName: string = a_newName
  if newName == ''
    var sym: string = expand('<cword>')
    newName = input($"Rename symbol '{sym}' to: ", sym)
    if newName == ''
      return
    endif

    # clear the input prompt
    :echo "\r"
  endif

  lspserver.renameSymbol(newName)
enddef

# Perform a code action
# Uses LSP "textDocument/codeAction" request
export def CodeAction(line1: number, line2: number, query: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var fname: string = @%
  lspserver.codeAction(fname, line1, line2, query)
enddef

# Code lens
# Uses LSP "textDocument/codeLens" request
export def CodeLens()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.codeLens(@%)
enddef

# Perform a workspace wide symbol lookup
# Uses LSP "workspace/symbol" request
export def SymbolSearch(queryArg: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var query: string = queryArg
  if query == ''
    query = input('Lookup symbol: ', expand('<cword>'))
    if query == ''
      return
    endif
  endif
  :redraw!

  lspserver.workspaceQuery(query)
enddef

# Display the list of workspace folders
export def ListWorkspaceFolders()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  :echomsg $'Workspace Folders: {lspserver.workspaceFolders->string()}'
enddef

# Add a workspace folder. Default is to use the current folder.
export def AddWorkspaceFolder(dirArg: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var dirName: string = dirArg
  if dirName == ''
    dirName = input('Add Workspace Folder: ', getcwd(), 'dir')
    if dirName == ''
      return
    endif
  endif
  :redraw!
  if !dirName->isdirectory()
    util.ErrMsg($'Error: {dirName} is not a directory')
    return
  endif

  lspserver.addWorkspaceFolder(dirName)
enddef

# Remove a workspace folder. Default is to use the current folder.
export def RemoveWorkspaceFolder(dirArg: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var dirName: string = dirArg
  if dirName == ''
    dirName = input('Remove Workspace Folder: ', getcwd(), 'dir')
    if dirName == ''
      return
    endif
  endif
  :redraw!
  if !dirName->isdirectory()
    util.ErrMsg($'Error: {dirName} is not a directory')
    return
  endif

  lspserver.removeWorkspaceFolder(dirName)
enddef

# expand the previous selection or start a new selection
export def SelectionExpand()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.selectionExpand()
enddef

# shrink the previous selection or start a new selection
export def SelectionShrink()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.selectionShrink()
enddef

# fold the entire document
export def FoldDocument()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  if &foldmethod != 'manual'
    util.ErrMsg("Error: Only works when 'foldmethod' is 'manual'")
    return
  endif

  var fname: string = @%
  lspserver.foldRange(fname)
enddef

# Enable diagnostic highlighting for all the buffers
export def DiagHighlightEnable()
  diag.DiagsHighlightEnable()
enddef

# Disable diagnostic highlighting for all the buffers
export def DiagHighlightDisable()
  diag.DiagsHighlightDisable()
enddef

# Display the LSP server capabilities
export def ShowServerCapabilities()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  lspserver.showCapabilities()
enddef

# Function to use with the 'tagfunc' option.
export def TagFunc(pat: string, flags: string, info: dict<any>): any
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return v:null
  endif

  return lspserver.tagFunc(pat, flags, info)
enddef

# Function to use with the 'formatexpr' option.
export def FormatExpr(): number
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return 1
  endif

  lspserver.textDocFormat(@%, true, v:lnum, v:lnum + v:count - 1)
  return 0
enddef

export def RegisterCmdHandler(cmd: string, Handler: func)
  codeaction.RegisterCmdHandler(cmd, Handler)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
