vim9script
# Unit tests for Vim Language Server Protocol (LSP) clangd client

source common.vim

var lspOpts = {autoComplete: false}
g:LspOptionsSet(lspOpts)

g:LSPTest_modifyDiags = false

var lspServers = [{
      filetype: ['c', 'cpp'],
      path: (exepath('clangd-15') ?? exepath('clangd')),
      args: ['--background-index', '--clang-tidy'],
      initializationOptions: { clangdFileStatus: true },
      customNotificationHandlers: {
        'textDocument/clangd.fileStatus': (lspserver: dict<any>, reply: dict<any>) => {
          g:LSPTest_customNotificationHandlerReplied = true
        }
      },
      processDiagHandler: (diags: list<dict<any>>) => {
        if g:LSPTest_modifyDiags != true
          return diags
        endif

        return diags->map((ix, diag) => {
          diag.message = $'this is overridden'
          return diag
        })
      }
  }]
call LspAddServer(lspServers)

var clangdVerDetail = systemlist($'{shellescape(lspServers[0].path)} --version')
var clangdVerMajor = clangdVerDetail->matchstr('.*version \d\+\..*')->substitute('.* \(\d\+\)\..*', '\1', 'g')->str2nr()
echomsg clangdVerDetail


# Test for formatting a file using LspFormat
def g:Test_LspFormat()
  :silent! edit XLspFormat.c
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

  deletebufline('', 1, '$')
  # shrinking multiple lines into a single one works
  setline(1, ['int \', 'i \', '= \', '42;'])
  :redraw!
  :4LspFormat
  assert_equal(['int i = 42;'], getline(1, '$'))
  bw!

  # empty file
  assert_equal('', execute('LspFormat'))

  # file without an LSP server
  edit a.raku
  assert_equal('Error: Language server for "raku" file type supporting "documentFormatting" feature is not found',
	       execute('LspFormat')->split("\n")[0])

  :%bw!
enddef

# Test for formatting a file using 'formatexpr'
def g:Test_LspFormatExpr()
  :silent! edit XLspFormat.c
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
  :silent! edit XshowRefs.c
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
  :lclose
  cursor(1, 5)
  :LspShowReferences
  assert_equal(1, getloclist(0)->len())
  loclist = getloclist(0)
  assert_equal([1, 5], [loclist[0].lnum, loclist[0].col])
  :lclose

  # Test for opening in qf list
  g:LspOptionsSet({useQuickfixForLocations: true})
  cursor(5, 2)
  :LspShowReferences
  sleep 100m
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  :cclose
  var qfl: list<dict<any>> = getqflist()
  assert_equal(3, qfl->len())
  assert_equal(bufnr(), qfl[0].bufnr)
  assert_equal([4, 6], [qfl[0].lnum, qfl[0].col])
  assert_equal([5, 2], [qfl[1].lnum, qfl[1].col])
  assert_equal([6, 6], [qfl[2].lnum, qfl[2].col])
  cursor(1, 5)
  :LspShowReferences
  assert_equal(1, getqflist()->len())
  qfl = getqflist()
  assert_equal([1, 5], [qfl[0].lnum, qfl[0].col])
  :cclose
  g:LspOptionsSet({useQuickfixForLocations: false})

  # Test for maintaining buffer focus
  g:LspOptionsSet({keepFocusInReferences: false})
  :LspShowReferences
  assert_equal('', getwinvar(0, '&buftype'))
  :lclose
  g:LspOptionsSet({keepFocusInReferences: true})

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
  assert_match('XshowRefs', filePopupAttrs.title)
  assert_equal('Symbol References', refPopupAttrs.title)
  assert_equal(10, line('.', ids[0]))
  assert_equal(1, line('.', ids[1]))
  assert_equal(3, line('$', ids[1]))
  feedkeys("jj\<CR>", 'xt')
  assert_equal(12, line('.'))
  assert_equal([], popup_list())
  popup_clear()

  # LspShowReferences should start with the current symbol
  cursor(12, 6)
  :LspPeekReferences
  sleep 50m
  ids = popup_list()
  assert_equal(2, ids->len())
  assert_equal(12, line('.', ids[0]))
  assert_equal(3, line('.', ids[1]))
  feedkeys("\<CR>", 'xt')
  popup_clear()

  bw!

  # empty file
  assert_equal('', execute('LspShowReferences'))

  # file without an LSP server
  edit a.raku
  assert_equal('Error: Language server for "raku" file type supporting "references" feature is not found',
	       execute('LspShowReferences')->split("\n")[0])

  :%bw!
enddef

# Test for LSP diagnostics
def g:Test_LspDiag()
  :silent! edit XLspDiag.c
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
  :LspDiag show
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
  var output = execute('LspDiag current')->split("\n")
  assert_equal('Warn: No diagnostic messages found for current line', output[0])
  :LspDiag first
  assert_equal([3, 14], [line('.'), col('.')])
  output = execute('LspDiag current')->split("\n")
  assert_equal("Expected ';' at end of declaration (fix available)", output[0])
  :normal! 0
  :LspDiag here
  assert_equal([3, 14], [line('.'), col('.')])
  :LspDiag next
  assert_equal([5, 2], [line('.'), col('.')])
  :LspDiag next
  assert_equal([7, 2], [line('.'), col('.')])
  output = execute('LspDiag next')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])
  :LspDiag prev
  :LspDiag prev
  :LspDiag prev
  output = execute('LspDiag prev')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])

  # Test for maintaining buffer focus
  g:LspOptionsSet({keepFocusInDiags: false})
  :LspDiag show
  assert_equal('', getwinvar(0, '&buftype'))
  :lclose
  g:LspOptionsSet({keepFocusInDiags: true})

  # :[count]LspDiag next
  cursor(3, 1)
  :2LspDiag next
  assert_equal([5, 2], [line('.'), col('.')])
  :2LspDiag next
  assert_equal([7, 2], [line('.'), col('.')])
  output = execute(':2LspDiag next')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])

  # :[count]LspDiag prev
  cursor(7, 2)
  :4LspDiag prev
  assert_equal([3, 14], [line('.'), col('.')])
  output = execute(':4LspDiag prev')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])

  :%d
  setline(1, ['void blueFunc()', '{', '}'])
  g:WaitForDiags(0)
  output = execute('LspDiag show')->split("\n")
  assert_match('Warn: No diagnostic messages found for', output[0])
  g:LspOptionsSet({showDiagInPopup: true})

  popup_clear()
  :%bw!
