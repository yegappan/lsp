vim9script
# Unit tests for LSP rust-analyzer client

source common.vim
source term_util.vim
source screendump.vim

var lspServers = [{
      filetype: ['rust'],
      path: exepath('rust-analyzer'),
      args: []
  }]
call LspAddServer(lspServers)
echomsg systemlist($'{lspServers[0].path} --version')

def g:Test_LspGotoDef()
  settagstack(0, {items: []})
  :cd xrust_tests/src
  try
    silent! edit ./main.rs
    sleep 600m
    var lines: list<string> =<< trim END
      fn foo() {
      }
      fn bar() {
        foo();
      }
    END
    append('$', lines)
    g:WaitForServerFileLoad(0)
    cursor(7, 5)
    :LspGotoDefinition
    assert_equal([4, 4], [line('.'), col('.')])
    :%bw!
  finally
    :cd ../..
  endtry
enddef

def g:Test_ZZZ_Cleanup()
  delete('./xrust_tests', 'rf')
enddef

# Start the rust-analyzer language server.  Returns true on success and false
# on failure.
def g:StartLangServer(): bool
  system('cargo new xrust_tests')
  :cd xrust_tests/src
  var status = false
  try
    status = g:StartLangServerWithFile('./main.rs')
  finally
    :cd ../..
  endtry
  return status
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
