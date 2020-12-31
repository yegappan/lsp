vim9script

# Vim9 LSP client

import NewLspServer from './lspserver.vim'
import {WarnMsg, ErrMsg, lsp_server_trace} from './util.vim'

# Needs Vim 8.2.2082 and higher
if v:version < 802 || !has('patch-8.2.2082')
  finish
endif

# LSP server information
var lspServers: list<dict<any>> = []

# filetype to LSP server map
var ftypeServerMap: dict<dict<any>> = {}

# Buffer number to LSP server map
var bufnrToServer: dict<dict<any>> = {}

# List of diagnostics for each opened file
#var diagsMap: dict<dict<any>> = {}

prop_type_add('LspTextRef', {'highlight': 'Search'})
prop_type_add('LspReadRef', {'highlight': 'DiffChange'})
prop_type_add('LspWriteRef', {'highlight': 'DiffDelete'})

# Return the LSP server for the a specific filetype. Returns a null dict if
# the server is not found.
def s:lspGetServer(ftype: string): dict<any>
  return ftypeServerMap->get(ftype, {})
enddef

# Add a LSP server for a filetype
def s:lspAddServer(ftype: string, lspserver: dict<any>)
  ftypeServerMap->extend({[ftype]: lspserver})
enddef

def lsp#enableServerTrace()
  lsp_server_trace = v:true
enddef

# Show information about all the LSP servers
def lsp#showServers()
  for [ftype, lspserver] in items(ftypeServerMap)
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

  lspserver.didSaveFile()
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
    lspserver.startServer()
  endif
  lspserver.textdocDidOpen(bnr, ftype)

  # Display hover information
  autocmd CursorHold <buffer> call s:LspHover()
  # file saved notification handler
  autocmd BufWritePost <buffer> call s:lspSavedFile()

  # add a listener to track changes to this buffer
  listener_add(function('lsp#bufchange_listener'), bnr)
  setbufvar(bnr, '&completefunc', 'lsp#completeFunc')
  setbufvar(bnr, '&completeopt', 'menuone,preview,noinsert')

  # map characters that trigger signature help
  if lspserver.caps->has_key('signatureHelpProvider')
    var triggers = lspserver.caps.signatureHelpProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch
				.. "<C-R>=lsp#showSignature()<CR>"
    endfor
  endif

  # map characters that trigger insert mode completion
  if lspserver.caps->has_key('completionProvider')
    var triggers = lspserver.caps.completionProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <buffer> <silent> ' .. ch .. ' ' .. ch .. "<C-X><C-U>"
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

  var fname: string = bufname(bnr)
  var ftype: string = bnr->getbufvar('&filetype')
  if fname == '' || ftype == ''
    return
  endif
  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty() || !lspserver.running
    return
  endif
  lspserver.textdocDidClose(bnr)
  if lspserver.diagsMap->has_key(fname)
    lspserver.diagsMap->remove(fname)
  endif
  remove(bufnrToServer, bnr)
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

    if !file_readable(server.path)
      ErrMsg('Error: LSP server ' .. server.path .. ' is not found')
      return
    endif
    if type(server.args) != v:t_list
      ErrMsg('Error: Arguments for LSP server ' .. server.path .. ' is not a List')
      return
    endif

    var lspserver: dict<any> = NewLspServer(server.path, server.args)

    if type(server.filetype) == v:t_string
      s:lspAddServer(server.filetype, lspserver)
    elseif type(server.filetype) == v:t_list
      for ftype in server.filetype
        s:lspAddServer(ftype, lspserver)
      endfor
    else
      ErrMsg('Error: Unsupported file type information "' .. string(server.filetype)
                                  .. '" in LSP server registration')
      continue
    endif
  endfor
enddef

# set the LSP server trace level for the current buffer
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

# Map the LSP DiagnosticSeverity to a type character
def LspDiagSevToType(severity: number): string
  var typeMap: list<string> = ['E', 'W', 'I', 'N']

  if severity > 4
    return ''
  endif

  return typeMap[severity - 1]
enddef

# Display the diagnostic messages from the LSP server for the current buffer
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

  if !lspserver.diagsMap->has_key(fname) || lspserver.diagsMap[fname]->empty()
    WarnMsg('No diagnostic messages found for ' .. fname)
    return
  endif

  var qflist: list<dict<any>> = []
  var text: string

  for [lnum, diag] in items(lspserver.diagsMap[fname])
    text = diag.message->substitute("\n\\+", "\n", 'g')
    qflist->add({'filename': fname,
                    'lnum': diag.range.start.line + 1,
                    'col': diag.range.start.character + 1,
                    'text': text,
                    'type': LspDiagSevToType(diag.severity)})
  endfor
  setqflist([], ' ', {'title': 'Language Server Diagnostics', 'items': qflist})
  :copen
enddef

# Insert mode completion handler
def lsp#completeFunc(findstart: number, base: string): any
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
    lspserver.getCompletion()

    # locate the start of the word
    var line = getline('.')
    var start = col('.') - 1
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
    return res
  endif
enddef

# Display the hover message from the LSP server for the current cursor
# location
def LspHover()
  var ftype = &filetype
  if ftype == ''
    return
  endif

  var lspserver: dict<any> = s:lspGetServer(ftype)
  if lspserver->empty()
    return
  endif
  if !lspserver.running
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
  prop_remove({'type': 'LspTextRef', 'all': v:true}, 1, line('$'))
  prop_remove({'type': 'LspReadRef', 'all': v:true}, 1, line('$'))
  prop_remove({'type': 'LspWriteRef', 'all': v:true}, 1, line('$'))
enddef

# open a window and display all the symbols in a file
def lsp#showDocSymbols()
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

  lspserver.showDocSymbols(fname)
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
    lspserver.textDocFormat(fname, v:true, line1, line2)
  else
    lspserver.textDocFormat(fname, v:false, 0, 0)
  endif
enddef

# TODO: Add support for textDocument.onTypeFormatting?
# Will this slow down Vim?

# Display all the locations where the current symbol is called from.
# Uses LSP "callHierarchy/incomingCalls" request
def lsp#incomingCalls()
  :echomsg 'Error: Not implemented yet'
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

# Perform a workspace wide symbol lookup
# Uses LSP "workspace/symbol" request
def lsp#showWorkspaceSymbols()
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

  var sym: string = input("Lookup symbol: ", expand('<cword>'))
  if sym == ''
    return
  endif

  lspserver.workspaceSymbols(sym)
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

  echomsg 'Workspace Folders: ' .. string(lspserver.workspaceFolders)
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

# vim: shiftwidth=2 softtabstop=2
