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
import './semantichighlight.vim'

# LSP server information
var LSPServers: list<dict<any>> = []

# filetype to LSP server map
var ftypeServerMap: dict<list<dict<any>>> = {}

var lspInitializedOnce = false

def LspInitOnce()
  hlset([
    {name: 'LspTextRef', default: true, linksto: 'Search'},
    {name: 'LspReadRef', default: true, linksto: 'DiffChange'},
    {name: 'LspWriteRef', default: true, linksto: 'DiffDelete'}
  ])

  var override = &cursorline
      && &cursorlineopt =~ '\<line\>\|\<screenline\>\|\<both\>'

  prop_type_add('LspTextRef', {highlight: 'LspTextRef', override: override})
  prop_type_add('LspReadRef', {highlight: 'LspReadRef', override: override})
  prop_type_add('LspWriteRef', {highlight: 'LspWriteRef', override: override})

  diag.InitOnce()
  inlayhints.InitOnce()
  signature.InitOnce()
  symbol.InitOnce()
  semantichighlight.InitOnce()

  lspInitializedOnce = true
enddef

# Returns the LSP servers for the a specific filetype. Based on how well there
# score, LSP servers with the same score are being returned.
# Returns an empty list if the servers is not found.
def LspGetServers(bnr: number, ftype: string): list<dict<any>>
  if !ftypeServerMap->has_key(ftype)
    return []
  endif

  var bufDir = bnr->bufname()->fnamemodify(':p:h')

  return ftypeServerMap[ftype]->filter((key, lspserver) => {
    # Don't run the server if no path is found
    if !lspserver.runIfSearchFiles->empty()
      var path = util.FindNearestRootDir(bufDir, lspserver.runIfSearchFiles)

      if path->empty()
        return false
      endif
    endif

    # Don't run the server if a path is found
    if !lspserver.runUnlessSearchFiles->empty()
      var path = util.FindNearestRootDir(bufDir, lspserver.runUnlessSearchFiles)

      if !path->empty()
        return false
      endif
    endif

    # Run the server
    return true
  })
enddef

# Add a LSP server for a filetype
def LspAddServer(ftype: string, lspsrv: dict<any>)
  var lspsrvlst = ftypeServerMap->has_key(ftype) ? ftypeServerMap[ftype] : []
  lspsrvlst->add(lspsrv)
  ftypeServerMap[ftype] = lspsrvlst
enddef

# Enable/disable the logging of the language server protocol messages
def ServerDebug(arg: string)
  if ['errors', 'messages', 'off', 'on']->index(arg) == -1
    util.ErrMsg($'Unsupported argument "{arg}"')
    return
  endif

  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  if lspservers->empty()
    util.WarnMsg($'No Lsp servers found for "{@%}"')
    return
  endif

  for lspserver in lspservers
    if arg == 'on'
      util.ClearTraceLogs(lspserver.logfile)
      util.ClearTraceLogs(lspserver.errfile)
      lspserver.debug = true
    elseif arg == 'off'
      lspserver.debug = false
    elseif arg == 'messages'
      util.ServerMessagesShow(lspserver.logfile)
    else
      util.ServerMessagesShow(lspserver.errfile)
    endif
  endfor
enddef

# Show information about all the LSP servers
export def ShowAllServers()
  var lines = []
  # Add filetype to server mapping information
  lines->add('Filetype Information')
  lines->add('====================')
  for [ftype, lspservers] in ftypeServerMap->items()
    for lspserver in lspservers
      lines->add($"Filetype: '{ftype}'")
      lines->add($"Server Name: '{lspserver.name}'")
      lines->add($"Server Path: '{lspserver.path}'")
      lines->add($"Status: {lspserver.running ? 'Running' : 'Not running'}")
      lines->add('')
    endfor
  endfor

  # Add buffer to server mapping information
  lines->add('Buffer Information')
  lines->add('==================')
  for bnr in range(1, bufnr('$'))
    var lspservers: list<dict<any>> = buf.BufLspServersGet(bnr)
    if !lspservers->empty()
      lines->add($"Buffer: '{bufname(bnr)}'")
      for lspserver in lspservers
        lines->add($"Server Path: '{lspserver.path}'")
        lines->add($"Status: {lspserver.running ? 'Running' : 'Not running'}")
      endfor
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

