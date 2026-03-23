vim9script
# Unit tests for Vim Language Server Protocol (LSP) clangd client

import '../autoload/lsp/hover.vim' as hover
import '../autoload/lsp/buffer.vim' as buf
import '../autoload/lsp/signature.vim' as signature

source common.vim

var lspOpts = {autoComplete: false}
g:LspOptionsSet(lspOpts)

g:LSPTest_modifyDiags = false

var clangdPath: string
if has('mac') && executable('brew')
  var brewPrefix = trim(system('brew --prefix'))
  var brewExePath = $'{brewPrefix}/opt/llvm@15/bin/clangd'
  clangdPath = filereadable(brewExePath) ? brewExePath : exepath('clangd')
else
  clangdPath = exepath($'clangd-15') ?? exepath('clangd')
endif

var clangdVerDetail = systemlist($'{shellescape(clangdPath)} --version')
var clangdVerMajor = clangdVerDetail->matchstr('.*version \d\+\..*')->substitute('.* \(\d\+\)\..*', '\1', 'g')->str2nr()
if clangdVerMajor != 15
  if has('mac')
    echoerr $'Clangd version 15 required. Please `brew install llvm@15`'
  elseif executable('apt')
    echoerr $'Clangd version 15 required. Please `apt install clangd-15`'
  else
    echoerr $'Clangd version 15 required. Please install clangd-15'
  endif
endif
echomsg clangdVerDetail

