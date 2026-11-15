vim9script
# Unit tests for the "serverPerRoot" option (one language server instance per
# workspace root directory)

source common.vim

import '../autoload/lsp/buffer.vim' as buf
import '../autoload/lsp/util.vim' as util

var lspServers = [{
      filetype: ['go'],
      path: exepath('gopls'),
      args: ['serve'],
      rootSearch: ['go.mod']
  }]
call LspAddServer(lspServers)

# Create two Go modules (workspace roots) "Xroot1" and "Xroot2"
def CreateRoots()
  for dir in ['Xroot1', 'Xroot2']
    mkdir(dir, 'p')
    writefile([$'module example.com/{dir}', '', 'go 1.21'], $'{dir}/go.mod')
    writefile(['package main', '', 'func main() {', '}'], $'{dir}/main.go')
    writefile(['package main'], $'{dir}/util.go')
  endfor
enddef

def DeleteRoots()
  delete('Xroot1', 'rf')
  delete('Xroot2', 'rf')
enddef

# Edit file "fname" and return the language server attached to it after the
# server is ready.
def EditAndGetServer(fname: string): dict<any>
  exe $'silent! edit {fname}'
  var lspservers = buf.BufLspServersGet(bufnr())
  assert_equal(1, lspservers->len())
  var lspserver = lspservers[0]
  g:WaitForAssert(() => assert_true(lspserver.ready), 10000)
  return lspserver
enddef

# Assert that "lspserver" was started with "dir" as the workspace root
def AssertServerRoot(lspserver: dict<any>, dir: string)
  var rootPath = dir->fnamemodify(':p')
  assert_equal([rootPath], lspserver.workspaceFolders)
  var initReq = lspserver.rpcInitializeRequest
  assert_equal(util.LspFileToUri(rootPath), initReq.rootUri)
  assert_equal([util.LspFileToUri(rootPath)],
	       initReq.workspaceFolders->mapnew((_, f) => f.uri))
enddef

# Assert that the process of "lspserver" is running in the directory "dir"
def AssertServerCwd(lspserver: dict<any>, dir: string)
  var procCwd = $'/proc/{lspserver.job->job_info().process}/cwd'
  if !isdirectory(procCwd)
    # Not supported on this system
    return
  endif
  assert_equal(dir->fnamemodify(':p')->resolve()->trim('/', 2),
	       procCwd->resolve()->trim('/', 2))
enddef

# Test for the default behavior: a single server instance for all the roots
def g:Test_ServerPerRoot_Disabled()
  CreateRoots()
  g:LspOptionsSet({serverPerRoot: false})

  var srv1 = EditAndGetServer('Xroot1/main.go')
  var srv2 = EditAndGetServer('Xroot2/main.go')
  assert_equal(srv1.id, srv2.id)
  # The server runs in the current directory
  AssertServerCwd(srv1, getcwd())

  :%bw!
  DeleteRoots()
enddef

# Test for a separate server instance for each root
def g:Test_ServerPerRoot_Enabled()
  CreateRoots()
  g:LspOptionsSet({serverPerRoot: true})

  var srv1 = EditAndGetServer('Xroot1/main.go')
  var srv2 = EditAndGetServer('Xroot2/main.go')
  assert_notequal(srv1.id, srv2.id)
  AssertServerRoot(srv1, 'Xroot1')
  AssertServerRoot(srv2, 'Xroot2')
  # The new server instance runs in its root directory.  The first server may
  # have been started by a previous test with "serverPerRoot" off.
  AssertServerCwd(srv2, 'Xroot2')

  # Another file in the same root uses the same server instance
  var srv3 = EditAndGetServer('Xroot1/util.go')
  assert_equal(srv1.id, srv3.id)
  var srv4 = EditAndGetServer('Xroot2/util.go')
  assert_equal(srv2.id, srv4.id)

  assert_true(lsp#lsp#ServerRunning('go'))

  # Restarting the server should restart only the server for the root of the
  # current buffer
  var pid1 = srv1.job->job_info().process
  var pid2 = srv2.job->job_info().process
  :edit Xroot2/main.go
  :LspServer restart
  g:WaitForAssert(() => assert_true(srv2.ready), 10000)
  assert_equal(pid1, srv1.job->job_info().process)
  assert_equal('run', srv1.job->job_status())
  assert_notequal(pid2, srv2.job->job_info().process)
  AssertServerRoot(srv2, 'Xroot2')
  AssertServerCwd(srv2, 'Xroot2')
  # The current buffer is attached to the same instance again
  assert_equal([srv2.id], buf.BufLspServersGet(bufnr())->mapnew((_, s) => s.id))
  # The buffers of the other root are still attached to their instance
  for fname in ['Xroot1/main.go', 'Xroot1/util.go']
    assert_equal([srv1.id],
		 buf.BufLspServersGet(bufnr(fname))->mapnew((_, s) => s.id))
  endfor

  # After a restart, the first server also runs in its root directory
  :edit Xroot1/main.go
  :LspServer restart
  g:WaitForAssert(() => assert_true(srv1.ready), 10000)
  AssertServerCwd(srv1, 'Xroot1')

  :%bw!
  g:LspOptionsSet({serverPerRoot: false})
  DeleteRoots()
enddef

# The language servers are started by the tests
def g:StartLangServer(): bool
  return true
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