# Create a new window containing the buffer "bname" or if the window is
# already present then jump to it.
def OpenScratchWindow(bname: string)
  var wid = bufwinid(bname)
  if wid != -1
    wid->win_gotoid()
    :setlocal modifiable
    :silent! :%d _
  else
    exe $':new {bname}'
    :setlocal buftype=nofile
    :setlocal bufhidden=wipe
    :setlocal noswapfile
    :setlocal nonumber nornu
    :setlocal fdc=0 signcolumn=no
  endif
enddef

# Show the status of the LSP server for the current buffer
def ShowServer(arg: string)
  if ['status', 'capabilities', 'initializeRequest', 'messages']->index(arg) == -1
    util.ErrMsg($'Unsupported argument "{arg}"')
    return
  endif

  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  if lspservers->empty()
    util.WarnMsg($'No Lsp servers found for "{@%}"')
    return
  endif

  var windowName: string = ''
  var lines: list<string> = []
  if arg->empty() || arg == 'status'
    windowName = $'LangServer-Status'
    for lspserver in lspservers
      if !lines->empty()
        lines->extend(['', repeat('=', &columns), ''])
      endif
      var msg = $"LSP server '{lspserver.name}' is "
      if lspserver.running
        msg ..= 'running'
      else
        msg ..= 'not running'
      endif
      lines->add(msg)
    endfor
  elseif arg == 'capabilities'
    windowName = $'LangServer-Capabilities'
    for lspserver in lspservers
      if !lines->empty()
        lines->extend(['', repeat('=', &columns), ''])
      endif
      lines->extend(lspserver.getCapabilities())
    endfor
  elseif arg == 'initializeRequest'
    windowName = $'LangServer-InitializeRequest'
    for lspserver in lspservers
      if !lines->empty()
        lines->extend(['', repeat('=', &columns), ''])
      endif
      lines->extend(lspserver.getInitializeRequest())
    endfor
  elseif arg == 'messages'
    windowName = $'LangServer-Messages'
    for lspserver in lspservers
      if !lines->empty()
        lines->extend(['', repeat('=', &columns), ''])
      endif
      lines->extend(lspserver.getMessages())
    endfor
  else
    util.ErrMsg($'Unsupported argument "{arg}"')
    return
  endif

  if lines->len() > 1
    OpenScratchWindow(windowName)
    setline(1, lines)
    :setlocal nomodified
    :setlocal nomodifiable
  else
    util.InfoMsg(lines[0])
  endif
enddef

# Get LSP server running status for filetype "ftype"
# Return true if running, or false if not found or not running
export def ServerRunning(ftype: string): bool
  if ftypeServerMap->has_key(ftype)
    var lspservers = ftypeServerMap[ftype]
    for lspserver in lspservers
      if lspserver.running
        return true
      endif
    endfor
  endif

  return false
enddef

# Go to a definition using "textDocument/definition" LSP request
export def GotoDefinition(peek: bool, cmdmods: string, count: number)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('definition')
  if lspserver->empty()
    return
  endif

  lspserver.gotoDefinition(peek, cmdmods, count)
enddef

# Go to a declaration using "textDocument/declaration" LSP request
export def GotoDeclaration(peek: bool, cmdmods: string, count: number)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('declaration')
  if lspserver->empty()
    return
  endif

  lspserver.gotoDeclaration(peek, cmdmods, count)
enddef

# Go to a type definition using "textDocument/typeDefinition" LSP request
export def GotoTypedef(peek: bool, cmdmods: string, count: number)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('typeDefinition')
  if lspserver->empty()
    return
  endif

  lspserver.gotoTypeDef(peek, cmdmods, count)
enddef

# Go to a implementation using "textDocument/implementation" LSP request
export def GotoImplementation(peek: bool, cmdmods: string, count: number)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('implementation')
  if lspserver->empty()
    return
  endif

  lspserver.gotoImplementation(peek, cmdmods, count)
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

# A buffer is saved. Send the "textDocument/didSave" LSP notification
def LspSavedFile(bnr: number)
  var lspservers: list<dict<any>> = buf.BufLspServersGet(bnr)->filter(
    (key, lspsrv) => !lspsrv->empty() && lspsrv.running
  )

  if lspservers->empty()
    return
  endif

  for lspserver in lspservers
    lspserver.didSaveFile(bnr)
  endfor