var lspServers = [{
      filetype: ['c', 'cpp'],
      path: clangdPath,
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


# Test for formatting a file using LspFormat
def g:Test_LspFormat()
  :silent! edit XLspFormat.c
  sleep 200m
  var lines: list<string> =<< trim END
    int i;
    int j;
  END
  setline(1, lines)
  :redraw!
  :LspFormat
  var expected: list<string> =<< trim DATA
  int i;
  int j;
  DATA
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END
  int f1(int i)
  {
  int j = 10; return j;
  }
  END
  setline(1, lines)
  :redraw!
  :LspFormat
  expected =<< trim DATA
  int f1(int i) {
    int j = 10;
    return j;
  }
  DATA
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END

  int     i;
  END
  setline(1, lines)
  :redraw!
  :LspFormat
  expected =<< trim DATA

  int i;
  DATA
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END
   int i;
  END
  setline(1, lines)
  :redraw!
  :LspFormat
  expected =<< trim DATA
  int i;
  DATA
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END
    int  i; 
  END
  setline(1, lines)
  :redraw!
  :LspFormat
  expected =<< trim DATA
  int i;
  DATA
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END
  int  i;



  END
  setline(1, lines)
  :redraw!
  :LspFormat
  expected =<< trim DATA
  int i;
  DATA
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END
  int f1(){int x;int y;x=1;y=2;return x+y;}
  END
  setline(1, lines)
  :redraw!
  :LspFormat
  expected =<< trim END
    int f1() {
      int x;
      int y;
      x = 1;
      y = 2;
      return x + y;
    }
  END
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  setline(1, ['', '', '', ''])
  :redraw!
  :LspFormat
  g:WaitForAssert(() => assert_equal([''], getline(1, '$')))

  deletebufline('', 1, '$')
  lines =<< trim END
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
  g:WaitForAssert(() => assert_equal(expected, getline(1, '$')))

  deletebufline('', 1, '$')
  # shrinking multiple lines into a single one works
  setline(1, ['int \', 'i \', '= \', '42;'])
  :redraw!
  :4LspFormat
  g:WaitForAssert(() => assert_equal(['int i = 42;'], getline(1, '$')))
  bw!

  # empty file
  g:WaitForAssert(() => assert_equal('', execute('LspFormat')))

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

# Tests for formatting using plug mappings
def g:Test_LspFormat_PlugMappings()
  # Note: clangd range formatting sometimes appies beyond the specified range,
  # which is why there is a dummy function between the indented sets of ints
  edit! XLspFormat.c
  sleep 200m
  nmap gq <plug>(LspFormat)
  setline(1, ['  int i;', '  int j;'])
  setline(3, ['', 'void foo() {}', ''])
  setline(6, ['  int x;', '  int y;'])
  redraw!
  feedkeys('gqap', 'x')
  assert_equal(['int i;', 'int j;'], getline(1, 2))
  assert_equal(['  int x;', '  int y;'], getline(6, 7))
  nunmap gq

  deletebufline('', 1, '$')
  xmap gq <plug>(LspFormat)
  setline(1, ['  int i;', '  int j;'])
  setline(3, ['', 'void foo() {}', ''])
  setline(6, ['  int x;', '  int y;'])
  redraw!
  feedkeys('vapgq', 'x')
  assert_equal(['int i;', 'int j;'], getline(1, 2))
  assert_equal(['  int x;', '  int y;'], getline(6, 7))
  xunmap gq

  :%bw!
enddef

# Test for formatting a file using 'formatprg'
def g:Test_LspFormat_Fallback()
  # Enable fallback to Vim built-in formatting.
  g:LspOptionsSet({formatFallback: true})

  # Case 1: No range provided, expect whole-buffer fallback via "1GgqG".
  silent! edit XformatFallback.raku
  setlocal formatexpr=
  setlocal formatprg=
  setlocal textwidth=20
  setlocal formatoptions=t

  setline(1, ['one two three four five six seven eight nine ten'])
  redraw!

  var out = execute('LspFormat')->split("\n")
  assert_equal('Warn: Formatting unsupported; falling back to built-in.', out[0])
  assert_equal([
        'one two three four',
        'five six seven eight',
        'nine ten',
      ], getline(1, '$'))

  # Case 2: Range provided, expect range fallback via "{line1}Ggq{line2}G".
  setlocal textwidth=12
  deletebufline('', 1, '$')
  setline(1, [
        'KEEP1',
        'one two three four five',
        'six seven eight nine ten',
        '',
        'KEEP5',
      ])
  redraw!

  out = execute(':2,3LspFormat')->split("\n")
  assert_equal('Warn: Formatting unsupported; falling back to built-in.', out[0])
  assert_equal([
        'KEEP1',
        'one two',
        'three four',
        'five six',
        'seven eight',
        'nine ten',
        '',
        'KEEP5',
      ], getline(1, '$'))

  # Restore default to avoid impacting other tests.
  g:LspOptionsSet({formatFallback: false})
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

  cursor(4, 1)
  :LspCodeAction only:quickfix#2
  assert_equal("\tif (count == 1) {", getline(4))
  bw!

  # empty file
  assert_equal('', execute('LspCodeAction'))

  # file without an LSP server
  edit a.raku
  assert_equal('Error: Language server for "raku" file type supporting "codeAction" feature is not found',
	       execute('LspCodeAction')->split("\n")[0])
  assert_equal('Error: Language server for "raku" file type supporting "codeAction" feature is not found',
	       execute('LspFixAll')->split("\n")[0])
  assert_equal('Error: Language server for "raku" file type supporting "codeAction" feature is not found',
	       execute('LspOrganizeImports')->split("\n")[0])

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

  # Re-running :LspHover at the same position should replace the existing
  # hover popup, not create additional hover popups.
  :LspHover
  assert_equal(1, popup_list()->len())
  var activeHoverPopups = popup_list()
  popup_close(activeHoverPopups[0])
  cursor(7, 1)
  output = execute(':LspHover')->split("\n")
  assert_equal('Warn: No documentation found for current keyword', output[0])
  output = execute(':silent LspHover')->split("\n")
  assert_equal([], output)
  assert_equal([], popup_list())

  # Open a diagnostics popup first, then request hover.
  # Expect both popups to coexist: :LspHover should manage only its own popup
  # and must not close unrelated popups.
  cursor(10, 6)
  :LspDiag current
  assert_equal(1, popup_list()->len())
  :LspHover
  assert_equal(2, popup_list()->len())
  popup_clear()

  # When hoverInPreview is enabled, :LspHover should render into the preview
  # window named "LspHover" and reuse that preview window across calls.
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

  var hoverServer = buf.CurbufGetServerChecked('hover')

  # Directly feed a synthetic plaintext hover reply and verify
  #   1) lines are preserved as-is, and
  #   2) the hover buffer filetype is set to "text".
  hover.HoverReply(hoverServer,
    {contents: {kind: 'plaintext', value: "line one\nline two"}},
    'silent')
  p = popup_list()
  assert_equal(1, p->len())
  assert_equal(['line one', 'line two'], getbufline(winbufnr(p[0]), 1, '$'))
  assert_equal('text', getbufvar(winbufnr(p[0]), '&filetype'))
  popup_clear()

  # Hover cache behavior:
  #   - first lookup at a position is a miss,
  #   - after one successful hover reply, same-position lookup is a hit,
  #   - moving the cursor invalidates the cache,
  #   - changing buffer text (changedtick) invalidates the cache.
  cursor(8, 4)
  var reqctx = hover.HoverRequestContextGet(hoverServer)
  assert_equal(false, hover.HoverShowCached(reqctx, hoverServer, 'silent'))

  :LspHover
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  popup_clear()

  assert_equal(true, hover.HoverShowCached(reqctx, hoverServer, 'silent'))
  assert_equal(1, popup_list()->len())
  popup_clear()

  cursor(9, 9)
  var movedReqctx = hover.HoverRequestContextGet(hoverServer)
  assert_equal(false, hover.HoverShowCached(movedReqctx, hoverServer, 'silent'))

  cursor(8, 4)
  setline(1, getline(1, 1)[0] .. ' ')
  setline(1, 'int f1(int a)')
  var changedReqctx = hover.HoverRequestContextGet(hoverServer)
  assert_equal(false, hover.HoverShowCached(changedReqctx, hoverServer, 'silent'))

  # Simulate an async race: capture request context at position A, move to
  # position B, then deliver a reply for A. The stale reply must be ignored,
  # and must not be shown or cached.
  cursor(8, 4)
  reqctx = hover.HoverRequestContextGet(hoverServer)
  cursor(9, 9)
  hover.HoverReply(hoverServer, {contents: 'stale hover result'}, 'silent', reqctx)
  assert_equal([], popup_list())
  cursor(8, 4)
  assert_equal(false, hover.HoverShowCached(reqctx, hoverServer, 'silent'))

  # Auto-hover scheduling is gated by the option. With hoverOnCursorHold
  # disabled, scheduling should be a no-op.
  g:LspOptionsSet({hoverOnCursorHold: false})
  cursor(8, 4)
  hover.HoverAutoSchedule(bufnr())
  :sleep 20m
  assert_equal([], popup_list())

  # With hoverOnCursorHold enabled, scheduling should trigger a debounced
  # hover request and eventually display a hover popup.
  g:LspOptionsSet({hoverOnCursorHold: true, hoverDelay: 1})
  cursor(8, 4)
  hover.HoverAutoSchedule(bufnr())
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  popup_clear()

  # HoverAutoStop should cancel a pending timer and clear the buffer-local
  # timer handle. Temporarily disable LSPTest shortcut path to ensure a real
  # timer is created.
  var saveLspTest = get(g:, 'LSPTest', false)
  g:LSPTest = false
  g:LspOptionsSet({hoverOnCursorHold: true, hoverDelay: 1000})
  hover.HoverAutoSchedule(bufnr())
  var hoverTimer = getbufvar(bufnr(), 'LspHoverTimer', -1)
  assert_true(hoverTimer != -1)
  hover.HoverAutoStop(bufnr())
  assert_equal(-1, getbufvar(bufnr(), 'LspHoverTimer', -1))
  g:LSPTest = saveLspTest

  g:LspOptionsSet({hoverOnCursorHold: false})

  :%bw!
enddef

# Test for :LspShowSignature
def g:Test_LspShowSignature()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

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

  # Default output should be compact (label only) with highlighted active
  # parameter for the first argument.
  cursor(8, 10)
  :LspShowSignature
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var p: list<number> = popup_list()
  var bnr: number = winbufnr(p[0])
  assert_equal(['MyFunc(int a, int b) -> int'], getbufline(bnr, 1, '$'))
  var expected: dict<any>
  expected = {id: 0, col: 8, end: 1, type: 'signature', length: 5, start: 1}
  expected.type_bufnr = bnr
  assert_equal([expected], prop_list(1, {bufnr: bnr}))

  # Simulate a stale async reply: capture context at this position, move the
  # cursor, then deliver an empty reply for the old context. The visible
  # popup must remain unchanged.
  var sigserver = buf.CurbufGetServerChecked('signatureHelp')
  var reqctx = signature.SignatureRequestContextGet()
  cursor(1, 1)
  signature.SignatureHelp(sigserver, {}, reqctx)
  assert_equal([p[0]], popup_list())

  popup_close(p[0])

  # Editing after the first argument should highlight the second parameter.
  setline(8, '  MyFunc(10, ')
  cursor(8, 13)
  :LspShowSignature
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  p = popup_list()
  bnr = winbufnr(p[0])
  assert_equal(['MyFunc(int a, int b) -> int'], getbufline(bnr, 1, '$'))
  expected = {id: 0, col: 15, end: 1, type: 'signature', length: 5, start: 1}
  expected.type_bufnr = bnr
  assert_equal([expected], prop_list(1, {bufnr: bnr}))

  # Re-invoking should replace/update the popup, not accumulate popups.
  :LspShowSignature
  p = popup_list()
  g:WaitForAssert(() => assert_equal(1, p->len()))

  popup_close(p[0])

  # Echo mode should avoid popup creation while still requesting signature help.
  g:LspOptionsSet({echoSignature: true, showSignatureDocs: false})
  :LspShowSignature
  g:WaitForAssert(() => assert_equal([], popup_list()))

  # Enabling docs should remain compatible with clangd replies.
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: true})
  cursor(8, 13)
  :LspShowSignature
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  p = popup_list()
  bnr = winbufnr(p[0])
  assert_match('^MyFunc(int a, int b) -> int', getbufline(bnr, 1, 1)[0])
  popup_close(p[0])

  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})
  :%bw!
