vim9script
# Unit tests for Vim Language Server Protocol (LSP) clangd client

source common.vim

var lspOpts = {autoComplete: false, highlightDiagInline: true}
g:LspOptionsSet(lspOpts)

var lspServers = [{
      filetype: ['c', 'cpp'],
      path: (exepath('clangd-15') ?? exepath('clangd')),
      args: ['--background-index', '--clang-tidy'],
      initializationOptions: { clangdFileStatus: true },
      customNotificationHandlers: {
        'textDocument/clangd.fileStatus': (lspserver: dict<any>, reply: dict<any>) => {
          g:LSPTest_customNotificationHandlerReplied = true
        }
      }
  }]
call LspAddServer(lspServers)
echomsg systemlist($'{shellescape(lspServers[0].path)} --version')

# Test for formatting a file using LspFormat
def g:Test_LspFormat()
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
  edit a.raku
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspFormat')->split("\n"))

  :%bw!
enddef

# Test for formatting a file using 'formatexpr'
def g:Test_LspFormatExpr()
  :silent! edit Xtest.c
  sleep 200m
  setlocal formatexpr=lsp#lsp#FormatExpr()
  setline(1, ['  int i;', '  int j;'])
  :redraw!
  normal! ggVGgq
  assert_equal(['int i;', 'int j;'], getline(1, '$'))

  # empty line/file
  deletebufline('', 1, '$')
  setline(1, [''])
  redraw!
  normal! ggVGgq
  assert_equal([''], getline(1, '$'))

  setlocal formatexpr&
  :%bw!
enddef

# Test for :LspShowReferences - showing all the references to a symbol in a
# file using LSP
def g:Test_LspShowReferences()
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
  sleep 100m
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  var loclist: list<dict<any>> = getloclist(0)
  assert_equal(bnr, loclist[0].bufnr)
  assert_equal(3, loclist->len())
  assert_equal([4, 6], [loclist[0].lnum, loclist[0].col])
  assert_equal([5, 2], [loclist[1].lnum, loclist[1].col])
  assert_equal([6, 6], [loclist[2].lnum, loclist[2].col])
  :only
  cursor(1, 5)
  :LspShowReferences
  assert_equal(1, getloclist(0)->len())
  loclist = getloclist(0)
  assert_equal([1, 5], [loclist[0].lnum, loclist[0].col])
  :lclose

  # Test for opening in qf list
  g:LspOptionsSet({ useQuickfixForLocations: true })
  cursor(5, 2)
  :LspShowReferences
  sleep 100m
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  var qfl: list<dict<any>> = getqflist()
  assert_equal(3, qfl->len())
  assert_equal(bufnr(), qfl[0].bufnr)
  assert_equal([4, 6], [qfl[0].lnum, qfl[0].col])
  assert_equal([5, 2], [qfl[1].lnum, qfl[1].col])
  assert_equal([6, 6], [qfl[2].lnum, qfl[2].col])
  :only
  cursor(1, 5)
  :LspShowReferences
  assert_equal(1, getqflist()->len())
  qfl = getqflist()
  assert_equal([1, 5], [qfl[0].lnum, qfl[0].col])
  :cclose
  g:LspOptionsSet({ useQuickfixForLocations: false })

  # Test for LspPeekReferences

  # Opening the preview window with an unsaved buffer displays the "E37: No
  # write since last change" error message.  To disable this message, mark the
  # buffer as not modified.
  setlocal nomodified
  cursor(10, 6)
  :LspPeekReferences
  sleep 50m
  var ids = popup_list()
  assert_equal(2, ids->len())
  var filePopupAttrs = ids[0]->popup_getoptions()
  var refPopupAttrs = ids[1]->popup_getoptions()
  assert_match('Xtest', filePopupAttrs.title)
  assert_match('References', refPopupAttrs.title)
  assert_equal(10, line('.', ids[0]))
  assert_equal(3, line('$', ids[1]))
  feedkeys("jj\<CR>", 'xt')
  assert_equal(12, line('.'))
  assert_equal([], popup_list())
  popup_clear()

  bw!

  # empty file
  assert_equal('', execute('LspShowReferences'))

  # file without an LSP server
  edit a.raku
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspShowReferences')->split("\n"))

  :%bw!