enddef

# Called after leaving insert mode. Used to process diag messages (if any)
def LspLeftInsertMode(bnr: number)
  var updatePending: bool = bnr->getbufvar('LspDiagsUpdatePending', false)
  if !updatePending
    return
  endif
  setbufvar(bnr, 'LspDiagsUpdatePending', false)

  diag.ProcessNewDiags(bnr)
enddef

# Add buffer-local autocmds when attaching a LSP server to a buffer
def AddBufLocalAutocmds(lspserver: dict<any>, bnr: number): void
  var acmds: list<dict<any>> = []

  # file saved notification handler
  acmds->add({bufnr: bnr,
	      event: 'BufWritePost',
	      group: 'LSPBufferAutocmds',
	      cmd: $'LspSavedFile({bnr})'})

  # Update the diagnostics when insert mode is stopped
  acmds->add({bufnr: bnr,
	      event: 'InsertLeave',
	      group: 'LSPBufferAutocmds',
	      cmd: $'LspLeftInsertMode({bnr})'})

  # Auto highlight all the occurrences of the current keyword
  if opt.lspOptions.autoHighlight &&
			lspserver.isDocumentHighlightProvider
    acmds->add({bufnr: bnr,
		event: 'CursorMoved',
		group: 'LSPBufferAutocmds',
		cmd: $'call LspDocHighlightClear({bnr}) | call LspDocHighlight({bnr}, "silent")'})
  endif

  autocmd_add(acmds)
enddef

# The LSP server with ID "lspserverId" is ready, initialize the LSP features
# for buffer "bnr".
def BufferInit(lspserverId: number, bnr: number): void
  var lspserver = buf.BufLspServerGetById(bnr, lspserverId)
  if lspserver->empty() || !lspserver.running
    return
  endif

  var ftype: string = bnr->getbufvar('&filetype')
  lspserver.textdocDidOpen(bnr, ftype)

  # add a listener to track changes to this buffer
  listener_add((_bnr: number, start: number, end: number, added: number, changes: list<dict<number>>) => {
    lspserver.textdocDidChange(bnr, start, end, added, changes)
  }, bnr)

  AddBufLocalAutocmds(lspserver, bnr)

  diag.BufferInit(lspserver, bnr)

  var allServersReady = true
  var lspservers: list<dict<any>> = buf.BufLspServersGet(bnr)
  for lspsrv in lspservers
    if !lspsrv.ready
      allServersReady = false
      break
    endif
  endfor

  if allServersReady
    for lspsrv in lspservers
      # It's only possible to initialize the features when the server
      # capabilities of all the registered language servers for this file type
      # are known.
      var completionServer = buf.BufLspServerGet(bnr, 'completion')
      if !completionServer->empty() && lspsrv.id == completionServer.id
        completion.BufferInit(lspsrv, bnr, ftype)
      endif

      var signatureServer = buf.BufLspServerGet(bnr, 'signatureHelp')
      if !signatureServer->empty() && lspsrv.id == signatureServer.id
	signature.BufferInit(lspsrv)
      endif

      var inlayHintServer = buf.BufLspServerGet(bnr, 'inlayHint')
      if !inlayHintServer->empty() && lspsrv.id == inlayHintServer.id
	inlayhints.BufferInit(lspsrv, bnr)
      endif

      var semanticServer = buf.BufLspServerGet(bnr, 'semanticTokens')
      if !semanticServer->empty() && lspsrv.id == semanticServer.id
	semantichighlight.BufferInit(lspserver, bnr)
      endif
    endfor

    if exists('#User#LspAttached')
      doautocmd <nomodeline> User LspAttached
    endif
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
  if ftype->empty()
    return
  endif
  var lspservers: list<dict<any>> = LspGetServers(bnr, ftype)
  if lspservers->empty()
    return
  endif
  for lspserver in lspservers
    if !lspserver.running
      if !lspInitializedOnce
        LspInitOnce()
      endif
      lspserver.startServer(bnr)
    endif
    buf.BufLspServerSet(bnr, lspserver)

    if lspserver.ready
      BufferInit(lspserver.id, bnr)
    else
      augroup LSPBufferAutocmds
        exe $'autocmd User LspServerReady_{lspserver.id} ++once BufferInit({lspserver.id}, {bnr})'
      augroup END
    endif
  endfor
