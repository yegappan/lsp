vim9script
# Unit tests for Vim Language Server Protocol (LSP) for various functionality 

import '../autoload/lsp/completion.vim' as completion

# Test for no duplicates in helptags
def g:Test_Helptags()
  :helptags ../doc
enddef

# Regression test for CompletionList.itemDefaults support.
def g:Test_CompletionList_ItemDefaults_EditRange()
  silent! edit XCompletionItemDefaults.vim
  setline(1, ['fo'])
  cursor(1, 3)

  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }

  var cItems = {
    isIncomplete: false,
    itemDefaults: {
      editRange: {
        start: {line: 0, character: 0},
        end: {line: 0, character: 2},
      },
      insertTextFormat: 1,
      insertTextMode: 2,
      data: {source: 'default'},
    },
    items: [{
      label: 'foobar',
    }],
  }

  completion.CompletionReply(lspserver, cItems)

  assert_false(lspserver.omniCompletePending)
  assert_equal(1, lspserver.completeItems->len())

  var item = lspserver.completeItems[0]
  assert_equal('foobar', item.word)
  assert_true(item.user_data->has_key('textEdit'))
  assert_equal('foobar', item.user_data.textEdit.newText)
  assert_equal(2, item.user_data.insertTextMode)
  assert_equal({source: 'default'}, item.user_data.data)
  assert_equal(0, item.user_data.textEdit.range.start.line)
  assert_equal(0, item.user_data.textEdit.range.start.character)
  assert_equal(0, item.user_data.textEdit.range.end.line)
  assert_equal(2, item.user_data.textEdit.range.end.character)

  :%bw!
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
