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

# Test for :LspGotoDefinition, :LspGotoDeclaration, etc.
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
  :redraw!
  g:WaitForServerFileLoad(0)

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
  var loclist: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(3, loclist->len())
  assert_equal(bufnr(), loclist[0].bufnr)
  assert_equal([1, 10, ''], [loclist[0].lnum, loclist[0].col, loclist[0].type])
  assert_equal([2, 10, ''], [loclist[1].lnum, loclist[1].col, loclist[1].type])
  assert_equal([3, 10, ''], [loclist[2].lnum, loclist[2].col, loclist[2].type])
  lclose

  g:LspOptionsSet({ useQuickfixForLocations: true })
  cursor(7, 8)
  assert_equal('', execute('LspGotoDefinition'))
  sleep 200m
  var qfl: list<dict<any>> = getqflist()
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(3, qfl->len())
  assert_equal(bufnr(), qfl[0].bufnr)
  assert_equal([1, 10, ''], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([2, 10, ''], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  assert_equal([3, 10, ''], [qfl[2].lnum, qfl[2].col, qfl[2].type])
  cclose
  g:LspOptionsSet({ useQuickfixForLocations: false })

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

  bw!
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