enddef

# Notify LSP server to remove a file
export def RemoveFile(bnr: number): void
  var lspservers: list<dict<any>> = buf.BufLspServersGet(bnr)
  for lspserver in lspservers->copy()
    if lspserver->empty()
      continue
    endif
    if lspserver.running
      lspserver.textdocDidClose(bnr)
    endif
    diag.DiagRemoveFile(bnr)
    buf.BufLspServerRemove(bnr, lspserver)
  endfor
enddef

# Buffer 'bnr' is loaded in a window, send the latest buffer contents to the
# language servers.
export def BufferLoadedInWin(bnr: number)
  var lspservers: list<dict<any>> = buf.BufLspServersGet(bnr)
  if lspservers->empty()
    # No language servers for this buffer
    return
  endif
  for lspserver in lspservers
    if !lspserver->empty() && lspserver.ready
      lspserver.textdocDidChange(bnr, 0, 0, 0, [])
    endif
  endfor
  # Refresh the displayed diags visuals
  if opt.lspOptions.autoHighlightDiags
    diag.DiagsRefresh(bnr)
  endif

  completion.BufferLoadedInWin(bnr)

  # Refresh the semantic highlights
  if opt.lspOptions.semanticHighlight
    var semanticServer = buf.BufLspServerGet(bnr, 'semanticTokens')
    if !semanticServer->empty()
      semanticServer.semanticHighlightUpdate(bnr)
    endif
  endif
enddef

# Stop all the LSP servers
export def StopAllServers()
  for lspserver in LSPServers
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
def RestartServer()
  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  if lspservers->empty()
    util.WarnMsg($'No Lsp servers found for "{@%}"')
    return
  endif

  # Remove all the buffers with the same file type as the current buffer
  var ftype: string = &filetype
  for binfo in getbufinfo()
    if binfo.bufnr->getbufvar('&filetype') == ftype
      RemoveFile(binfo.bufnr)
    endif
  endfor

  for lspserver in lspservers
    # Stop the server (if running)
    if lspserver.running
      lspserver.stopServer()
    endif

    # Start the server again
    lspserver.startServer(bufnr())
  endfor

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
      util.ErrMsg('LSP server information is missing filetype or path')
      continue
    endif
    # Enable omni-completion by default
    var omnicompl_def: bool = false
    if opt.lspOptions.omniComplete == true
	|| (opt.lspOptions.omniComplete == null
	    && !opt.lspOptions.autoComplete)
      omnicompl_def = true
    endif
    server.omnicompl = server->get('omnicompl', omnicompl_def)

    if !server.path->executable()
      if !opt.lspOptions.ignoreMissingServer
        util.ErrMsg($'LSP server {server.path} is not found')
      endif
      continue
    endif
    if server->has_key('args')
      if server.args->type() != v:t_list
        util.ErrMsg($'Arguments for LSP server {server.args} is not a List')
        continue
      endif
    else
      server.args = []
    endif

    if !server->has_key('initializationOptions')
	|| server.initializationOptions->type() != v:t_dict
      server.initializationOptions = {}
    endif

    if !server->has_key('forceOffsetEncoding')
	|| server.forceOffsetEncoding->type() != v:t_string
	|| (server.forceOffsetEncoding != 'utf-8'
	    && server.forceOffsetEncoding != 'utf-16'
	    && server.forceOffsetEncoding != 'utf-32')
      server.forceOffsetEncoding = ''
    endif

    if !server->has_key('customNotificationHandlers')
	|| server.customNotificationHandlers->type() != v:t_dict
      server.customNotificationHandlers = {}
    endif

    if server->has_key('processDiagHandler')
      if server.processDiagHandler->type() != v:t_func
        util.ErrMsg($'Setting of processDiagHandler {server.processDiagHandler} is not a Funcref nor lambda')
        continue
      endif
    else
      server.processDiagHandler = null_function
    endif

    if !server->has_key('customRequestHandlers')
	|| server.customRequestHandlers->type() != v:t_dict
      server.customRequestHandlers = {}
    endif

    if !server->has_key('features') || server.features->type() != v:t_dict
      server.features = {}
    endif

    if server.omnicompl->type() != v:t_bool
      util.ErrMsg($'Setting of omnicompl {server.omnicompl} is not a Boolean')
      continue
    endif

    if !server->has_key('syncInit')
      server.syncInit = false
    endif

    if !server->has_key('name') || server.name->type() != v:t_string
	|| server.name->empty()
      # Use the executable name (without the extension) as the language server
      # name.
      server.name = server.path->fnamemodify(':t:r')
    endif

    if !server->has_key('debug') || server.debug->type() != v:t_bool
      server.debug = false
    endif

    if !server->has_key('traceLevel')
	|| server->type() != v:t_string
	|| (server.traceLevel != 'off' && server.traceLevel != 'debug'
	    && server.traceLevel != 'verbose')
      server.traceLevel = 'off'
    endif

    if !server->has_key('workspaceConfig')
	|| server.workspaceConfig->type() != v:t_dict
      server.workspaceConfig = {}
    endif

    if !server->has_key('rootSearch') || server.rootSearch->type() != v:t_list
      server.rootSearch = []
    endif

    if !server->has_key('runIfSearch') ||
	server.runIfSearch->type() != v:t_list
      server.runIfSearch = []
    endif

    if !server->has_key('runUnlessSearch') ||
	server.runUnlessSearch->type() != v:t_list
      server.runUnlessSearch = []
    endif

    var lspserver: dict<any> = lserver.NewLspServer(server)

    var ftypes = server.filetype
    if ftypes->type() == v:t_string
      AddServerForFiltype(lspserver, ftypes, server.omnicompl)
    elseif ftypes->type() == v:t_list
      for ftype in ftypes
	AddServerForFiltype(lspserver, ftype, server.omnicompl)
      endfor
    else
      util.ErrMsg($'Unsupported file type information "{ftypes->string()}" in LSP server registration')
      continue
    endif
  endfor
