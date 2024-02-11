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
    deletebufline('%', 1, '$')
    g:WaitForServerFileLoad(0)
    var lines: list<string> =<< trim END
      fn main() {
      }
      fn foo() {
      }
      fn bar() {
        foo();
      }
    END
    setline(1, lines)
    g:WaitForServerFileLoad(0)
    cursor(6, 5)
    :LspGotoDefinition
    assert_equal([3, 4], [line('.'), col('.')])
    :%bw!
  finally
    :cd ../..
  endtry
enddef

# Test for :LspCodeAction creating a file in the current directory
def g:Test_LspCodeAction_CreateFile()
  :cd xrust_tests/src
  try
    silent! edit ./main.rs
    deletebufline('%', 1, '$')
    g:WaitForServerFileLoad(0)
    var lines: list<string> =<< trim END
      mod foo;
      fn main() {
      }
    END
    setline(1, lines)
    g:WaitForServerFileLoad(1)
    cursor(1, 1)
    :LspCodeAction 1
    g:WaitForServerFileLoad(0)
    assert_true(filereadable('foo.rs'))
    :%bw!
    delete('foo.rs')
  finally
    :cd ../..
  endtry
enddef

# Test for :LspCodeAction creating a file in a subdirectory
def g:Test_LspCodeAction_CreateFile_Subdir()
  :cd xrust_tests/src
  try
    silent! edit ./main.rs
    deletebufline('%', 1, '$')
    g:WaitForServerFileLoad(0)
    var lines: list<string> =<< trim END
      mod baz;
      fn main() {
      }
    END
    setline(1, lines)
    g:WaitForServerFileLoad(1)
    cursor(1, 1)
    :LspCodeAction 2
    g:WaitForServerFileLoad(0)
    assert_true(filereadable('baz/mod.rs'))
    :%bw!
    delete('baz', 'rf')
  finally
    :cd ../..
  endtry
enddef

# Test for :LspCodeAction renaming a file
def g:Test_LspCodeAction_RenameFile()
  :cd xrust_tests/src
  try
    silent! edit ./main.rs
    deletebufline('%', 1, '$')
    g:WaitForServerFileLoad(0)
    writefile([], 'foobar.rs')
    var lines: list<string> =<< trim END
      mod foobar;
      fn main() {
      }
    END
    setline(1, lines)
    g:WaitForServerFileLoad(0)
    cursor(1, 5)
    :LspRename foobaz
    g:WaitForServerFileLoad(0)
    assert_true(filereadable('foobaz.rs'))
    :%bw!
    delete('foobaz.rs')
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