enddef

# Additional signature-help coverage for behavior that is difficult to trigger
# from clangd responses alone.
def g:Test_LspShowSignature_SyntheticSession()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: true})

  silent! edit XLspShowSignatureSynthetic.c
  setline(1, ['void f2(void) {', '  MyFunc(', '}'])
  cursor(2, 9)

  var lspserver = {
    id: 4242,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'MyFunc(int a, int b) -> int',
        documentation: {
          kind: 'markdown',
          value: "Signature details\n\n```c\nMyFunc(1, 2)\n```"
        },
        parameters: [
          {label: 'int a', documentation: 'first argument'},
          {label: 'int b', documentation: 'second argument'}
        ],
        # Explicit null means suppress active-parameter highlight for this
        # signature even when top-level activeParameter is present.
        activeParameter: v:null
      },
      {
        label: 'MyFunc(float a, float b) -> int',
        parameters: [
          {label: 'float a'},
          {label: 'float b'}
        ],
        activeParameter: 1
      }
    ],
    activeSignature: 0,
    activeParameter: 1
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))

  var popups = popup_list()
  var bnr = winbufnr(popups[0])
  assert_equal('lspgfm', getbufvar(bnr, '&filetype'))
  assert_equal('MyFunc(int a, int b) -> int  (1/2)', getbufline(bnr, 1, 1)[0])

  # activeParameter is null on the first signature: no highlight should be set.
  assert_equal([], prop_list(1, {bufnr: bnr}))

  # Empty signature-help result should close the popup and reset the session.
  signature.SignatureHelp(lspserver, {})
  assert_equal([], popup_list())

  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})
  :%bw!