enddef

# Test for LSP diagnostics handler
def g:Test_LspProcessDiagHandler()
  g:LSPTest_modifyDiags = true
  g:LspOptionsSet({showDiagInPopup: false})

  :silent! edit XLspProcessDiag.c
  sleep 200m
  var lines: list<string> =<< trim END
    void blueFunc()
    {
	int count, j:
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(1)
  :redraw!
  normal gg

  :LspDiag first
  assert_equal([3, 14], [line('.'), col('.')])

  var output = execute('LspDiag current')->split("\n")
  assert_equal("this is overridden", output[0])

  g:LspOptionsSet({showDiagInPopup: true})
  g:LSPTest_modifyDiags = false
  :%bw!
enddef

# Diag location list should be automatically updated when the list of diags
# changes.
def g:Test_DiagLocListAutoUpdate()
  :silent! edit XdiagLocListAutoUpdate.c
  :sleep 200m
  setloclist(0, [], 'f')
  var lines: list<string> =<< trim END
    int i:
    int j;
  END
  setline(1, lines)
  var bnr = bufnr()
  g:WaitForServerFileLoad(1)
  :redraw!
  var d = lsp#diag#GetDiagsForBuf()[0]
  assert_equal({start: {line: 0, character: 5}, end: {line: 0, character: 6}},
	       d.range)

  :LspDiag show
  assert_equal(1, line('$'))
  wincmd w
  setline(2, 'int j:')
  redraw!
  g:WaitForDiags(2)
  var l = lsp#diag#GetDiagsForBuf()
  assert_equal({start: {line: 0, character: 5}, end: {line: 0, character: 6}},
	       l[0].range)
  assert_equal({start: {line: 1, character: 5}, end: {line: 1, character: 6}},
	       l[1].range)
  wincmd w
  assert_equal(2, line('$'))
  wincmd w
  deletebufline('', 1, '$')
  redraw!
  g:WaitForDiags(0)
  assert_equal([], lsp#diag#GetDiagsForBuf())
  wincmd w
  assert_equal([''], getline(1, '$'))
  :lclose

  setloclist(0, [], 'f')
  :%bw!
enddef

# Test that the client have been able to configure the server to speak utf-32
def g:Test_UnicodeColumnCalc()
  :silent! edit XUnicodeColumn.c
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

  :%bw!
enddef

# Test for multiple LSP diagnostics on the same line
def g:Test_LspDiag_Multi()
  :silent! edit XLspDiagMulti.c
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
  if clangdVerMajor > 14
    g:WaitForServerFileLoad(3)
  else
    g:WaitForServerFileLoad(2)
  endif
  :LspDiag show
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(3, qfl->len())
  if clangdVerMajor > 14
    assert_equal([1, 5, 'E'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  else
    assert_equal([1, 5, 'W'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  endif
  assert_equal([1, 9, 'E'], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  assert_equal([2, 9, 'E'], [qfl[2].lnum, qfl[2].col, qfl[2].type])
  close

  :sleep 100m
  cursor(2, 1)
  assert_equal('', execute('LspDiag prev'))
  assert_equal([1, 9], [line('.'), col('.')])

  assert_equal('', execute('LspDiag prev'))
  assert_equal([1, 5], [line('.'), col('.')])

  var output = execute('LspDiag prev')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])

  assert_equal('', execute('LspDiag prevWrap'))
  assert_equal([2, 9], [line('.'), col('.')])

  cursor(2, 1)
  assert_equal('', execute('LspDiag first'))
  assert_equal([1, 5], [line('.'), col('.')])
  assert_equal('', execute('LspDiag next'))
  assert_equal([1, 9], [line('.'), col('.')])
  cursor(1, 1)
  assert_equal('', execute('LspDiag last'))
  assert_equal([2, 9], [line('.'), col('.')])
  assert_equal('', execute('LspDiag nextWrap'))
  assert_equal([1, 5], [line('.'), col('.')])
  assert_equal('', execute('LspDiag nextWrap'))
  assert_equal([1, 9], [line('.'), col('.')])
  popup_clear()

  # Test for :LspDiag here on a line with multiple diagnostics
  cursor(1, 1)
  :LspDiag here
  assert_equal([1, 5], [line('.'), col('.')])
  var ids = popup_list()
  assert_equal(1, ids->len())
  assert_match('Incompatible pointer to integer', getbufline(ids[0]->winbufnr(), 1, '$')[0])
  popup_clear()
  cursor(1, 6)
  :LspDiag here
  assert_equal([1, 9], [line('.'), col('.')])
  ids = popup_list()
  assert_equal(1, ids->len())
  assert_match('Initializer element is not', getbufline(ids[0]->winbufnr(), 1, '$')[0])
  popup_clear()

  # Line without diagnostics
  cursor(3, 1)
  output = execute('LspDiag here')->split("\n")
  assert_equal('Warn: No more diagnostics found on this line', output[0])

  g:LspOptionsSet({showDiagInPopup: false})
  for i in range(1, 5)
    cursor(1, i)
    output = execute('LspDiag current')->split('\n')
    assert_match('Incompatible pointer to integer', output[0])
  endfor
  for i in range(6, 12)
    cursor(1, i)
    output = execute('LspDiag current')->split('\n')
    assert_match('Initializer element is not ', output[0])
  endfor
  g:LspOptionsSet({showDiagInPopup: true})

  # Check for exact diag ":LspDiag current!"
  g:LspOptionsSet({showDiagInPopup: false})
  for i in range(1, 4)
    cursor(1, i)
    output = execute('LspDiag! current')->split('\n')
    assert_equal('Warn: No diagnostic messages found for current position', output[0])
  endfor

  cursor(1, 5)
  output = execute('LspDiag! current')->split('\n')
  assert_match('Incompatible pointer to integer', output[0])

  for i in range(6, 8)
    cursor(1, i)
    output = execute('LspDiag! current')->split('\n')
    assert_equal('Warn: No diagnostic messages found for current position', output[0])
  endfor

  for i in range(9, 11)
    cursor(1, i)
    output = execute('LspDiag! current')->split('\n')
    assert_match('Initializer element is not ', output[0])
  endfor
  for i in range(12, 12)
    cursor(1, i)
    output = execute('LspDiag! current')->split('\n')
    assert_equal('Warn: No diagnostic messages found for current position', output[0])
  endfor

  g:LspOptionsSet({showDiagInPopup: true})

  # :[count]LspDiag next
  g:LspOptionsSet({showDiagInPopup: false})
  cursor(1, 1)
  :2LspDiag next
  assert_equal([1, 9], [line('.'), col('.')])
  :2LspDiag next
  assert_equal([2, 9], [line('.'), col('.')])
  output = execute(':2LspDiag next')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])

  cursor(1, 1)
  :99LspDiag next
  assert_equal([2, 9], [line('.'), col('.')])
  g:LspOptionsSet({showDiagInPopup: true})

  # :[count]LspDiag prev
  g:LspOptionsSet({showDiagInPopup: false})
  cursor(1, 1)
  :2LspDiag prev
  assert_equal('Warn: No more diagnostics found', output[0])
  cursor(3, 3)
  :2LspDiag prev
  assert_equal([1, 9], [line('.'), col('.')])
  :2LspDiag prev
  assert_equal([1, 5], [line('.'), col('.')])
  output = execute(':2LspDiag prev')->split("\n")
  assert_equal('Warn: No more diagnostics found', output[0])

  cursor(3, 3)
  :99LspDiag prev
  assert_equal([1, 5], [line('.'), col('.')])
  g:LspOptionsSet({showDiagInPopup: true})

  :%bw!
enddef

# Test for highlight diag inline
def g:Test_LspHighlightDiagInline()
  :silent! edit XLspHighlightDiag.c
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

  g:LspOptionsSet({highlightDiagInline: true})

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

  g:LspOptionsSet({highlightDiagInline: false})
  props = prop_list(1, {end_lnum: line('$')})
  assert_equal(0, props->len())

  :%bw!
enddef

# Test for :LspCodeAction
def g:Test_LspCodeAction()
  silent! edit XLspCodeAction.c
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
  silent! edit XLspCodeActionPattern.c
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
  assert_equal('Error: Language server for "raku" file type supporting "codeAction" feature is not found',
	       execute('LspCodeAction')->split("\n")[0])

  :%bw!
enddef

# Test for :LspRename
def g:Test_LspRename()
  silent! edit XLspRename.c
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
  assert_equal('Error: Language server for "raku" file type supporting "rename" feature is not found',
	       execute('LspRename')->split("\n")[0])

  :%bw!
enddef

# Test for :LspSelectionExpand and :LspSelectionShrink
def g:Test_LspSelection()
  silent! edit XLspSelection.c
  sleep 200m
  var lines: list<string> =<< trim END
    void fnSel(int count)
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
  assert_equal('Error: Language server for "raku" file type supporting "selectionRange" feature is not found',
	       execute('LspSelectionExpand')->split("\n")[0])

  :%bw!
enddef

# Test for :LspGotoDefinition, :LspGotoDeclaration and :LspGotoImpl
def g:Test_LspGotoSymbol()
  settagstack(0, {items: []})
  silent! edit XLspGotoSymbol.cpp
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
  assert_equal('symbol declaration is not found', m[1])
  :messages clear
  :LspGotoDefinition
  m = execute('messages')->split("\n")
  assert_equal('symbol definition is not found', m[1])
  :messages clear
  :LspGotoImpl
  m = execute('messages')->split("\n")
  assert_equal('symbol implementation is not found', m[1])
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
  assert_equal('Error: Language server for "raku" file type supporting "definition" feature is not found',
	       execute('LspGotoDefinition')->split("\n")[0])
  assert_equal('Error: Language server for "raku" file type supporting "declaration" feature is not found',
	       execute('LspGotoDeclaration')->split("\n")[0])
  assert_equal('Error: Language server for "raku" file type supporting "implementation" feature is not found',
	       execute('LspGotoImpl')->split("\n")[0])

  :%bw!
enddef

# Test for :LspHighlight
def g:Test_LspHighlight()
  silent! edit XLspHighlight.c
  sleep 200m
  var lines: list<string> =<< trim END
    void f1(int arg)
    {
      int i = arg;
      arg = 2;
      if (arg == 2) {
        arg = 3;
      }
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

  cursor(5, 3) # if (arg == 2) {
  var output = execute('LspHighlight')->split("\n")
  assert_equal('Warn: No highlight for the current position', output[0])
  :%bw!
enddef

# Test for :LspHover
def g:Test_LspHover()
  silent! edit XLspHover.c
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
  if clangdVerMajor > 14
    g:WaitForServerFileLoad(1)
  else
    g:WaitForServerFileLoad(0)
  endif
  cursor(8, 4)
  var output = execute(':LspHover')->split("\n")
  assert_equal([], output)
  var p: list<number> = popup_list()
  assert_equal(1, p->len())
  assert_equal(['### function `f1`  ', '', '---', '→ `int`  ', 'Parameters:  ', '- `int a`', '', '---', '```cpp', 'int f1(int a)', '```'], getbufline(winbufnr(p[0]), 1, '$'))
  popup_close(p[0])
  cursor(7, 1)
  output = execute(':LspHover')->split("\n")
  assert_equal('Warn: No documentation found for current keyword', output[0])
  output = execute(':silent LspHover')->split("\n")
  assert_equal([], output)
  assert_equal([], popup_list())

  # Show current diagnostic as to open another popup.
  # Then we can test that LspHover closes all existing popups
  cursor(10, 6)
  :LspDiag current
  assert_equal(1, popup_list()->len())
  :LspHover
  assert_equal(1, popup_list()->len())
  popup_clear()

  # Show hover information in a preview window
  g:LspOptionsSet({hoverInPreview: true})
  cursor(8, 4)
  :LspHover
  assert_equal([2, 2, 'preview'], [winnr('$'), winnr(), win_gettype(1)])
  assert_equal('LspHover', winbufnr(1)->bufname())
  cursor(9, 9)
  :LspHover
  assert_equal([2, 2, 'preview'], [winnr('$'), winnr(), win_gettype(1)])
  g:LspOptionsSet({hoverInPreview: false})
  :pclose

  :%bw!
enddef

# Test for :LspShowSignature
def g:Test_LspShowSignature()
  silent! edit XLspShowSignature.c
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
  silent! edit XLspSymbolSearch.c
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
  feedkeys(":LspSymbolSearch lsptest_funcB\<CR>", "xt")
  assert_equal([5, 6], [line('.'), col('.')])

  cursor(1, 1)
  feedkeys(":LspSymbolSearch lsptest_func\<CR>\<Down>\<Down>\<CR>", "xt")
  assert_equal([9, 6], [line('.'), col('.')])

  cursor(1, 1)
  feedkeys(":LspSymbolSearch lsptest_func\<CR>A\<BS>B\<CR>", "xt")
  assert_equal([5, 6], [line('.'), col('.')])

  var output = execute(':LspSymbolSearch lsptest_nonexist')->split("\n")
  assert_equal('Warn: Symbol "lsptest_nonexist" is not found', output[0])

  :%bw!
enddef

# Test for :LspIncomingCalls
def g:Test_LspIncomingCalls()
  silent! edit XLspIncomingCalls.c
  sleep 200m
  var lines: list<string> =<< trim END
    void xFuncIncoming(void)
    {
    }

    void aFuncIncoming(void)
    {
      xFuncIncoming();
    }

    void bFuncIncoming(void)
    {
      xFuncIncoming();
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  cursor(1, 6)
  :LspIncomingCalls
  assert_equal([1, 2], [winnr(), winnr('$')])
  var l = getline(1, '$')
  assert_equal('# Incoming calls to "xFuncIncoming"', l[0])
  assert_match('- xFuncIncoming (XLspIncomingCalls.c \[.*\])', l[1])
  assert_match('  + aFuncIncoming (XLspIncomingCalls.c \[.*\])', l[2])
  assert_match('  + bFuncIncoming (XLspIncomingCalls.c \[.*\])', l[3])
  :%bw!
enddef

# Test for :LspOutline
def g:Test_LspOutline()
  silent! edit XLspOutline.c
  sleep 200m
  var lines: list<string> =<< trim END
    void aFuncOutline(void)
    {
    }

    void bFuncOutline(void)
    {
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  var winid = win_getid()
  :LspOutline
  assert_equal(2, winnr('$'))
  var bnum = winbufnr(winid + 1)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))

  # Validate position vert topleft
  assert_equal(['row', [['leaf', winid + 1], ['leaf', winid]]], winlayout())

  # Validate default width is 20
  assert_equal(20, winwidth(winid + 1))

  execute $':{bnum}bw'

  # Validate position vert botright
  g:LspOptionsSet({outlineOnRight: true})
  :LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 2)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(['row', [['leaf', winid], ['leaf', winid + 2]]], winlayout())
  g:LspOptionsSet({outlineOnRight: false})
  execute $':{bnum}bw'

  # Validate <mods> position botright (below)
  :botright LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 3)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(['col', [['leaf', winid], ['leaf', winid + 3]]], winlayout())
  execute $':{bnum}bw'

  # Validate that outlineWinSize works for LspOutline
  g:LspOptionsSet({outlineWinSize: 40})
  :LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 4)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(40, winwidth(winid + 4))
  execute $':{bnum}bw'
  g:LspOptionsSet({outlineWinSize: 20})

  # Validate that <count> works for LspOutline
  :37LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 5)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(37, winwidth(winid + 5))
  execute $':{bnum}bw'

  :%bw!
