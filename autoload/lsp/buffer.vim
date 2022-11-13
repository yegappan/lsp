vim9script

# Functions for managing the per-buffer LSP server information

import './util.vim'

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

# Returns the LSP server for the current buffer if it is running and is ready.
# Returns an empty dict if the server is not found or is not ready.
export def CurbufGetServerChecked(): dict<any>
  var fname: string = @%
  if fname == ''
    return {}
  endif

  var lspserver: dict<any> = CurbufGetServer()
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
