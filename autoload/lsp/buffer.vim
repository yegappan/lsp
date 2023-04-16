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

var SupportedCheckFns = {
  codeAction: (lspserver) => lspserver.isCodeActionProvider,
  codeLens: (lspserver) => lspserver.isCodeLensProvider,
  completion: (lspserver) => lspserver.isCompletionProvider,
  declaration: (lspserver) => lspserver.isDeclarationProvider,
  definition: (lspserver) => lspserver.isDefinitionProvider,
  documentFormatting: (lspserver) => lspserver.isDocumentFormattingProvider,
  documentHighlight: (lspserver) => lspserver.isDocumentHighlightProvider,
  foldingRange: (lspserver) => lspserver.isFoldingRangeProvider,
  hover: (lspserver) => lspserver.isHoverProvider,
  implementation: (lspserver) => lspserver.isImplementationProvider,
  references: (lspserver) => lspserver.isReferencesProvider,
  rename: (lspserver) => lspserver.isRenameProvider,
  selectionRange: (lspserver) => lspserver.isSelectionRangeProvider,
  typeDefinition: (lspserver) => lspserver.isTypeDefinitionProvider,
}

# Returns the LSP server for the buffer "bnr".  If "feature" is specified,
# then returns the LSP server that provides the "feature".
# Returns an empty dict if the server is not found.
export def BufLspServerGet(bnr: number, feature: string = null_string): dict<any>
  if !bufnrToServers->has_key(bnr)
    return {}
  endif

  if bufnrToServers[bnr]->empty()
    return {}
  endif

  if feature == null_string
    return bufnrToServers[bnr][0]
  endif

  if !SupportedCheckFns->has_key(feature)
    # If this happns it is a programming error, and should be fixed in the source code
    :throw $'Error: ''{feature}'' is not a valid feature'
    return {}
  endif

  var SupportedCheckFn = SupportedCheckFns[feature]

  var possibleLSPs: list<dict<any>> = []

  for lspserver in bufnrToServers[bnr]
    if !SupportedCheckFn(lspserver)
      continue
    endif

    possibleLSPs->add(lspserver)
  endfor

  if possibleLSPs->empty()
    return {}
  endif

  # LSP server is configured to be a provider for 'feature'
  for lspserver in possibleLSPs
    if lspserver.features->has_key(feature) && lspserver.features[feature]
      return lspserver
    endif
  endfor

  # Return the first LSP server that supports "feature" and doesn't have it
  # disabled
  for lspserver in possibleLSPs
    if !lspserver.features->has_key(feature)
      return lspserver
    endif
  endfor

  return {}
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

# Returns the LSP server for the current buffer with the optionally 'feature'.
# Returns an empty dict if the server is not found.
export def CurbufGetServer(feature: string = null_string): dict<any>
  return BufLspServerGet(bufnr(), feature)
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

# Returns the LSP server for the current buffer with the optinally 'feature' if
# it is running and is ready.
# Returns an empty dict if the server is not found or is not ready.
export def CurbufGetServerChecked(feature: string = null_string): dict<any>
  var fname: string = @%
  if fname == ''
    return {}
  endif

  var lspserver: dict<any> = CurbufGetServer(feature)
  if lspserver->empty()
    util.ErrMsg($'Language server for "{&filetype}" file type is not found')
    return {}
  endif
  if !lspserver.running
    util.ErrMsg($'Language server for "{&filetype}" file type is not running')
    return {}
  endif
  if !lspserver.ready
    util.ErrMsg($'Language server for "{&filetype}" file type is not ready')
    return {}
  endif

  return lspserver
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
