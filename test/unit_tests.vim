vim9script
# Unit tests for Vim Language Server Protocol (LSP) client

syntax on
filetype on
filetype plugin on
filetype indent on

set rtp+=../
source ../plugin/lsp.vim
var lspServers = [{
      filetype: ['c', 'cpp'],
      path: '/usr/bin/clangd',
      args: ['--background-index', '--clang-tidy']
  }]
lsp#addServer(lspServers)

g:LSPTest = true

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
  :sleep 500m
  assert_equal(['int f1(int i) {', '  int j = 10;', '  return j;', '}'],
							getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['', 'int     i;'])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['', 'int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, [' int i;'])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['  int  i; '])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int  i;', '', '', ''])
  :redraw!
  :LspFormat
  :sleep 500m
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(){int x;int y;x=1;y=2;return x+y;}'])
  :redraw!
  :LspFormat
  :sleep 500m
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
  :sleep 500m
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
  :sleep 500m
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

# Test for showing all the references of a symbol in a file using LSP
def Test_lsp_show_references()
  :silent! edit Xtest.c
  var lines: list<string> =<< trim END
    int count;
    void redFunc()
    {
	int count, i;
	count = 10;
	i = count;
    }
    void blueFunc()
    {
	int count, j;
	count = 20;
	j = count;
    }
  END
  setline(1, lines)
  :redraw!
  cursor(5, 2)
  var bnr: number = bufnr()
  :LspShowReferences
  :sleep 1
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([4, 6], [qfl[0].lnum, qfl[0].col])
  assert_equal([5, 2], [qfl[1].lnum, qfl[1].col])
  assert_equal([6, 6], [qfl[2].lnum, qfl[2].col])
  :only
  cursor(1, 5)
  :LspShowReferences
  :sleep 500m
  qfl = getloclist(0)
  assert_equal(1, qfl->len())
  assert_equal([1, 5], [qfl[0].lnum, qfl[0].col])

  :%bw!
enddef

# Test for LSP diagnostics
def Test_lsp_diags()
  :silent! edit Xtest.c
  var lines: list<string> =<< trim END
    void blueFunc()
    {
	int count, j:
	count = 20;
	j <= count;
	j = 10;
	MyFunc();
    }
  END
  setline(1, lines)
  :sleep 1
  var bnr: number = bufnr()
  :redraw!
  :LspDiagShow
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([3, 14, 'E'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([5, 2, 'W'], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  assert_equal([7, 2, 'W'], [qfl[2].lnum, qfl[2].col, qfl[2].type])
  close
  normal gg
  var output = execute('LspDiagCurrent')->split("\n")
  assert_equal('No diagnostic messages found for current line', output[0])
  :LspDiagFirst
  assert_equal([3, 1], [line('.'), col('.')])
  output = execute('LspDiagCurrent')->split("\n")
  assert_equal("Expected ';' at end of declaration (fix available)", output[0])
  :LspDiagNext
  assert_equal([5, 1], [line('.'), col('.')])
  :LspDiagNext
  assert_equal([7, 1], [line('.'), col('.')])
  output = execute('LspDiagNext')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])
  :LspDiagPrev
  :LspDiagPrev
  :LspDiagPrev
  output = execute('LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])
  :%d
  setline(1, ['void blueFunc()', '{', '}'])
  sleep 500m
  output = execute('LspDiagShow')->split("\n")
  assert_match('No diagnostic messages found for', output[0])

  :%bw!
enddef

# Test for LSP code action
def Test_lsp_codeaction()
  silent! edit Xtest.c
  sleep 500m
  var lines: list<string> =<< trim END
    void testFunc()
    {
	int count;
	count == 20;
    }
  END
  setline(1, lines)
  sleep 500m
  cursor(4, 1)
  redraw!
  g:LSPTest_CodeActionChoice = 1
  :LspCodeAction
  sleep 500m
  assert_equal("\tcount = 20;", getline(4))

  setline(4, "\tcount = 20:")
  cursor(4, 1)
  sleep 500m
  g:LSPTest_CodeActionChoice = 0
  :LspCodeAction
  sleep 500m
  assert_equal("\tcount = 20:", getline(4))

  g:LSPTest_CodeActionChoice = 2
  cursor(4, 1)
  :LspCodeAction
  sleep 500m
  assert_equal("\tcount = 20:", getline(4))

  g:LSPTest_CodeActionChoice = 1
  cursor(4, 1)
  :LspCodeAction
  sleep 500m
  assert_equal("\tcount = 20;", getline(4))

  :%bw!
enddef

# Test for LSP symbol rename
def Test_lsp_rename()
  silent! edit Xtest.c
  sleep 1
  var lines: list<string> =<< trim END
    void F1(int count)
    {
	count = 20;

	++count;
    }

    void F2(int count)
    {
	count = 5;
    }
  END
  setline(1, lines)
  sleep 1
  cursor(1, 1)
  search('count')
  redraw!
  feedkeys(":LspRename\<CR>er\<CR>", "xt")
  sleep 1
  redraw!
  var expected: list<string> =<< trim END
    void F1(int counter)
    {
	counter = 20;

	++counter;
    }

    void F2(int count)
    {
	count = 5;
    }
  END
  assert_equal(expected, getline(1, '$'))
  :%bw!
enddef

# Test for LSP selection range
def Test_lsp_selection()
  silent! edit Xtest.c
  sleep 500m
  var lines: list<string> =<< trim END
    void F1(int count)
    {
        int i;
        for (i = 0; i < 10; i++) {
           count++;
        }
        count = 20;
    }
  END
  setline(1, lines)
  sleep 1
  # start a block-wise visual mode, LspSelectionRange should change this to
  # a characterwise visual mode.
  exe "normal! 1G\<C-V>G\"_y"
  cursor(2, 1)
  redraw!
  :LspSelectionRange
  sleep 1
  redraw!
  normal! y
  assert_equal('v', visualmode())
  assert_equal([2, 8], [line("'<"), line("'>")])
  # start a linewise visual mode, LspSelectionRange should change this to
  # a characterwise visual mode.
  exe "normal! 3GViB\"_y"
  cursor(4, 29)
  redraw!
  :LspSelectionRange
  sleep 1
  redraw!
  normal! y
  assert_equal('v', visualmode())
  assert_equal([4, 5, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])
  :%bw!
enddef

def LspRunTests()
  :set nomore
  :set debug=beep
  delete('results.txt')

  # Edit a dummy C file to start the LSP server
  :edit Xtest.c
  :sleep 500m
  :%bw!

  # Get the list of test functions in this file and call them
  var fns: list<string> = execute('function /Test_')
		    ->split("\n")
		    ->map("v:val->substitute('^def <SNR>\\d\\+_', '', '')")
  for f in fns
    v:errors = []
    v:errmsg = ''
    try
      exe f
    catch
      call add(v:errors, "Error: Test " .. f .. " failed with exception " .. v:exception)
    endtry
    if v:errmsg != ''
      call add(v:errors, "Error: Test " .. f .. " generated error " .. v:errmsg)
    endif
    if !v:errors->empty()
      writefile(v:errors, 'results.txt', 'a')
      writefile([f .. ': FAIL'], 'results.txt', 'a')
    else
      writefile([f .. ': pass'], 'results.txt', 'a')
    endif
  endfor
enddef

LspRunTests()
qall!

# vim: shiftwidth=2 softtabstop=2 noexpandtab
