vim9script
# Unit tests for Vim Language Server Protocol (LSP) typescript client

source common.vim
source term_util.vim
source screendump.vim

var lspServers = [{
      filetype: ['typescript', 'javascript'],
      path: exepath('typescript-language-server'),
      args: ['--stdio']
  }]
call LspAddServer(lspServers)
echomsg systemlist($'{lspServers[0].path} --version')

# Test for LSP diagnostics
def g:Test_LspDiag()
  :silent! edit Xtest.ts
  sleep 200m

  var bnr: number = bufnr()

  # This tests that two diagnostics can be on the same line
  var lines: list<string> = [
    '  export obj = {',
    '    foo: 1,',
    '    bar: 2,',
    '    baz: 3',
    '  }'
  ]

  setline(1, lines)
  :sleep 3
  g:WaitForDiags(2)
  :redraw!
  :LspDiagShow
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(2, qfl->len())
  assert_equal([1, 3, 'E'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([1, 10, 'E'], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  close

  :sleep 100m
  cursor(5, 1)
  assert_equal('', execute('LspDiagPrev'))
  assert_equal([1, 10], [line('.'), col('.')])

  assert_equal('', execute('LspDiagPrev'))
  assert_equal([1, 3], [line('.'), col('.')])

  var output = execute('LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  cursor(5, 1)
  assert_equal('', execute('LspDiagFirst'))
  assert_equal([1, 3], [line('.'), col('.')])
  assert_equal('', execute('LspDiagNext'))
  assert_equal([1, 10], [line('.'), col('.')])

  g:LspOptionsSet({showDiagInPopup: false})
  for i in range(1, 3)
    cursor(1, i)
    output = execute('LspDiagCurrent')->split('\n')
    assert_equal('Declaration or statement expected.', output[0])
  endfor
  for i in range(4, 16)
    cursor(1, i)
    output = execute('LspDiagCurrent')->split('\n')
    assert_equal('Cannot find name ''obj''.', output[0])
  endfor
  g:LspOptionsSet({showDiagInPopup: true})

  :%bw!
enddef

def g:Test_LspGoto()
  :silent! edit Xtest.ts
  sleep 200m

  var lines: list<string> = [
    'function B(val: number): void;',
    'function B(val: string): void;',
    'function B(val: string | number) {',
    '	console.log(val);',
    '	return void 0;',
    '}',
    'typeof B;',
    'B(1);',
    'B("1");'
  ]

  setline(1, lines)
  :sleep 3

  cursor(8, 1)
  assert_equal('', execute('LspGotoDefinition'))
  assert_equal([1, 10], [line('.'), col('.')])

  cursor(9, 1)
  assert_equal('', execute('LspGotoDefinition'))
  assert_equal([2, 10], [line('.'), col('.')])

  cursor(9, 1)
  assert_equal('', execute('LspGotoDefinition'))
  assert_equal([2, 10], [line('.'), col('.')])

  cursor(7, 8)
  assert_equal('', execute('LspGotoDefinition'))
  sleep 200m
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bufnr(), qfl[0].bufnr)
  assert_equal(3, qfl->len())
  assert_equal([1, 10, ''], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([2, 10, ''], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  assert_equal([3, 10, ''], [qfl[2].lnum, qfl[2].col, qfl[2].type])
  lclose

  # Opening the preview window with an unsaved buffer displays the "E37: No
  # write since last change" error message.  To disable this message, mark the
  # buffer as not modified.
  setlocal nomodified
  cursor(7, 8)
  :LspPeekDefinition
  sleep 10m
  var ids = popup_list()
  assert_equal(2, ids->len())
  var filePopupAttrs = ids[0]->popup_getoptions()
  var refPopupAttrs = ids[1]->popup_getoptions()
  assert_match('Xtest', filePopupAttrs.title)
  assert_match('Definitions', refPopupAttrs.title)
  assert_equal(1, line('.', ids[0]))
  assert_equal(3, line('$', ids[1]))
  feedkeys("jj\<CR>", 'xt')
  assert_equal(3, line('.'))
  assert_equal([], popup_list())
  popup_clear()
enddef

# Test for auto-completion.  Make sure that only keywords that matches with the
# keyword before the cursor are shown.
# def g:Test_LspCompletion1()
#   var lines =<< trim END
#     const http = require('http')
#     http.cr
#   END
#   writefile(lines, 'Xcompletion1.js')
#   var buf = g:RunVimInTerminal('--cmd "silent so start_tsserver.vim" Xcompletion1.js', {rows: 10, wait_for_ruler: 1})
#   sleep 5
#   term_sendkeys(buf, "GAe")
#   g:TermWait(buf)
#   g:VerifyScreenDump(buf, 'Test_tsserver_completion_1', {})
#   term_sendkeys(buf, "\<BS>")
#   g:TermWait(buf)
#   g:VerifyScreenDump(buf, 'Test_tsserver_completion_2', {})
# 
#   g:StopVimInTerminal(buf)
#   delete('Xcompletion1.js')
# enddef

# Start the typescript language server.  Returns true on success and false on
# failure.
def g:StartLangServer(): bool
  return g:StartLangServerWithFile('Xtest.ts')
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