enddef

# Test parameter documentation in signature help (string format)
def g:Test_LspShowSignature_ParameterDocStringFormat()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: true})

  silent! edit XLspShowSignature_ParamDocString.c
  setline(1, ['void f() {', '  Func(', '}'])
  cursor(2, 8)

  var lspserver = {
    id: 5000,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'Func(int x, int y)',
        documentation: 'Main function',
        parameters: [
          {label: 'int x', documentation: 'first parameter (string doc)'},
          {label: 'int y', documentation: 'second parameter (string doc)'}
        ],
        activeParameter: 0
      }
    ],
    activeSignature: 0,
    activeParameter: 0
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var bnr = winbufnr(popups[0])

  # Verify signature label and parameter highlighting
  var lines = getbufline(bnr, 1, '$')
  assert_equal('Func(int x, int y)', lines[0])

  # Verify text property for first parameter 'int x'
  var props = prop_list(1, {bufnr: bnr})
  assert_equal(1, props->len())
  assert_equal('signature', props[0].type)
  assert_equal(6, props[0].col)
  assert_equal(5, props[0].length) # 'int x'

  # Verify parameter doc is present
  assert_match('first parameter', lines->join('\n'))

  popup_close(popups[0])
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})
  :%bw!
enddef

# Test parameter documentation in signature help (markdown format)
def g:Test_LspShowSignature_ParameterDocMarkdown()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: true})

  silent! edit XLspShowSignature_ParamDocMarkdown.c
  setline(1, ['void f() {', '  Process(', '}'])
  cursor(2, 11)

  var lspserver = {
    id: 5001,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'Process(const char* data, int count)',
        documentation: {
          kind: 'markdown',
          value: '# Process Function\nProcesses the data buffer.'
        },
        parameters: [
          {
            label: 'const char* data',
            documentation: {
              kind: 'markdown',
              value: '**Data buffer** - pointer to input data\n'
            }
          },
          {
            label: 'int count',
            documentation: {kind: 'plaintext', value: 'Element count'}
          }
        ],
        activeParameter: 0
      }
    ],
    activeSignature: 0,
    activeParameter: 0
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var bnr = winbufnr(popups[0])

  # Markdown filetype should be set
  assert_equal('lspgfm', getbufvar(bnr, '&filetype'))

  var lines = getbufline(bnr, 1, '$')
  assert_equal('Process(const char* data, int count)', lines[0])

  # Verify markdown content is included
  assert_match('Process Function', lines->join('\n'))

  popup_close(popups[0])
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})
  :%bw!