enddef

# The LSP server is considered ready when the server capabilities are
# received ("initialize" LSP reply message)
export def ServerReady(): bool
  var fname: string = @%
  if fname->empty()
    return false
  endif

  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  if lspservers->empty()
    return false
  endif

  for lspserver in lspservers
    if !lspserver.ready
      return false
    endif
  endfor

  return true
enddef

# set the LSP server trace level for the current buffer
# Params: SetTraceParams
def ServerTraceSet(traceVal: string)
  if ['off', 'messages', 'verbose']->index(traceVal) == -1
    util.ErrMsg($'Unsupported argument "{traceVal}"')
    return
  endif

  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  if lspservers->empty()
    util.WarnMsg($'No Lsp servers found for "{@%}"')
    return
  endif

  for lspserver in lspservers
    lspserver.setTrace(traceVal)
  endfor
enddef

# Display the diagnostic messages from the LSP server for the current buffer
# in a quickfix list
export def ShowDiagnostics(): void
  diag.ShowAllDiags()
enddef

# Show the diagnostic message for the current line
export def LspShowCurrentDiag(atPos: bool)
  diag.ShowCurrentDiag(atPos)
enddef

# get the count of diagnostics in the current buffer
export def ErrorCount(): dict<number>
  var res = {Error: 0, Warn: 0, Info: 0, Hint: 0}
  var fname: string = @%
  if fname->empty()
    return res
  endif

  return diag.DiagsGetErrorCount(bufnr())
enddef

# jump to the next/previous/first diagnostic message in the current buffer
export def JumpToDiag(which: string, count: number = 0): void
  diag.LspDiagsJump(which, count)
enddef

