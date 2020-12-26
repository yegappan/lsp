vim9script
# Tests for Vim Language Server Protocol (LSP) client
# To run the tests, just source this file

# Test for formatting a file using LSP
def Test_lsp_formatting()
  :silent! edit Xtest.c
  setline(1, ['  int i;', '  int j;'])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['int i;', 'int j;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(int i)', '{', 'int j = 10; return j;', '}'])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['int f1(int i) {', '  int j = 10;', '  return j;', '}'],
							getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['', 'int     i;'])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['', 'int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, [' int i;'])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['  int  i; '])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int  i;', '', '', ''])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(){int x;int y;x=1;y=2;return x+y;}'])
  :redraw!
  :LspFormat
  :sleep 1
  var expected: list<string> =<< trim END
    int f1() {
      int x;
      int y;
      x = 1;
      y = 2;
      return x + y;
    }
  END
  assert_equal(expected, getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['', '', '', ''])
  :redraw!
  :LspFormat
  :sleep 1
  assert_equal([''], getline(1, '$'))

  deletebufline('', 1, '$')
  var lines: list<string> =<< trim END
    int f1() {
      int i, j;
        for (i = 1; i < 10; i++) { j++; }
        for (j = 1; j < 10; j++) { i++; }
    }
  END
  setline(1, lines)
  :redraw!
  :4LspFormat
  :sleep 1
  expected =<< trim END
    int f1() {
      int i, j;
        for (i = 1; i < 10; i++) { j++; }
        for (j = 1; j < 10; j++) {
          i++;
        }
    }
  END
  assert_equal(expected, getline(1, '$'))

  :%bw!
enddef

def LspRunTests()
  # Edit a dummy C file to start the LSP server
  :edit Xtest.c
  :sleep 1
  :%bw!

  var fns: list<string> = execute('function /Test_')
		    ->split("\n")
		    ->map("v:val->substitute('^def <SNR>\\d\\+_', '', '')")
  for f in fns
    v:errors = []
    exe f
    if v:errors->len() != 0
      new Lsp-Test-Results
      setline(1, ["Error: Test " .. f .. " failed"]->extend(v:errors))
      setbufvar('', '&modified', 0)
      return
    endif
  endfor

  echomsg "Success: All LSP tests have passed"
enddef

LspRunTests()

# vim: shiftwidth=2 softtabstop=2 noexpandtab