enddef

# Test out-of-range active parameter falls back to last parameter (variadic)
def g:Test_LspShowSignature_OutOfRangeActiveParam()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

  silent! edit XLspShowSignature_OutOfRange.c
  setline(1, ['void f() {', '  Printf(', '}'])
  cursor(2, 10)

  var lspserver = {
    id: 5002,
    signaturePopup: -1
  }
  # Signature has 3 parameters but activeParameter is 10 (out of range)
  # Should fall back to the last parameter (index 2)
  var sighelp = {
    signatures: [
      {
        label: 'Printf(const char* fmt, ...)',
        parameters: [
          {label: 'const char* fmt'},
          {label: '...'}
        ]
      }
    ],
    activeSignature: 0,
    activeParameter: 10  # Out of range - should clamp to last param
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var bnr = winbufnr(popups[0])

  # Highlight should be on the second parameter '...'
  var props = prop_list(1, {bufnr: bnr})
  assert_equal(1, props->len())
  assert_equal('signature', props[0].type)
  # The '...' should be highlighted
  assert_equal(25, props[0].col) # Position of '...'

  popup_close(popups[0])
  :%bw!
enddef

# Test echo mode signature display
def g:Test_LspShowSignature_EchoMode()
  g:LspOptionsSet({echoSignature: true, showSignatureDocs: false})

  silent! edit XLspShowSignature_Echo.c
  setline(1, ['void f() {', '  Add(', '}'])
  cursor(2, 7)

  var lspserver = {
    id: 5003,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'Add(int a, int b) -> int',
        documentation: 'Adds two integers',
        parameters: [
          {label: 'int a'},
          {label: 'int b'}
        ],
        activeParameter: 0
      }
    ],
    activeSignature: 0,
    activeParameter: 0
  }

  signature.SignatureHelp(lspserver, sighelp)

  # Echo mode should NOT create any popups
  assert_equal([], popup_list())

  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})
  :%bw!