# Display the hover message from the LSP server for the current cursor
# location
export def Hover(cmdmods: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('hover')
  if lspserver->empty()
    return
  endif

  lspserver.hover(cmdmods)
enddef

# Enable or disable inlay hints
export def InlayHints(ctl: string)
  if ctl == 'enable'
    inlayhints.InlayHintsEnable()
  elseif ctl == 'disable'
    inlayhints.InlayHintsDisable()
  else
    util.ErrMsg($'LspInlayHints - Unsupported argument "{ctl}"')
  endif
enddef

# Command-line completion for the ":LspInlayHints" command
export def LspInlayHintsComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  var l = ['enable', 'disable']
  return filter(l, (_, val) => val =~ $'^{arglead}')
enddef

# show symbol references
export def ShowReferences(peek: bool)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('references')
  if lspserver->empty()
    return
  endif

  lspserver.showReferences(peek)
enddef

# highlight all the places where a symbol is referenced
def g:LspDocHighlight(bnr: number = bufnr(), cmdmods: string = '')
  var lspserver: dict<any> = buf.CurbufGetServerChecked('documentHighlight')
  if lspserver->empty()
    return
  endif

  lspserver.docHighlight(bnr, cmdmods)
enddef

# clear the symbol reference highlight
def g:LspDocHighlightClear(bnr: number = bufnr())
  var lspserver: dict<any> = buf.CurbufGetServerChecked('documentHighlight')
  if lspserver->empty()
    return
  endif

  var propNames = ['LspTextRef', 'LspReadRef', 'LspWriteRef']
  if has('patch-9.0.0233')
    prop_remove({types: propNames, bufnr: bnr, all: true})
  else
    for propName in propNames
      prop_remove({type: propName, bufnr: bnr, all: true})
    endfor
  endif
enddef

def g:LspRequestDocSymbols()
  if outline.SkipOutlineRefresh()
    return
  endif

  var fname: string = @%
  if fname->empty()
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServer('documentSymbol')
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  lspserver.getDocSymbols(fname, true)
enddef

# open a window and display all the symbols in a file (outline)
export def Outline(cmdmods: string, winsize: number)
  var fname: string = @%
  if fname->empty()
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServerChecked('documentSymbol')
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  outline.OpenOutlineWindow(cmdmods, winsize)
  g:LspRequestDocSymbols()
enddef

# show all the symbols in a file in a popup menu
export def ShowDocSymbols()
  var fname: string = @%
  if fname->empty()
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServerChecked('documentSymbol')
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  lspserver.getDocSymbols(fname, false)
enddef

# Format the entire file
export def TextDocFormat(range_args: number, line1: number, line2: number)
  if !&modifiable
    util.ErrMsg('Current file is not a modifiable file')
    return
  endif

  var lspserver: dict<any> = buf.CurbufGetServerChecked('documentFormatting')
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
  var lspserver: dict<any> = buf.CurbufGetServerChecked('callHierarchy')
  if lspserver->empty()
    return
  endif

  lspserver.incomingCalls(@%)
enddef

# Display all the symbols used by the current symbol.
# Uses LSP "callHierarchy/outgoingCalls" request
export def OutgoingCalls()
  var lspserver: dict<any> = buf.CurbufGetServerChecked('callHierarchy')
  if lspserver->empty()
    return
  endif

  lspserver.outgoingCalls(@%)
enddef

# Display the type hierarchy for the current symbol.  Direction is 0 for
# sub types and 1 for super types.
export def TypeHierarchy(direction: number)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('typeHierarchy')
  if lspserver->empty()
    return
  endif

  lspserver.typeHierarchy(direction)
enddef

# Rename a symbol
# Uses LSP "textDocument/rename" request
export def Rename(a_newName: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('rename')
  if lspserver->empty()
    return
  endif

  var newName: string = a_newName
  if newName->empty()
    var sym: string = expand('<cword>')
    newName = input($"Rename symbol '{sym}' to: ", sym)
    if newName->empty()
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
  var lspserver: dict<any> = buf.CurbufGetServerChecked('codeAction')
  if lspserver->empty()
    return
  endif

  var fname: string = @%
  lspserver.codeAction(fname, line1, line2, query)
enddef

# Code lens
# Uses LSP "textDocument/codeLens" request
export def CodeLens()
  var lspserver: dict<any> = buf.CurbufGetServerChecked('codeLens')
  if lspserver->empty()
    return
  endif

  lspserver.codeLens(@%)
enddef

# Perform a workspace wide symbol lookup
# Uses LSP "workspace/symbol" request
export def SymbolSearch(queryArg: string, cmdmods: string)
  var lspserver: dict<any> = buf.CurbufGetServerChecked('workspaceSymbol')
  if lspserver->empty()
    return
  endif

  var query: string = queryArg
  if query->empty()
    query = input('Lookup symbol: ', expand('<cword>'))
    if query->empty()
      return
    endif
  endif
  :redraw!

  lspserver.workspaceQuery(query, true, cmdmods)
enddef

# Display the list of workspace folders
export def ListWorkspaceFolders()
  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  for lspserver in lspservers
    util.InfoMsg($'Workspace Folders: "{lspserver.name}" {lspserver.workspaceFolders->string()}')
  endfor
enddef

# Add a workspace folder. Default is to use the current folder.
export def AddWorkspaceFolder(dirArg: string)
  var dirName: string = dirArg
  if dirName->empty()
    dirName = input('Add Workspace Folder: ', getcwd(), 'dir')
    if dirName->empty()
      return
    endif
  endif
  :redraw!
  if !dirName->isdirectory()
    util.ErrMsg($'{dirName} is not a directory')
    return
  endif

  var lspservers: list<dict<any>> = buf.CurbufGetServers()

  for lspserver in lspservers
    lspserver.addWorkspaceFolder(dirName)
  endfor
enddef

# Remove a workspace folder. Default is to use the current folder.
export def RemoveWorkspaceFolder(dirArg: string)
  var dirName: string = dirArg
  if dirName->empty()
    dirName = input('Remove Workspace Folder: ', getcwd(), 'dir')
    if dirName->empty()
      return
    endif
  endif
  :redraw!
  if !dirName->isdirectory()
    util.ErrMsg($'{dirName} is not a directory')
    return
  endif

  var lspservers: list<dict<any>> = buf.CurbufGetServers()
  for lspserver in lspservers
    lspserver.removeWorkspaceFolder(dirName)
  endfor
enddef

# expand the previous selection or start a new selection
export def SelectionExpand()
  var lspserver: dict<any> = buf.CurbufGetServerChecked('selectionRange')
  if lspserver->empty()
    return
  endif

  lspserver.selectionExpand()
enddef

# shrink the previous selection or start a new selection
export def SelectionShrink()
  var lspserver: dict<any> = buf.CurbufGetServerChecked('selectionRange')
  if lspserver->empty()
    return
  endif

  lspserver.selectionShrink()
enddef

# fold the entire document
export def FoldDocument()
  var lspserver: dict<any> = buf.CurbufGetServerChecked('foldingRange')
  if lspserver->empty()
    return
  endif

  if &foldmethod != 'manual'
    util.ErrMsg("Only works when 'foldmethod' is 'manual'")
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

# Function to use with the 'tagfunc' option.
export def TagFunc(pat: string, flags: string, info: dict<any>): any
  var lspserver: dict<any> = buf.CurbufGetServerChecked('definition')
  if lspserver->empty()
    return v:null
  endif

  return lspserver.tagFunc(pat, flags, info)
enddef

# Function to use with the 'formatexpr' option.
export def FormatExpr(): number
  var lspserver: dict<any> = buf.CurbufGetServerChecked('documentFormatting')
  if lspserver->empty()
    return 1
  endif

  lspserver.textDocFormat(@%, true, v:lnum, v:lnum + v:count - 1)
  return 0
enddef

export def RegisterCmdHandler(cmd: string, Handler: func)
  codeaction.RegisterCmdHandler(cmd, Handler)
enddef

# Command-line completion for the ":LspServer <cmd>" and ":LspDiag <cmd>" sub
# commands
def LspSubCmdComplete(cmds: list<string>, arglead: string, cmdline: string, cursorPos: number): list<string>
  var wordBegin = cmdline->match('\s\+\zs\S', cursorPos)
  if wordBegin == -1
    return cmds
  endif

  # Make sure there are no additional sub-commands
  var wordEnd = cmdline->stridx(' ', wordBegin)
  if wordEnd == -1
    return cmds->filter((_, val) => val =~ $'^{arglead}')
  endif

  return []
enddef

# Command-line completion for the ":LspDiag highlight" command
def LspDiagHighlightComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  return LspSubCmdComplete(['enable', 'disable'], arglead, cmdline, cursorPos)
enddef

# Command-line completion for the ":LspDiag" command
export def LspDiagComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  var wordBegin = -1
  var wordEnd = -1
  var l = ['first', 'current', 'here', 'highlight', 'last', 'next', 'nextWrap',
           'prev', 'prevWrap', 'show']

  # Skip the command name
  var i = cmdline->stridx(' ', 0)
  wordBegin = cmdline->match('\s\+\zs\S', i)
  if wordBegin == -1
    return l
  endif

  wordEnd = cmdline->stridx(' ', wordBegin)
  if wordEnd == -1
    return filter(l, (_, val) => val =~ $'^{arglead}')
  endif

  var cmd = cmdline->strpart(wordBegin, wordEnd - wordBegin)
  if cmd == 'highlight'
    return LspDiagHighlightComplete(arglead, cmdline, wordEnd)
  endif

  return []
enddef

# ":LspDiag" command handler
export def LspDiagCmd(args: string, cmdCount: number, force: bool)
  if args->stridx('highlight') == 0
    if args[9] == ' '
      var subcmd = args[10 : ]->trim()
      if subcmd == 'enable'
	diag.DiagsHighlightEnable()
      elseif subcmd == 'disable'
	diag.DiagsHighlightDisable()
      else
	util.ErrMsg($':LspDiag highlight - Unsupported argument "{subcmd}"')
      endif
    else
      util.ErrMsg('Argument required for ":LspDiag highlight"')
    endif
  elseif args == 'first'
    diag.LspDiagsJump('first', 0)
  elseif args == 'current'
    LspShowCurrentDiag(force)
  elseif args == 'here'
    diag.LspDiagsJump('here', 0)
  elseif args == 'last'
    diag.LspDiagsJump('last', 0)
  elseif args == 'next'
    diag.LspDiagsJump('next', cmdCount)
  elseif args == 'nextWrap'
    diag.LspDiagsJump('nextWrap', cmdCount)
  elseif args == 'prev'
    diag.LspDiagsJump('prev', cmdCount)
  elseif args == 'prevWrap'
    diag.LspDiagsJump('prevWrap', cmdCount)
  elseif args == 'show'
    ShowDiagnostics()
  else
    util.ErrMsg($':LspDiag - Unsupported argument "{args}"')
  endif
enddef

# Command-line completion for the ":LspServer debug" command
def LspServerDebugComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  return LspSubCmdComplete(['errors', 'messages', 'off', 'on'], arglead,
			   cmdline, cursorPos)
enddef

# Command-line completion for the ":LspServer show" command
def LspServerShowComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  return LspSubCmdComplete(['capabilities', 'initializeRequest', 'messages',
			    'status'], arglead, cmdline, cursorPos)
enddef

# Command-line completion for the ":LspServer trace" command
def LspServerTraceComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  return LspSubCmdComplete(['messages', 'off', 'verbose'], arglead, cmdline,
			   cursorPos)
enddef

# Command-line completion for the ":LspServer" command
export def LspServerComplete(arglead: string, cmdline: string, cursorPos: number): list<string>
  var wordBegin = -1
  var wordEnd = -1
  var l = ['debug', 'restart', 'show', 'trace']

  # Skip the command name
  var i = cmdline->stridx(' ', 0)
  wordBegin = cmdline->match('\s\+\zs\S', i)
  if wordBegin == -1
    return l
  endif

  wordEnd = cmdline->stridx(' ', wordBegin)
  if wordEnd == -1
    return filter(l, (_, val) => val =~ $'^{arglead}')
  endif

  var cmd = cmdline->strpart(wordBegin, wordEnd - wordBegin)
  if cmd == 'debug'
    return LspServerDebugComplete(arglead, cmdline, wordEnd)
  elseif cmd == 'restart'
  elseif cmd == 'show'
    return LspServerShowComplete(arglead, cmdline, wordEnd)
  elseif cmd == 'trace'
    return LspServerTraceComplete(arglead, cmdline, wordEnd)
  endif

  return []
enddef

# ":LspServer" command handler
export def LspServerCmd(args: string)
  if args->stridx('debug') == 0
    if args[5] == ' '
      var subcmd = args[6 : ]->trim()
      ServerDebug(subcmd)
    else
      util.ErrMsg('Argument required for ":LspServer debug"')
    endif
  elseif args == 'restart'
    RestartServer()
  elseif args->stridx('show') == 0
    if args[4] == ' '
      var subcmd = args[5 : ]->trim()
      ShowServer(subcmd)
    else
      util.ErrMsg('Argument required for ":LspServer show"')
    endif
  elseif args->stridx('trace') == 0
    if args[5] == ' '
      var subcmd = args[6 : ]->trim()
      ServerTraceSet(subcmd)
    else
      util.ErrMsg('Argument required for ":LspServer trace"')
    endif
  else
    util.ErrMsg($'LspServer - Unsupported argument "{args}"')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
