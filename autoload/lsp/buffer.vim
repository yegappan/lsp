vim9script

# Functions for managing the per-buffer LSP server information

# Buffer number to LSP server map
var bufnrToServer: dict<dict<any>> = {}

export def BufLspServerSet(bnr: number, lspserver: dict<any>)
  bufnrToServer[bnr] = lspserver
enddef

export def BufLspServerRemove(bnr: number)
  bufnrToServer->remove(bnr)
enddef

# Returns the LSP server for the buffer 'bnr'. Returns an empty dict if the
# server is not found.
export def BufLspServerGet(bnr: number): dict<any>
  return bufnrToServer->get(bnr, {})
enddef

# Returns the LSP server for the current buffer. Returns an empty dict if the
# server is not found.
export def CurbufGetServer(): dict<any>
  return BufLspServerGet(bufnr())
enddef

export def BufHasLspServer(bnr: number): bool
  return bufnrToServer->has_key(bnr)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