enddef

# Test for setting the 'tagfunc'
def g:Test_LspTagFunc()
  var lines: list<string> =<< trim END
    void aFuncTag(void)
    {
      xFuncTag();
    }

    void bFuncTag(void)
    {
      xFuncTag();
    }

    void xFuncTag(void)
    {
    }
  END
  writefile(lines, 'Xtagfunc.c')
  :silent! edit Xtagfunc.c
  g:WaitForServerFileLoad(1)
  :setlocal tagfunc=lsp#lsp#TagFunc
  cursor(3, 4)
  :exe "normal \<C-]>"
  assert_equal([11, 6], [line('.'), col('.')])
  cursor(1, 1)
  assert_fails('exe "normal \<C-]>"', 'E433:')

  :set tagfunc&
  :%bw!
  delete('Xtagfunc.c')
enddef

# Test for the LspDiagsUpdated autocmd
def g:Test_LspDiagsUpdated_Autocmd()
  g:LspAutoCmd = 0
  autocmd_add([{event: 'User', pattern: 'LspDiagsUpdated', cmd: 'g:LspAutoCmd = g:LspAutoCmd + 1'}])
  silent! edit XLspDiagsAutocmd.c
  sleep 200m
  var lines: list<string> =<< trim END
    void aFuncDiag(void)
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
  assert_equal(5, g:LspAutoCmd)