enddef

# Test for LSP diagnostics
def g:Test_LspDiag()
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
  g:WaitForServerFileLoad(1)
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
  g:LspOptionsSet({showDiagInPopup: false})
  normal gg
  var output = execute('LspDiagCurrent')->split("\n")
  assert_equal('No diagnostic messages found for current line', output[0])
  :LspDiagFirst
  assert_equal([3, 14], [line('.'), col('.')])
  output = execute('LspDiagCurrent')->split("\n")
  assert_equal("Expected ';' at end of declaration (fix available)", output[0])
  :normal! 0
  :LspDiagHere
  assert_equal([3, 14], [line('.'), col('.')])
  :LspDiagNext
  assert_equal([5, 2], [line('.'), col('.')])
  :LspDiagNext
  assert_equal([7, 2], [line('.'), col('.')])
  output = execute('LspDiagNext')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])
  :LspDiagPrev
  :LspDiagPrev
  :LspDiagPrev
  output = execute('LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  # :[count]LspDiagNext
  cursor(3, 1)
  :2LspDiagNext
  assert_equal([5, 2], [line('.'), col('.')])
  :2LspDiagNext
  assert_equal([7, 2], [line('.'), col('.')])
  output = execute(':2LspDiagNext')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  # :[count]LspDiagPrev
  cursor(7, 2)
  :4LspDiagPrev
  assert_equal([3, 14], [line('.'), col('.')])
  output = execute(':4LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  :%d
  setline(1, ['void blueFunc()', '{', '}'])
  g:WaitForDiags(0)
  output = execute('LspDiagShow')->split("\n")
  assert_match('No diagnostic messages found for', output[0])
  g:LspOptionsSet({showDiagInPopup: true})

  popup_clear()
  :%bw!
enddef

# Test that the client have been able to configure the server to speak utf-32
def g:Test_UnicodeColumnCalc()
  :silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    int count;
    int fn(int a)
    {
      int 😊😊😊😊;
      😊😊😊😊 = a;

      int b;
      b = a;
      return    count + 1;
    }
  END
  setline(1, lines)
  :redraw!

  cursor(5, 1) # 😊😊😊😊 = a;
  search('a')
  assert_equal([],
              execute('LspGotoDefinition')->split("\n"))
  assert_equal([2, 12], [line('.'), col('.')])

  cursor(8, 1) # b = a;
  search('a')
  assert_equal([],
              execute('LspGotoDefinition')->split("\n"))
  assert_equal([2, 12], [line('.'), col('.')])

  bw!
enddef

# Test for multiple LSP diagnostics on the same line
def g:Test_LspDiag_Multi()
  :silent! edit Xtest.c
  sleep 200m

  var bnr: number = bufnr()

  var lines =<< trim END
    int i = "a";
    int j = i;
    int y = 0;
  END
  setline(1, lines)
  :redraw!
  # TODO: Waiting count doesn't include Warning, Info, and Hint diags
  g:WaitForServerFileLoad(3)
  :LspDiagShow
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([1, 5, 'E'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([1, 9, 'E'], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  assert_equal([2, 9, 'E'], [qfl[2].lnum, qfl[2].col, qfl[2].type])
  close

  :sleep 100m
  cursor(2, 1)
  assert_equal('', execute('LspDiagPrev'))
  assert_equal([1, 9], [line('.'), col('.')])

  assert_equal('', execute('LspDiagPrev'))
  assert_equal([1, 5], [line('.'), col('.')])

  var output = execute('LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  cursor(2, 1)
  assert_equal('', execute('LspDiagFirst'))
  assert_equal([1, 5], [line('.'), col('.')])
  assert_equal('', execute('LspDiagNext'))
  assert_equal([1, 9], [line('.'), col('.')])
  cursor(1, 1)
  assert_equal('', execute('LspDiagLast'))
  assert_equal([2, 9], [line('.'), col('.')])
  popup_clear()

  # Test for :LspDiagHere on a line with multiple diagnostics
  cursor(1, 1)
  :LspDiagHere
  assert_equal([1, 5], [line('.'), col('.')])
  var ids = popup_list()
  assert_equal(1, ids->len())
  assert_match('Incompatible pointer to integer', getbufline(ids[0]->winbufnr(), 1, '$')[0])
  popup_clear()
  cursor(1, 6)
  :LspDiagHere
  assert_equal([1, 9], [line('.'), col('.')])
  ids = popup_list()
  assert_equal(1, ids->len())
  assert_match('Initializer element is not', getbufline(ids[0]->winbufnr(), 1, '$')[0])
  popup_clear()

  # Line without diagnostics
  cursor(3, 1)
  output = execute('LspDiagHere')->split("\n")
  assert_equal('Error: No more diagnostics found on this line', output[0])

  g:LspOptionsSet({showDiagInPopup: false})
  for i in range(1, 5)
    cursor(1, i)
    output = execute('LspDiagCurrent')->split('\n')
    assert_match('Incompatible pointer to integer', output[0])
  endfor
  for i in range(6, 12)
    cursor(1, i)
    output = execute('LspDiagCurrent')->split('\n')
    assert_match('Initializer element is not ', output[0])
  endfor
  g:LspOptionsSet({showDiagInPopup: true})

  # Check for exact diag ":LspDiagCurrent!"
  g:LspOptionsSet({showDiagInPopup: false})
  for i in range(1, 4)
    cursor(1, i)
    output = execute('LspDiagCurrent!')->split('\n')
    assert_match('No diagnostic messages found for current position', output[0])
  endfor

  cursor(1, 5)
  output = execute('LspDiagCurrent!')->split('\n')
  assert_match('Incompatible pointer to integer', output[0])

  for i in range(6, 8)
    cursor(1, i)
    output = execute('LspDiagCurrent!')->split('\n')
    assert_match('No diagnostic messages found for current position', output[0])
  endfor

  for i in range(9, 11)
    cursor(1, i)
    output = execute('LspDiagCurrent!')->split('\n')
    assert_match('Initializer element is not ', output[0])
  endfor
  for i in range(12, 12)
    cursor(1, i)
    output = execute('LspDiagCurrent!')->split('\n')
    assert_match('No diagnostic messages found for current position', output[0])
  endfor

  g:LspOptionsSet({showDiagInPopup: true})

  # :[count]LspDiagNext
  g:LspOptionsSet({showDiagInPopup: false})
  cursor(1, 1)
  :2LspDiagNext
  assert_equal([1, 9], [line('.'), col('.')])
  :2LspDiagNext
  assert_equal([2, 9], [line('.'), col('.')])
  output = execute(':2LspDiagNext')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  cursor(1, 1)
  :99LspDiagNext
  assert_equal([2, 9], [line('.'), col('.')])
  g:LspOptionsSet({showDiagInPopup: true})

  # :[count]LspDiagPrev
  g:LspOptionsSet({showDiagInPopup: false})
  cursor(1, 1)
  :2LspDiagPrev
  assert_equal('Error: No more diagnostics found', output[0])
  cursor(3, 3)
  :2LspDiagPrev
  assert_equal([1, 9], [line('.'), col('.')])
  :2LspDiagPrev
  assert_equal([1, 5], [line('.'), col('.')])
  output = execute(':2LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  cursor(3, 3)
  :99LspDiagPrev
  assert_equal([1, 5], [line('.'), col('.')])
  g:LspOptionsSet({showDiagInPopup: true})

  bw!
enddef

# Test for highlight diag inline
def g:Test_LspHighlightDiagInline()
  :silent! edit Xtest.c
  sleep 200m
  setline(1, [
    'int main()',
    '{',
      '    struct obj obj',
      '',
      '    return 1;',
    '}',
  ])

  # TODO: Waiting count doesn't include Warning, Info, and Hint diags
  g:WaitForDiags(2)

  var props = prop_list(1)
  assert_equal(0, props->len())
  props = prop_list(2)
  assert_equal(0, props->len())
  props = prop_list(3)
  assert_equal(2, props->len())
  assert_equal([
    {'id': 0, 'col': 12, 'type_bufnr': 0, 'end': 1, 'type': 'LspDiagInlineInfo', 'length': 3, 'start': 1},
    {'id': 0, 'col': 16, 'type_bufnr': 0, 'end': 1, 'type': 'LspDiagInlineError', 'length': 3, 'start': 1}
  ], props)
  props = prop_list(4)
  assert_equal(0, props->len())
  props = prop_list(5)
  assert_equal(1, props->len())
  assert_equal([{'id': 0, 'col': 5, 'type_bufnr': 0, 'end': 1, 'type': 'LspDiagInlineError', 'length': 6, 'start': 1}], props)
  props = prop_list(6)
  assert_equal(0, props->len())

  bw!
enddef

# Test for :LspCodeAction
def g:Test_LspCodeAction()
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
  g:WaitForServerFileLoad(0)
  cursor(4, 1)
  redraw!
  :LspCodeAction 1
  assert_equal("\tcount = 20;", getline(4))

  setline(4, "\tcount = 20:")
  cursor(4, 1)
  sleep 500m
  :LspCodeAction 0
  assert_equal("\tcount = 20:", getline(4))

  cursor(4, 1)
  :LspCodeAction 2
  assert_equal("\tcount = 20:", getline(4))

  cursor(4, 1)
  :LspCodeAction 1
  assert_equal("\tcount = 20;", getline(4))
  bw!

  # pattern and string prefix
  silent! edit Xtest.c
  sleep 200m
  var lines2: list<string> =<< trim END
    void testFunc()
    {
	int count;
	if (count = 1) {
	}
    }
  END
  setline(1, lines2)
  g:WaitForServerFileLoad(0)
  cursor(4, 1)
  redraw!
  :LspCodeAction use
  assert_equal("\tif (count == 1) {", getline(4))

  setline(4, "\tif (count = 1) {")
  cursor(4, 1)
  sleep 500m
  :LspCodeAction /paren
  assert_equal("\tif ((count = 1)) {", getline(4))

  setline(4, "\tif (count = 1) {")
  cursor(4, 1)
  sleep 500m
  :LspCodeAction NON_EXISTING_PREFIX
  assert_equal("\tif (count = 1) {", getline(4))

  cursor(4, 1)
  :LspCodeAction /NON_EXISTING_REGEX
  assert_equal("\tif (count = 1) {", getline(4))
  bw!

  # empty file
  assert_equal('', execute('LspCodeAction'))

  # file without an LSP server
  edit a.raku
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspCodeAction')->split("\n"))

  :%bw!
enddef

# Test for :LspRename
def g:Test_LspRename()
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
  g:WaitForServerFileLoad(0)
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

  cursor(1, 1)
  search('counter')
  LspRename countvar
  var expected2: list<string> =<< trim END
    void F1(int countvar)
    {
	countvar = 20;

	++countvar;
    }

    void F2(int count)
    {
	count = 5;
    }
  END
  assert_equal(expected2, getline(1, '$'))
  sleep 100m
  bw!

  # empty file
  assert_equal('', execute('LspRename'))

  # file without an LSP server
  edit a.raku
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspRename')->split("\n"))

  :%bw!
enddef

# Test for :LspSelectionExpand and :LspSelectionShrink
def g:Test_LspSelection()
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
  g:WaitForServerFileLoad(0)
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
  edit a.raku
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspSelectionExpand')->split("\n"))

  :%bw!
enddef

# Test for :LspGotoDefinition, :LspGotoDeclaration and :LspGotoImpl
def g:Test_LspGotoSymbol()
  settagstack(0, {items: []})
  silent! edit Xtest.cpp
  sleep 600m
  var lines: list<string> =<< trim END
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
  g:WaitForServerFileLoad(0)

  cursor(21, 6)
  :LspGotoDeclaration
  assert_equal([3, 19], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([21, 6], [line('.'), col('.')])
  assert_equal(1, winnr('$'))

  :LspGotoDefinition
  assert_equal([6, 12], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([21, 6], [line('.'), col('.')])
  assert_equal(1, winnr('$'))

  # Command modifiers
  :topleft LspGotoDefinition
  assert_equal([6, 12], [line('.'), col('.')])
  assert_equal([1, 2], [winnr(), winnr('$')])
  close
  exe "normal! \<C-t>"
  assert_equal([21, 6], [line('.'), col('.')])

  :tab LspGotoDefinition
  assert_equal([6, 12], [line('.'), col('.')])
  assert_equal([2, 2, 1], [tabpagenr(), tabpagenr('$'), winnr('$')])
  tabclose
  exe "normal! \<C-t>"
  assert_equal([21, 6], [line('.'), col('.')])

  # :LspGotoTypeDef
  cursor(21, 2)
  :LspGotoTypeDef
  assert_equal([1, 7], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([21, 2], [line('.'), col('.')])

  # :LspGotoImpl
  cursor(21, 6)
  :LspGotoImpl
  assert_equal([12, 11], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([21, 6], [line('.'), col('.')])

  # FIXME: The following tests are failing in Github CI. Comment out for now.
  if 0
  # Error cases
  :messages clear
  cursor(11, 5)
  :LspGotoDeclaration
  var m = execute('messages')->split("\n")
  assert_equal('Error: symbol declaration is not found', m[1])
  :messages clear
  :LspGotoDefinition
  m = execute('messages')->split("\n")
  assert_equal('Error: symbol definition is not found', m[1])
  :messages clear
  :LspGotoImpl
  m = execute('messages')->split("\n")
  assert_equal('Error: symbol implementation is not found', m[1])
  :messages clear
  endif

  # Test for LspPeekDeclaration
  cursor(21, 6)
  var bnum = bufnr()
  :LspPeekDeclaration
  var plist = popup_list()
  assert_true(1, plist->len())
  assert_equal(bnum, plist[0]->winbufnr())
  assert_equal(3, line('.', plist[0]))
  popup_clear()
  # tag stack should not be changed
  assert_fails("normal! \<C-t>", 'E555:')

  # Test for LspPeekDefinition
  :LspPeekDefinition
  plist = popup_list()
  assert_true(1, plist->len())
  assert_equal(bnum, plist[0]->winbufnr())
  assert_equal(6, line('.', plist[0]))
  popup_clear()
  # tag stack should not be changed
  assert_fails("normal! \<C-t>", 'E555:')

  # FIXME: :LspPeekTypeDef and :LspPeekImpl are supported only with clang-14.
  # This clangd version is not available in Github CI.

  :%bw!

  # empty file
  assert_equal('', execute('LspGotoDefinition'))
  assert_equal('', execute('LspGotoDeclaration'))
  assert_equal('', execute('LspGotoImpl'))

  # file without an LSP server
  edit a.raku
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspGotoDefinition')->split("\n"))
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspGotoDeclaration')->split("\n"))
  assert_equal(['Error: Language server for "raku" file type is not found'],
	       execute('LspGotoImpl')->split("\n"))

  :%bw!
enddef

# Test for :LspHighlight
def g:Test_LspHighlight()
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
  g:WaitForServerFileLoad(0)
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
def g:Test_LspHover()
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
      char *z = "z";
      f1(z);
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(1)
  cursor(8, 4)
  var output = execute(':LspHover')->split("\n")
  assert_equal([], output)
  var p: list<number> = popup_list()
  assert_equal(1, p->len())
  assert_equal(['function f1', '', '→ int', 'Parameters:', '- int a', '', 'int f1(int a)'], getbufline(winbufnr(p[0]), 1, '$'))
  popup_close(p[0])
  cursor(7, 1)
  output = execute(':LspHover')->split("\n")
  assert_equal('No hover messages found for current position', output[0])
  assert_equal([], popup_list())

  # Show current diagnostic as to open another popup.
  # Then we can test that LspHover closes all existing popups
  cursor(10, 6)
  :LspDiagCurrent
  assert_equal(1, popup_list()->len())
  :LspHover
  assert_equal(1, popup_list()->len())
  popup_clear()

  :%bw!


enddef

# Test for :LspShowSignature
def g:Test_LspShowSignature()
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
  g:WaitForServerFileLoad(2)
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

# Test for :LspSymbolSearch
def g:Test_LspSymbolSearch()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    void lsptest_funcA()
    {
    }

    void lsptest_funcB()
    {
    }

    void lsptest_funcC()
    {
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)

  cursor(1, 1)
  feedkeys(":LspSymbolSearch lsptest_funcB\<CR>\<CR>", "xt")
  assert_equal([5, 6], [line('.'), col('.')])

  cursor(1, 1)
  feedkeys(":LspSymbolSearch lsptest_func\<CR>\<Down>\<Down>\<CR>", "xt")
  assert_equal([9, 6], [line('.'), col('.')])

  cursor(1, 1)
  feedkeys(":LspSymbolSearch lsptest_funcA\<CR>\<BS>B\<CR>", "xt")
  assert_equal([5, 6], [line('.'), col('.')])

  var output = execute(':LspSymbolSearch lsptest_nonexist')->split("\n")
  assert_equal(['Error: Symbol "lsptest_nonexist" is not found'], output)

  :%bw!
enddef

# Test for :LspIncomingCalls
def g:Test_LspIncomingCalls()
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
  g:WaitForServerFileLoad(0)
  cursor(1, 6)
  :LspIncomingCalls
  assert_equal([1, 2], [winnr(), winnr('$')])
  var l = getline(1, '$')
  assert_equal('# Incoming calls to "xFunc"', l[0])
  assert_match('- xFunc (Xtest.c \[.*\])', l[1])
  assert_match('  + aFunc (Xtest.c \[.*\])', l[2])
  assert_match('  + bFunc (Xtest.c \[.*\])', l[3])
  :%bw!
enddef

# Test for :LspOutline
def g:Test_LspOutline()
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    void aFunc(void)
    {
    }

    void bFunc(void)
    {
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  :LspOutline
  assert_equal(2, winnr('$'))
  var bnum = winbufnr(1)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function', '  aFunc', '  bFunc'], getbufline(bnum, 4, '$'))
  :%bw!
enddef

# Test for setting the 'tagfunc'
def g:Test_LspTagFunc()
  var lines: list<string> =<< trim END
    void aFunc(void)
    {
      xFunc();
    }

    void bFunc(void)
    {
      xFunc();
    }

    void xFunc(void)
    {
    }
  END
  writefile(lines, 'Xtest.c')
  :silent! edit Xtest.c
  g:WaitForServerFileLoad(1)
  :setlocal tagfunc=lsp#lsp#TagFunc
  cursor(3, 4)
  :exe "normal \<C-]>"
  assert_equal([11, 6], [line('.'), col('.')])
  cursor(1, 1)
  assert_fails('exe "normal \<C-]>"', 'E433: No tags file')

  :set tagfunc&
  :%bw!
  delete('Xtest.c')
enddef

# Test for the LspDiagsUpdated autocmd
def g:Test_LspDiagsUpdated_Autocmd()
  g:LspAutoCmd = 0
  autocmd_add([{event: 'User', pattern: 'LspDiagsUpdated', cmd: 'g:LspAutoCmd = g:LspAutoCmd + 1'}])
  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    void aFunc(void)
    {
	return;
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  setline(3, '    return:')
  redraw!
  g:WaitForDiags(1)
  setline(3, '    return;')
  redraw!
  g:WaitForDiags(0)
  :%bw!
  autocmd_delete([{event: 'User', pattern: 'LspDiagsUpdated'}])
  assert_equal(6, g:LspAutoCmd)
enddef

# Test custom notification handlers
def g:Test_LspCustomNotificationHandlers()

  g:LSPTest_customNotificationHandlerReplied = false

  silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    int a = 1;
    int main(void) {
      return a;
    }
  END
  setline(1, lines)
  g:WaitForAssert(() => assert_equal(true, g:LSPTest_customNotificationHandlerReplied))
  :%bw!
enddef

def g:Test_ScanFindIdent()
  :silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    int count;
    int fn(int a)
    {
      int hello;
      hello =    a;
      return    count + 1;
    }
  END
  setline(1, lines)
  :redraw!

  # LspGotoDefinition et al
  cursor(5, 10)
  assert_equal([],
	       execute('LspGotoDefinition')->split("\n"))
  assert_equal([2, 12], [line('.'), col('.')])

  cursor(6, 10)
  assert_equal([],
	       execute('LspGotoDefinition')->split("\n"))
  assert_equal([1, 5], [line('.'), col('.')])

  # LspShowReferences
  cursor(6, 10)
  assert_equal([],
	       execute('LspShowReferences')->split("\n"))

  # LspRename
  cursor(6, 10)
  assert_equal([],
	       execute('LspRename counter')->split("\n"))
  sleep 100m
  assert_equal('int counter;', getline(1))
  assert_equal('  return    counter + 1;', getline(6))

  bw!
enddef

# Test for doing omni completion from the first column
def g:Test_OmniComplete_FirstColumn()
  :silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    typedef struct Foo_ {
    } Foo_t;

    #define FOO 1
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  feedkeys("G0i\<C-X>\<C-O>", 'xt')
  assert_equal('Foo_t#define FOO 1', getline('.'))
  :bw!
enddef

# Test for doing omni completion from the first column
def g:Test_OmniComplete_Multibyte()
  :silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    #include <string.h>
    void Fn(void)
    {
      int thisVar = 1;
      int len = strlen("©©©©©") + thisVar;
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  cursor(5, 36)
  feedkeys("cwthis\<C-X>\<C-O>", 'xt')
  assert_equal('  int len = strlen("©©©©©") + thisVar;', getline('.'))
  :bw!
enddef

# Test for doing omni completion from the first column
def g:Test_OmniComplete_Struct()
  :silent! edit Xtest.c
  sleep 200m
  var lines: list<string> =<< trim END
    struct test_ {
        int foo;
        int bar;
        int baz;
    };
    void Fn(void)
    {
        struct test_ myTest;
        struct test_ *pTest;
        myTest.bar = 10;
        pTest->bar = 20;
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  cursor(10, 12)
  feedkeys("cwb\<C-X>\<C-O>\<C-N>\<C-Y>", 'xt')
  assert_equal('    myTest.baz = 10;', getline('.'))
  cursor(11, 12)
  feedkeys("cw\<C-X>\<C-O>\<C-N>\<C-N>\<C-Y>", 'xt')
  assert_equal('    pTest->foo = 20;', getline('.'))
  :bw!
enddef

# TODO:
# 1. Add a test for autocompletion with a single match while ignoring case.
#    After the full matched name is typed, the completion popup should still
#    be displayed. e.g.
#
#      int MyVar = 1;
#      int abc = myvar<C-N><C-Y>
# 2. Add a test for jumping to a non-existing symbol definition, declaration.

# Start the C language server.  Returns true on success and false on failure.
def g:StartLangServer(): bool
  return g:StartLangServerWithFile('Xtest.c')
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
