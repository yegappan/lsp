vim9script
# Unit tests for Vim Language Server Protocol (LSP) golang client

source common.vim

var lspServers = [{
      filetype: ['go'],
      path: exepath('gopls'),
      args: ['serve']
  }]
call LspAddServer(lspServers)
echomsg systemlist($'{lspServers[0].path} version')

# Test for :LspGotoDefinition, :LspGotoDeclaration, etc.
def g:Test_LspGoto()
  :silent! edit Xtest.go
  sleep 200m

  var lines =<< trim END
    package main

    func foo() {
    }

    func bar() {
	foo();
    }
  END
  
  setline(1, lines)
  :redraw!
  g:WaitForServerFileLoad(0)

  cursor(7, 1)
  :LspGotoDefinition
  assert_equal([3, 6], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([7, 1], [line('.'), col('.')])

  bw!
enddef

# Start the gopls language server.  Returns true on success and false on
# failure.
def g:StartLangServer(): bool
  return g:StartLangServerWithFile('Xtest.go')
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
