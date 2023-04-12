vim9script

# Functions for managing the per-buffer LSP server information

import './util.vim'

# Buffer number to LSP server map
var bufnrToServers: dict<list<dict<any>>> = {}

export def BufLspServerSet(bnr: number, lspserver: dict<any>)
  if !bufnrToServers->has_key(bnr)
    bufnrToServers[bnr] = []
  endif

  bufnrToServers[bnr]->add(lspserver)
enddef

export def BufLspServerRemove(bnr: number, lspserver: dict<any>)
  if !bufnrToServers->has_key(bnr)
    return
  endif

  var servers: list<dict<any>> = bufnrToServers[bnr]
  servers = servers->filter((key, srv) => srv.id != lspserver.id)

  if servers->empty()
    bufnrToServers->remove(bnr)
  else
    bufnrToServers[bnr] = servers
  endif
enddef

# Returns the LSP server for the buffer 'bnr' and optionally 'domain'.
# Returns an empty dict if the server is not found.
export def BufLspServerGet(bnr: number, domain: string = null_string): dict<any>
  if !bufnrToServers->has_key(bnr)
    return {}
  endif

  if bufnrToServers[bnr]->empty()
    return {}
  endif

  if domain == null_string
    return bufnrToServers[bnr][0]
  endif

  var SupportedCheckFns = {
    'completion': (lspserver) => lspserver.isCompletionProvider,
    'definition': (lspserver) => lspserver.isDefinitionProvider,
    'declaration': (lspserver) => lspserver.isDeclarationProvider,
    'typeDefinition': (lspserver) => lspserver.isTypeDefinitionProvider,
    'implementation': (lspserver) => lspserver.isImplementationProvider,
    'hover': (lspserver) => lspserver.isHoverProvider,
    'references': (lspserver) => lspserver.isReferencesProvider,
    'documentHighlight': (lspserver) => lspserver.isDocumentHighlightProvider,
    'documentFormatting': (lspserver) => lspserver.isDocumentFormattingProvider,
    'rename': (lspserver) => lspserver.isRenameProvider,
    'codeAction': (lspserver) => lspserver.isCodeActionProvider,
    'codeLens': (lspserver) => lspserver.isCodeLensProvider,
    'selectionRange': (lspserver) => lspserver.isSelectionRangeProvider,
  }

  if !SupportedCheckFns->has_key(domain)
    # If this happns it is a programming error, and should be fixed in the source code
    :throw $'Error: ''{domain}'' is not a valid domain'
    return {}
  endif

  var SupportedCheckFn = SupportedCheckFns[domain]

  var possibleLSPs: list<dict<any>> = []

  for lspserver in bufnrToServers[bnr]
    if !SupportedCheckFn(lspserver)
      continue
    endif

    possibleLSPs->add(lspserver)
  endfor

  if possibleLSPs->len() == 0
    return {}
  endif

  # LSP server is configured to be a provider for 'domain'
  for lspserver in possibleLSPs
    if lspserver.features->has_key(domain) && lspserver.features[domain]
      return lspserver
    endif
  endfor

  # Return the first LSP server that supports 'domain'
  return possibleLSPs[0]
enddef

# Returns the LSP server for the buffer 'bnr' and with ID 'id'. Returns an empty
# dict if the server is not found.
export def BufLspServerGetById(bnr: number, id: number): dict<any>
  if !bufnrToServers->has_key(bnr)
    return {}
  endif

  for lspserver in bufnrToServers[bnr]
    if lspserver.id == id
      return lspserver
    endif
  endfor

  return {}
enddef

# Returns the LSP servers for the buffer 'bnr'. Returns an empty list if the
# servers are not found.
export def BufLspServersGet(bnr: number): list<dict<any>>
  if !bufnrToServers->has_key(bnr)
    return []
  endif

  return bufnrToServers[bnr]
enddef

# Returns the LSP server for the current buffer with the optionally 'domain'.
# Returns an empty dict if the server is not found.
export def CurbufGetServer(domain: string = null_string): dict<any>
  return BufLspServerGet(bufnr(), domain)
enddef

# Returns the LSP servers for the current buffer. Returns an empty list if the
# servers are not found.
export def CurbufGetServers(): list<dict<any>>
  return BufLspServersGet(bufnr())
enddef

export def BufHasLspServer(bnr: number): bool
  var lspserver = BufLspServerGet(bnr)

  return !lspserver->empty()
enddef

# Returns the LSP server for the current buffer with the optinally 'domain' if
# it is running and is ready.
# Returns an empty dict if the server is not found or is not ready.
export def CurbufGetServerChecked(domain: string = null_string): dict<any>
  var fname: string = @%
  if fname == ''
    return {}
  endif

  var lspserver: dict<any> = CurbufGetServer(domain)
  if lspserver->empty()
    util.ErrMsg($'Error: Language server for "{&filetype}" file type is not found')
    return {}
  endif
  if !lspserver.running
    util.ErrMsg($'Error: Language server for "{&filetype}" file type is not running')
    return {}
  endif
  if !lspserver.ready
    util.ErrMsg($'Error: Language server for "{&filetype}" file type is not ready')
    return {}
  endif

  return lspserver
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