enddef

# Test empty signature response closes popup
def g:Test_LspShowSignature_EmptyResponse()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

  silent! edit XLspShowSignature_Empty.c
  setline(1, ['void f() {', '  Func(', '}'])
  cursor(2, 9)

  var lspserver = {
    id: 5004,
    signaturePopup: -1
  }

  # First, create a valid signature popup
  var sighelp = {
    signatures: [
      {
        label: 'Func(int x)',
        parameters: [{label: 'int x'}],
        activeParameter: 0
      }
    ],
    activeSignature: 0,
    activeParameter: 0
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))

  # Now send an empty response
  signature.SignatureHelp(lspserver, {})
  assert_equal([], popup_list())

  :%bw!
enddef

# Test offset-based parameter label highlighting (UTF-16 encoding)
def g:Test_LspShowSignature_OffsetLabelHighlight()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

  silent! edit XLspShowSignature_OffsetLabel.c
  setline(1, ['void f() {', '  Fn(', '}'])
  cursor(2, 7)

  var lspserver = {
    id: 5005,
    signaturePopup: -1
  }
  # Use array-format label for offset-based highlighting
  var sighelp = {
    signatures: [
      {
        label: 'Fn(int x, double y)',
        parameters: [
          {label: [0, 5]},  # 'Fn(in'
          {label: [8, 14]}  # 'double'
        ],
        activeParameter: 1
      }
    ],
    activeSignature: 0,
    activeParameter: 1
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var bnr = winbufnr(popups[0])

  # Verify text property exists for second parameter
  var props = prop_list(1, {bufnr: bnr})
  assert_equal(1, props->len())
  assert_equal('signature', props[0].type)

  popup_close(popups[0])
  :%bw!
enddef

# Test multi-signature with only one parameter each
def g:Test_LspShowSignature_SimpleOverloads()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

  silent! edit XLspShowSignature_SimpleOverloads.c
  setline(1, ['void f() {', '  Get(', '}'])
  cursor(2, 7)

  var lspserver = {
    id: 5006,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'Get(int)',
        parameters: [{label: 'int'}],
        activeParameter: 0
      },
      {
        label: 'Get(double)',
        parameters: [{label: 'double'}],
        activeParameter: 0
      },
      {
        label: 'Get(void*)  -> void*',
        parameters: [{label: 'void*'}],
        activeParameter: 0
      }
    ],
    activeSignature: 1,  # Start at second overload
    activeParameter: 0
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var bnr = winbufnr(popups[0])

  # Should display second overload with indicator
  assert_equal('Get(double)  (2/3)', getbufline(bnr, 1, 1)[0])

  popup_close(popup_list()[0])
  :%bw!
enddef

# Test signature with no parameters
def g:Test_LspShowSignature_NoParameters()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

  silent! edit XLspShowSignature_NoParams.c
  setline(1, ['void f() {', '  Init(', '}'])
  cursor(2, 9)

  var lspserver = {
    id: 5007,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'Init()',
      }
    ],
    activeSignature: 0,
    activeParameter: null
  }

  signature.SignatureHelp(lspserver, sighelp)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var bnr = winbufnr(popups[0])

  # No parameters, so no highlighting
  var props = prop_list(1, {bufnr: bnr})
  assert_equal([], props)

  popup_close(popups[0])
  :%bw!
enddef

