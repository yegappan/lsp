vim9script
# Unit tests for Vim Language Server Protocol (LSP) client

syntax on
filetype on
filetype plugin on
filetype indent on

# Set the $LSP_PROFILE environment variable to profile the LSP plugin
var do_profile: bool = false
if exists('$LSP_PROFILE')
  do_profile = true
endif

if do_profile
  # profile the LSP plugin
  profile start lsp_profile.txt
  profile! file */lsp/*
endif

source ../plugin/lsp.vim
var lspServers = [{
      filetype: ['c', 'cpp'],
      path: '/usr/bin/clangd-12',
      args: ['--background-index', '--clang-tidy']
  }]
call LspAddServer(lspServers)

g:LSPTest = true

# The WaitFor*() functions are reused from the Vim test suite.
#
# Wait for up to five seconds for "assert" to return zero.  "assert" must be a
# (lambda) function containing one assert function.  Example:
#	call WaitForAssert({-> assert_equal("dead", job_status(job)})
#
# A second argument can be used to specify a different timeout in msec.
#
# Return zero for success, one for failure (like the assert function).
func WaitForAssert(assert, ...)
  let timeout = get(a:000, 0, 5000)
  if WaitForCommon(v:null, a:assert, timeout) < 0
    return 1
  endif
  return 0
endfunc

# Either "expr" or "assert" is not v:null
# Return the waiting time for success, -1 for failure.
func WaitForCommon(expr, assert, timeout)
  " using reltime() is more accurate, but not always available
  let slept = 0
  if exists('*reltimefloat')
    let start = reltime()
  endif

  while 1
    if type(a:expr) == v:t_func
      let success = a:expr()
    elseif type(a:assert) == v:t_func
      let success = a:assert() == 0
    else
      let success = eval(a:expr)
    endif
    if success
      return slept
    endif

    if slept >= a:timeout
      break
    endif
    if type(a:assert) == v:t_func
      " Remove the error added by the assert function.
      call remove(v:errors, -1)
    endif

    sleep 10m
    if exists('*reltimefloat')
      let slept = float2nr(reltimefloat(reltime(start)) * 1000)
    else
      let slept += 10
    endif
  endwhile

  return -1  " timed out
endfunc

# Test for formatting a file using LspFormat
def Test_LspFormat()
  :silent! edit Xtest.c
  sleep 200m
  setline(1, ['  int i;', '  int j;'])
  :redraw!
  :LspFormat
  assert_equal(['int i;', 'int j;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(int i)', '{', 'int j = 10; return j;', '}'])
  :redraw!
  :LspFormat
  assert_equal(['int f1(int i) {', '  int j = 10;', '  return j;', '}'],
							getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['', 'int     i;'])
  :redraw!
  :LspFormat
  assert_equal(['', 'int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, [' int i;'])
  :redraw!
  :LspFormat
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['  int  i; '])
  :redraw!
  :LspFormat
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int  i;', '', '', ''])
  :redraw!
  :LspFormat
  assert_equal(['int i;'], getline(1, '$'))

  deletebufline('', 1, '$')
  setline(1, ['int f1(){int x;int y;x=1;y=2;return x+y;}'])
  :redraw!
  :LspFormat
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
  bw!

  # empty file
  assert_equal('', execute('LspFormat'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspFormat')->split("\n"))

  :%bw!
enddef

# Test for :LspShowReferences - showing all the references to a symbol in a
# file using LSP
def Test_LspShowReferences()
  :silent! edit Xtest.c
  sleep 200m
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
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([4, 6], [qfl[0].lnum, qfl[0].col])
  assert_equal([5, 2], [qfl[1].lnum, qfl[1].col])
  assert_equal([6, 6], [qfl[2].lnum, qfl[2].col])
  :only
  cursor(1, 5)
  :LspShowReferences
  assert_equal(1, getloclist(0)->len())
  qfl = getloclist(0)
  assert_equal([1, 5], [qfl[0].lnum, qfl[0].col])
  bw!

  # empty file
  assert_equal('', execute('LspShowReferences'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspShowReferences')->split("\n"))

  :%bw!
enddef

# Test for LSP diagnostics
def Test_LspDiag()
  :silent! edit Xtest.c
  sleep 200m
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

# Test for :LspCodeAction
def Test_LspCodeAction()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    void testFunc()
    {
	int count;
	count == 20;
    }
  END
  setline(1, lines)
  sleep 1
  cursor(4, 1)
  redraw!
  g:LSPTest_CodeActionChoice = 1
  :LspCodeAction
  assert_equal("\tcount = 20;", getline(4))

  setline(4, "\tcount = 20:")
  cursor(4, 1)
  sleep 500m
  g:LSPTest_CodeActionChoice = 0
  :LspCodeAction
  assert_equal("\tcount = 20:", getline(4))

  g:LSPTest_CodeActionChoice = 2
  cursor(4, 1)
  :LspCodeAction
  assert_equal("\tcount = 20:", getline(4))

  g:LSPTest_CodeActionChoice = 1
  cursor(4, 1)
  :LspCodeAction
  assert_equal("\tcount = 20;", getline(4))
  bw!

  # empty file
  assert_equal('', execute('LspCodeAction'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspCodeAction')->split("\n"))

  :%bw!
enddef

# Test for :LspRename
def Test_LspRename()
  silent! edit Xtest.c
  sleep 200m
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
  bw!

  # empty file
  assert_equal('', execute('LspRename'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspRename')->split("\n"))

  :%bw!
enddef

# Test for :LspSelectionExpand and :LspSelectionShrink
def Test_LspSelection()
  silent! edit Xtest.c
  sleep 200m
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
  # start a block-wise visual mode, LspSelectionExpand should change this to
  # a characterwise visual mode.
  exe "normal! 1G\<C-V>G\"_y"
  cursor(2, 1)
  redraw!
  :LspSelectionExpand
  redraw!
  normal! y
  assert_equal('v', visualmode())
  assert_equal([2, 8], [line("'<"), line("'>")])
  # start a linewise visual mode, LspSelectionExpand should change this to
  # a characterwise visual mode.
  exe "normal! 3GViB\"_y"
  cursor(4, 29)
  redraw!
  :LspSelectionExpand
  redraw!
  normal! y
  assert_equal('v', visualmode())
  assert_equal([4, 5, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])

  # Expand the visual selection
  xnoremap <silent> le <Cmd>LspSelectionExpand<CR>
  xnoremap <silent> ls <Cmd>LspSelectionShrink<CR>
  cursor(5, 8)
  normal vley
  assert_equal([5, 8, 5, 12], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vleley
  assert_equal([5, 8, 5, 14], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vleleley
  assert_equal([4, 30, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vleleleley
  assert_equal([4, 5, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vleleleleley
  assert_equal([2, 1, 8, 1], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vleleleleleley
  assert_equal([1, 1, 8, 1], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vleleleleleleley
  assert_equal([1, 1, 8, 1], [line("'<"), col("'<"), line("'>"), col("'>")])

  # Shrink the visual selection
  cursor(5, 8)
  normal vlsy
  assert_equal([5, 8, 5, 12], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vlelsy
  assert_equal([5, 8, 5, 12], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vlelelsy
  assert_equal([5, 8, 5, 12], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vlelelelsy
  assert_equal([5, 8, 5, 14], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vlelelelelsy
  assert_equal([4, 30, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vlelelelelelsy
  assert_equal([4, 5, 6, 5], [line("'<"), col("'<"), line("'>"), col("'>")])
  cursor(5, 8)
  normal vlelelelelelelsy
  assert_equal([2, 1, 8, 1], [line("'<"), col("'<"), line("'>"), col("'>")])

  xunmap le
  xunmap ls
  bw!

  # empty file
  assert_equal('', execute('LspSelectionExpand'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspSelectionExpand')->split("\n"))

  :%bw!
enddef

# Test for :LspGotoDefinition, :LspGotoDeclaration and :LspGotoImpl
def Test_LspGotoDefinition()
  silent! edit Xtest.cpp
  sleep 200m
  var lines: list<string> =<< trim END
    #include <iostream>
    using namespace std;

    class base {
	public:
	    virtual void print();
    };

    void base::print()
    {
    }

    class derived : public base {
	public:
	    void print() {}
    };

    void f1(void)
    {
	base *bp;
	derived d;
	bp = &d;

	bp->print();
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(24, 6)
  :LspGotoDeclaration
  assert_equal([6, 19], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([24, 6], [line('.'), col('.')])
  :LspGotoDefinition
  assert_equal([9, 12], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([24, 6], [line('.'), col('.')])
  # FIXME: The following test is failing in Github CI
  # :LspGotoImpl
  # assert_equal([15, 11], [line('.'), col('.')])
  # exe "normal! \<C-t>"
  # assert_equal([24, 6], [line('.'), col('.')])

  # Error cases
  # FIXME: The following tests are failing in Github CI. Comment out for now.
  if 0
  :messages clear
  cursor(14, 5)
  :LspGotoDeclaration
  var m = execute('messages')->split("\n")
  assert_equal('Error: declaration is not found', m[1])
  :messages clear
  :LspGotoDefinition
  m = execute('messages')->split("\n")
  assert_equal('Error: definition is not found', m[1])
  :messages clear
  :LspGotoImpl
  m = execute('messages')->split("\n")
  assert_equal('Error: implementation is not found', m[1])
  endif
  bw!

  # empty file
  assert_equal('', execute('LspGotoDefinition'))
  assert_equal('', execute('LspGotoDeclaration'))
  assert_equal('', execute('LspGotoImpl'))

  # file without an LSP server
  edit a.b
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspGotoDefinition')->split("\n"))
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspGotoDeclaration')->split("\n"))
  assert_equal(['Error: LSP server for "a.b" is not found'],
	       execute('LspGotoImpl')->split("\n"))

  :%bw!
enddef

# Test for :LspHighlight
def Test_LspHighlight()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    void f1(int arg)
    {
      int i = arg;
      arg = 2;
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(1, 13)
  :LspHighlight
  var expected: dict<any>
  expected = {id: 0, col: 13, end: 1, type: 'LspTextRef', length: 3, start: 1}
  expected.type_bufnr = 0
  assert_equal([expected], prop_list(1))
  expected = {id: 0, col: 11, end: 1, type: 'LspReadRef', length: 3, start: 1}
  expected.type_bufnr = 0
  assert_equal([expected], prop_list(3))
  expected = {id: 0, col: 3, end: 1, type: 'LspWriteRef', length: 3, start: 1}
  expected.type_bufnr = 0
  assert_equal([expected], prop_list(4))
  :LspHighlightClear
  assert_equal([], prop_list(1))
  assert_equal([], prop_list(3))
  assert_equal([], prop_list(4))
  :%bw!
enddef

# Test for :LspHover
def Test_LspHover()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    int f1(int a)
    {
      return 0;
    }

    void f2(void)
    {
      f1(5);
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(8, 4)
  :LspHover
  var p: list<number> = popup_list()
  assert_equal(1, p->len())
  assert_equal(['function f1', '', '→ int', 'Parameters:', '- int a', '', 'int f1(int a)'], getbufline(winbufnr(p[0]), 1, '$'))
  popup_close(p[0])
  cursor(7, 1)
  :LspHover
  assert_equal([], popup_list())
  :%bw!
enddef

# Test for :LspShowSignature
def Test_LspShowSignature()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    int MyFunc(int a, int b)
    {
      return 0;
    }

    void f2(void)
    {
      MyFunc( 
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(8, 10)
  :LspShowSignature
  var p: list<number> = popup_list()
  var bnr: number = winbufnr(p[0])
  assert_equal(1, p->len())
  assert_equal(['MyFunc(int a, int b) -> int'], getbufline(bnr, 1, '$'))
  var expected: dict<any>
  expected = {id: 0, col: 8, end: 1, type: 'signature', length: 5, start: 1}
  expected.type_bufnr = bnr
  assert_equal([expected], prop_list(1, {bufnr: bnr}))
  popup_close(p[0])

  setline(line('.'), '  MyFunc(10, ')
  cursor(8, 13)
  :LspShowSignature
  p = popup_list()
  bnr = winbufnr(p[0])
  assert_equal(1, p->len())
  assert_equal(['MyFunc(int a, int b) -> int'], getbufline(bnr, 1, '$'))
  expected = {id: 0, col: 15, end: 1, type: 'signature', length: 5, start: 1}
  expected.type_bufnr = bnr
  assert_equal([expected], prop_list(1, {bufnr: bnr}))
  popup_close(p[0])
  :%bw!
enddef

# Test for :LspIncomingCalls
def Test_LspIncomingCalls()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    void xFunc(void)
    {
    }

    void aFunc(void)
    {
      xFunc();
    }

    void bFunc(void)
    {
      xFunc();
    }
  END
  setline(1, lines)
  :sleep 1
  cursor(1, 6)
  :LspIncomingCalls
  assert_equal(2, winnr('$'))
  var l = getloclist(0)
  assert_equal([7, 3], [l[0].lnum, l[0].col])
  assert_equal('aFunc: xFunc();', l[0].text)
  assert_equal([12, 3], [l[1].lnum, l[1].col])
  assert_equal('bFunc: xFunc();', l[1].text)
  setloclist(0, [], 'f')
  :%bw!
enddef

def LspRunTests()
  :set nomore
  :set debug=beep
  delete('results.txt')

  # Edit a dummy C file to start the LSP server
  :edit Xtest.c
  # Wait for the LSP server to become ready (max 10 seconds)
  var maxcount = 100
  while maxcount > 0 && !g:LspServerReady()
    :sleep 100m
    maxcount -= 1
  endwhile
  :%bw!

  # Get the list of test functions in this file and call them
  var fns: list<string> = execute('function /Test_')
		    ->split("\n")
		    ->map("v:val->substitute('^def <SNR>\\d\\+_', '', '')")
  for f in fns
    v:errors = []
    v:errmsg = ''
    try
      :%bw!
      exe f
    catch
      call add(v:errors, "Error: Test " .. f .. " failed with exception " .. v:exception .. " at " .. v:throwpoint)
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
