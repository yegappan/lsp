vim9script
# Unit tests for Vim Language Server Protocol (LSP) golang client

source common.vim

var lspServers = [{
      filetype: ['go'],
      path: exepath('gopls'),
      args: ['serve']
  }]
call LspAddServer(lspServers)
echomsg systemlist($'{lspServers[0].path} version')

# Test for :LspGotoDefinition, :LspGotoDeclaration, etc.
# This test also tests that multiple locations will be
# shown in a list or popup
def g:Test_LspGoto()
  :silent! edit Xtest.go
  var bnr = bufnr()

  sleep 200m

  var lines =<< trim END
    package main

    type A/*goto implementation*/ interface {
            Hello()
    }

    type B struct{}

    func (b *B) Hello() {}

    type C struct{}

    func (c *C) Hello() {}

    func main() {
    }
  END
  
  setline(1, lines)
  :redraw!
  g:WaitForServerFileLoad(0)

  cursor(9, 10)
  :LspGotoDefinition
  assert_equal([7, 6], [line('.'), col('.')])
  exe "normal! \<C-t>"
  assert_equal([9, 10], [line('.'), col('.')])

  cursor(9, 13)
  :LspGotoImpl
  assert_equal([4, 9], [line('.'), col('.')])

  cursor(13, 13)
  :LspGotoImpl
  assert_equal([4, 9], [line('.'), col('.')])

  # Two implementions needs to be shown in a location list
  cursor(4, 9)
  assert_equal('', execute('LspGotoImpl'))
  sleep 200m
  var loclist: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(2, loclist->len())
  assert_equal(bnr, loclist[0].bufnr)
  assert_equal([9, 13, ''], [loclist[0].lnum, loclist[0].col, loclist[0].type])
  assert_equal([13, 13, ''], [loclist[1].lnum, loclist[1].col, loclist[1].type])
  lclose

  # Two implementions needs to be shown in a quickfix list
  g:LspOptionsSet({ useQuickfixForLocations: true })
  cursor(4, 9)
  assert_equal('', execute('LspGotoImpl'))
  sleep 200m
  var qfl: list<dict<any>> = getqflist()
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(2, qfl->len())
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal([9, 13, ''], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([13, 13, ''], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  cclose
  g:LspOptionsSet({ useQuickfixForLocations: false })

  # Two implementions needs to be peeked in a popup
  cursor(4, 9)
  :LspPeekImpl
  sleep 10m
  var ids = popup_list()
  assert_equal(2, ids->len())
  var filePopupAttrs = ids[0]->popup_getoptions()
  var refPopupAttrs = ids[1]->popup_getoptions()
  assert_match('Xtest', filePopupAttrs.title)
  assert_match('Implementation', refPopupAttrs.title)
  assert_equal(9, line('.', ids[0])) # current line in left panel
  assert_equal(2, line('$', ids[1])) # last line in right panel
  feedkeys("j\<CR>", 'xt')
  assert_equal(13, line('.'))
  assert_equal([], popup_list())
  popup_clear()

  # Jump to the first implementation
  cursor(4, 9)
  assert_equal('', execute(':1LspGotoImpl'))
  assert_equal([9, 13], [line('.'), col('.')])

  # Jump to the second implementation
  cursor(4, 9)
  assert_equal('', execute(':2LspGotoImpl'))
  assert_equal([13, 13], [line('.'), col('.')])
  bw!
enddef

# Start the gopls language server.  Returns true on success and false on
# failure.
def g:StartLangServer(): bool
  return g:StartLangServerWithFile('Xtest.go')
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