# Test context mismatch rejects stale replies
def g:Test_LspShowSignature_ContextMatch()
  g:LspOptionsSet({echoSignature: false, showSignatureDocs: false})

  silent! edit XLspShowSignature_Context.c
  setline(1, ['int x = 0;', 'void f() {', '  Call(', '}'])
  cursor(3, 8)

  var lspserver = {
    id: 5008,
    signaturePopup: -1
  }
  var sighelp = {
    signatures: [
      {
        label: 'Call(int arg)',
        parameters: [{label: 'int arg'}],
        activeParameter: 0
      }
    ],
    activeSignature: 0,
    activeParameter: 0
  }

  # Capture context at current position
  var reqctx = signature.SignatureRequestContextGet()

  # Display signature
  signature.SignatureHelp(lspserver, sighelp, reqctx)
  g:WaitForAssert(() => assert_equal(1, popup_list()->len()))
  var popups = popup_list()
  var oldPopupId = popups[0]

  # Move to a different position
  cursor(1, 1)

  # Send an old reply for the old context - should be rejected
  var oldSighelp = {
    signatures: [
      {
        label: 'OldCall(float)',
        parameters: [{label: 'float'}],
        activeParameter: 0
      }
    ],
    activeSignature: 0,
    activeParameter: 0
  }
  signature.SignatureHelp(lspserver, oldSighelp, reqctx)

  # Popup should still show the original signature (stale reply was rejected)
  popups = popup_list()
  assert_equal([oldPopupId], popups)

  popup_close(popups[0])
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
  assert_equal(['Function@', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))

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
  assert_equal(['Function@', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(['row', [['leaf', winid], ['leaf', winid + 2]]], winlayout())
  g:LspOptionsSet({outlineOnRight: false})
  execute $':{bnum}bw'

  # Validate <mods> position botright (below)
  :botright LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 3)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function@', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(['col', [['leaf', winid], ['leaf', winid + 3]]], winlayout())
  execute $':{bnum}bw'

  # Validate that outlineWinSize works for LspOutline
  g:LspOptionsSet({outlineWinSize: 40})
  :LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 4)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function@', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(40, winwidth(winid + 4))
  execute $':{bnum}bw'
  g:LspOptionsSet({outlineWinSize: 20})

  # Validate that <count> works for LspOutline
  :37LspOutline
  assert_equal(2, winnr('$'))
  bnum = winbufnr(winid + 5)
  assert_equal('LSP-Outline', bufname(bnum))
  assert_equal(['Function@', '  aFuncOutline', '  bFuncOutline'], getbufline(bnum, 4, '$'))
  assert_equal(37, winwidth(winid + 5))
  execute $':{bnum}bw'

  :%bw!
enddef

# Test for setting the 'tagfunc'
def g:Test_LspTagFunc()
  var lines: list<string> =<< trim END
    void xFuncTag(void)
    {
    }

    void yFuncTag(void)
    {
    }

    void aFuncTag(void)
    {
      xFuncTag();
    }

    void bFuncTag(void)
    {
      yFuncTag();
    }
  END
  writefile(lines, 'Xtagfunc.c')
  :silent! edit Xtagfunc.c
  g:WaitForServerFileLoad(0)
  :setlocal tagfunc=lsp#lsp#TagFunc
  cursor(11, 4)
  :exe "normal \<C-]>"
  assert_equal([1, 6], [line('.'), col('.')])
  cursor(1, 1)
  assert_fails('exe "normal \<C-]>"', 'E433:')

  # Keep the cursor on a different symbol and do an explicit :tag lookup.
  cursor(11, 4)
  :tag yFuncTag
  assert_equal([5, 6], [line('.'), col('.')])

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
  var save_completeopt = &completeopt
  set completeopt+=noselect,noinsert
  feedkeys("A\<C-X>\<C-O>\<C-Y>", 'xt')
  assert_equal('  printf(', getline('.'))
  &completeopt = save_completeopt
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
  assert_equal('LspDiag highlight enable disable toggle', @:)
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

def g:Test_DocumentSymbol()
  :silent! edit Xdocsymbol.c
  sleep 200m
  var lines: list<string> =<< trim END
    void DocSymFunc1(void)
    {
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  v:errmsg = ''
  :LspDocumentSymbol
  sleep 50m
  feedkeys("x\<CR>", 'xt')
  popup_clear()
  assert_equal('', v:errmsg)

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

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