enddef

# Test custom notification handlers
def g:Test_LspCustomNotificationHandlers()

  g:LSPTest_customNotificationHandlerReplied = false

  silent! edit XcustomNotification.c
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
  :silent! edit XscanFindIdent.c
  sleep 200m
  var lines: list<string> =<< trim END
    int countFI;
    int fnFI(int a)
    {
      int hello;
      hello =    a;
      return    countFI + 1;
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  :redraw!

  # LspGotoDefinition et al
  cursor(5, 10)
  assert_equal([], execute('LspGotoDefinition')->split("\n"))
  assert_equal([2, 14], [line('.'), col('.')])

  cursor(6, 10)
  assert_equal([], execute('LspGotoDefinition')->split("\n"))
  assert_equal([1, 5], [line('.'), col('.')])

  # LspShowReferences
  cursor(6, 10)
  assert_equal([], execute('LspShowReferences')->split("\n"))
  :lclose

  # LspRename
  cursor(6, 10)
  assert_equal([], execute('LspRename counterFI')->split("\n"))
  sleep 100m
  assert_equal('int counterFI;', getline(1))
  assert_equal('  return    counterFI + 1;', getline(6))

  :%bw!
enddef

# Test for doing omni completion from the first column
def g:Test_OmniComplete_FirstColumn()
  :silent! edit XOmniCompleteFirstColumn.c
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
  :%bw!
enddef

# Test for doing omni completion with a multibyte character
def g:Test_OmniComplete_Multibyte()
  :silent! edit XOmniCompleteMultibyte.c
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
  :%bw!
enddef

# Test for doing omni completion for a struct field
def g:Test_OmniComplete_Struct()
  :silent! edit XOmniCompleteStruct.c
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
  feedkeys("cw\<C-X>\<C-O>\<C-N>\<C-Y>", 'xt')
  assert_equal('    pTest->baz = 20;', getline('.'))
  :%bw!
enddef

# Test for doing omni completion after an opening parenthesis.
# This used to result in an error message.
def g:Test_OmniComplete_AfterParen()
  :silent! edit XOmniCompleteAfterParen.c
  sleep 200m
  var lines: list<string> =<< trim END
    #include <stdio.h>
    void Fn(void)
    {
      printf(
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(2)
  redraw!

  cursor(4, 1)
  feedkeys("A\<C-X>\<C-O>\<C-Y>", 'xt')
  assert_equal('  printf(', getline('.'))
  :%bw!
enddef

# Test for inlay hints
def g:Test_InlayHints()
  :silent! edit XinlayHints.c
  sleep 200m
  var lines: list<string> =<< trim END
    void func1(int a, int b)
    {
    }

    void func2()
    {
      func1(10, 20);
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  assert_equal([], prop_list(7))

  :LspInlayHints enable
  var p = prop_list(7)
  assert_equal([9, 'LspInlayHintsParam'], [p[0].col, p[0].type])
  assert_equal([13, 'LspInlayHintsParam'], [p[1].col, p[1].type])

  :LspInlayHints disable
  assert_equal([], prop_list(7))

  g:LspOptionsSet({showInlayHints: true})
  assert_equal([9, 'LspInlayHintsParam'], [p[0].col, p[0].type])
  assert_equal([13, 'LspInlayHintsParam'], [p[1].col, p[1].type])

  g:LspOptionsSet({showInlayHints: false})
  assert_equal([], prop_list(7))

  :hide enew
  :LspInlayHints enable
  :bprev
  assert_equal([9, 'LspInlayHintsParam'], [p[0].col, p[0].type])
  assert_equal([13, 'LspInlayHintsParam'], [p[1].col, p[1].type])

  :hide enew
  :LspInlayHints disable
  :bprev
  assert_equal([], prop_list(7))

  :%bw!
enddef

# Test for reloading a modified buffer with diags
def g:Test_ReloadBufferWithDiags()
  var lines: list<string> =<< trim END
    void ReloadBufferFunc1(void)
    {
      int a:
    }
  END
  writefile(lines, 'Xreloadbuffer.c')
  :silent! edit Xreloadbuffer.c
  g:WaitForServerFileLoad(1)
  var signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal(3, signs[0].lnum)
  append(0, ['', ''])
  signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal(5, signs[0].lnum)
  :edit!
  sleep 200m
  signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal(3, signs[0].lnum)

  :%bw!
  delete('Xreloadbuffer.c')
enddef

# Test for ":LspDiag" sub commands
def g:Test_LspDiagsSubcmd()
  new XLspDiagsSubCmd.raku

  feedkeys(":LspDiag \<C-A>\<CR>", 'xt')
  assert_equal('LspDiag first current here highlight last next nextWrap prev prevWrap show', @:)
  feedkeys(":LspDiag highlight \<C-A>\<CR>", 'xt')
  assert_equal('LspDiag highlight enable disable', @:)
  assert_equal(['Error: :LspDiag - Unsupported argument "xyz"'],
	       execute('LspDiag xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "first xyz"'],
	       execute('LspDiag first xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "current xyz"'],
	       execute('LspDiag current xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "here xyz"'],
	       execute('LspDiag here xyz')->split("\n"))
  assert_equal(['Error: Argument required for ":LspDiag highlight"'],
	       execute('LspDiag highlight')->split("\n"))
  assert_equal(['Error: :LspDiag highlight - Unsupported argument "xyz"'],
	       execute('LspDiag highlight xyz')->split("\n"))
  assert_equal(['Error: :LspDiag highlight - Unsupported argument "enable xyz"'],
	       execute('LspDiag highlight enable xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "last xyz"'],
	       execute('LspDiag last xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "next xyz"'],
	       execute('LspDiag next xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "prev xyz"'],
	       execute('LspDiag prev xyz')->split("\n"))
  assert_equal(['Error: :LspDiag - Unsupported argument "show xyz"'],
	       execute('LspDiag show xyz')->split("\n"))

  :%bw!
enddef

# Test for the :LspServer command.
def g:Test_LspServer()
  new a.raku
  assert_equal(['Warn: No Lsp servers found for "a.raku"'],
	       execute('LspServer debug on')->split("\n"))
  assert_equal(['Warn: No Lsp servers found for "a.raku"'],
	       execute('LspServer restart')->split("\n"))
  assert_equal(['Warn: No Lsp servers found for "a.raku"'],
	       execute('LspServer show status')->split("\n"))
  assert_equal(['Warn: No Lsp servers found for "a.raku"'],
	       execute('LspServer trace verbose')->split("\n"))
  assert_equal(['Error: LspServer - Unsupported argument "xyz"'],
	       execute('LspServer xyz')->split("\n"))
  assert_equal(['Error: Argument required for ":LspServer debug"'],
	       execute('LspServer debug')->split("\n"))
  assert_equal(['Error: Unsupported argument "xyz"'],
	       execute('LspServer debug xyz')->split("\n"))
  assert_equal(['Error: Unsupported argument "on xyz"'],
	       execute('LspServer debug on xyz')->split("\n"))
  assert_equal(['Error: Argument required for ":LspServer show"'],
	       execute('LspServer show')->split("\n"))
  assert_equal(['Error: Unsupported argument "xyz"'],
	       execute('LspServer show xyz')->split("\n"))
  assert_equal(['Error: Unsupported argument "status xyz"'],
	       execute('LspServer show status xyz')->split("\n"))
  assert_equal(['Error: Argument required for ":LspServer trace"'],
	       execute('LspServer trace')->split("\n"))
  assert_equal(['Error: Unsupported argument "xyz"'],
	       execute('LspServer trace xyz')->split("\n"))
  assert_equal(['Error: Unsupported argument "verbose xyz"'],
	       execute('LspServer trace verbose xyz')->split("\n"))
  :%bw!
enddef

# Test for the diagnostics virtual text text property
def g:Test_DiagVirtualText()
  if !has('patch-9.0.1157')
    # Doesn't support virtual text
    return
  endif
  g:LspOptionsSet({highlightDiagInline: false})
  :silent! edit XdiagVirtualText.c
  sleep 200m
  var lines: list<string> =<< trim END
    void DiagVirtualTextFunc1()
    {
      int i:
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(1)
  redraw!

  var p = prop_list(1, {end_lnum: line('$')})
  assert_equal(0, p->len())

  g:LspOptionsSet({showDiagWithVirtualText: true})
  p = prop_list(1, {end_lnum: line('$')})
  assert_equal(1, p->len())
  assert_equal([3, 'LspDiagVirtualTextError'], [p[0].lnum, p[0].type])

  g:LspOptionsSet({showDiagWithVirtualText: false})
  p = prop_list(1, {end_lnum: line('$')})
  assert_equal(0, p->len())

  g:LspOptionsSet({highlightDiagInline: true})
  :%bw!
enddef

# Test for enabling and disabling the "showDiagWithSign" option.
def g:Test_DiagSigns()
  :silent! edit Xdiagsigns.c
  sleep 200m
  var lines: list<string> =<< trim END
    void DiagSignsFunc1(void)
    {
      int a:
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(1)
  redraw!

  var signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal([1, 3], [signs->len(), signs[0].lnum])

  g:LspOptionsSet({showDiagWithSign: false})
  signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal([], signs)
  g:LspOptionsSet({showDiagWithSign: true})
  signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal([1, 3], [signs->len(), signs[0].lnum])

  # Test for enabling/disabling "autoHighlightDiags"
  g:LspOptionsSet({autoHighlightDiags: false})
  signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal([], signs)
  g:LspOptionsSet({autoHighlightDiags: true})
  signs = sign_getplaced('%', {group: '*'})[0].signs
  assert_equal([1, 3], [signs->len(), signs[0].lnum])

  :%bw!
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
