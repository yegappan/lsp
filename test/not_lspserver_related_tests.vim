vim9script
# Unit tests for Vim Language Server Protocol (LSP) for various functionality 

import '../autoload/lsp/completion.vim' as completion
import '../autoload/lsp/buffer.vim' as buf

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

# Regression test for CompletionItem.insertTextMode handling.
def g:Test_Completion_InsertTextMode_AdjustIndentation()
  silent! edit XCompletionInsertTextMode.vim
  setline(1, ['    f'])
  cursor(1, 6)

  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }

  var cItems = [{
    label: 'foo',
    insertText: "foo\n  bar",
    insertTextFormat: 1,
    insertTextMode: 2,
  }]

  completion.CompletionReply(lspserver, cItems)

  assert_false(lspserver.omniCompletePending)
  assert_equal(1, lspserver.completeItems->len())
  assert_equal("foo\n    bar", lspserver.completeItems[0].word)

  :%bw!
enddef

def g:Test_Completion_InsertTextMode_AsIs()
  silent! edit XCompletionInsertTextModeAsIs.vim
  setline(1, ['    f'])
  cursor(1, 6)

  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }

  var cItems = [{
    label: 'foo',
    insertText: "foo\n  bar",
    insertTextFormat: 1,
    insertTextMode: 1,
  }]

  completion.CompletionReply(lspserver, cItems)

  assert_false(lspserver.omniCompletePending)
  assert_equal(1, lspserver.completeItems->len())
  assert_equal("foo\n  bar", lspserver.completeItems[0].word)

  :%bw!
enddef

# Regression test for CompletionItem.labelDetails rendering.
def g:Test_Completion_LabelDetails_Rendering()
  g:LspOptionsSet({condensedCompletionMenu: false})

  silent! edit XCompletionLabelDetails.vim
  setline(1, ['fo'])
  cursor(1, 3)

  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }

  var cItems = [{
    label: 'foo',
    labelDetails: {
      detail: '(x: number)',
      description: 'pkg.module',
    },
    detail: 'legacy detail',
  }]

  completion.CompletionReply(lspserver, cItems)

  assert_false(lspserver.omniCompletePending)
  assert_equal(1, lspserver.completeItems->len())

  var item = lspserver.completeItems[0]
  assert_equal('foo(x: number)', item.abbr)
  assert_equal('pkg.module | legacy detail', item.menu)

  :%bw!
enddef

# Regression test for CompletionTriggerKind=3 retrigger on incomplete lists.
def g:Test_Completion_RetriggerKind_IncompleteList()
  silent! edit XCompletionRetriggerKind.vim
  setline(1, ['foo'])
  cursor(1, 4)

  var calls: list<list<any>> = []
  var lspserver = {
    id: 9001,
    name: 'test',
    running: true,
    ready: true,
    isCompletionProvider: true,
    completeItemsIsIncomplete: true,
    features: {completion: true},
    featureEnabled: (_) => true,
    getCompletion: (kind: number, ch: string) => calls->add([kind, ch]),
  }

  buf.BufLspServerSet(bufnr(), lspserver)
  completion.LspComplete()

  assert_equal(1, calls->len())
  assert_equal(3, calls[0][0])
  assert_equal('', calls[0][1])

  buf.BufLspServerRemove(bufnr(), lspserver)
  :%bw!
enddef

def g:Test_Completion_TriggerKind_Initial()
  silent! edit XCompletionTriggerKindInitial.vim
  setline(1, ['foo'])
  cursor(1, 4)

  var calls: list<list<any>> = []
  var lspserver = {
    id: 9002,
    name: 'test',
    running: true,
    ready: true,
    isCompletionProvider: true,
    completeItemsIsIncomplete: false,
    features: {completion: true},
    featureEnabled: (_) => true,
    getCompletion: (kind: number, ch: string) => calls->add([kind, ch]),
  }

  buf.BufLspServerSet(bufnr(), lspserver)
  completion.LspComplete()

  assert_equal(1, calls->len())
  assert_equal(1, calls[0][0])
  assert_equal('', calls[0][1])

  buf.BufLspServerRemove(bufnr(), lspserver)
  :%bw!
enddef


# Regression test for CompletionItem.preselect ordering.
def g:Test_Completion_Preselect_ItemFirst()
  silent! edit XCompletionPreselect.vim
  setline(1, ['f'])
  cursor(1, 2)

  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }

  var cItems = [{
    label: 'alpha',
    sortText: 'a',
  }, {
    label: 'beta',
    sortText: 'b',
  }, {
    label: 'gamma',
    sortText: 'c',
    preselect: true,
  }]

  completion.CompletionReply(lspserver, cItems)

  assert_false(lspserver.omniCompletePending)
  assert_equal(3, lspserver.completeItems->len())
  assert_equal('gamma', lspserver.completeItems[0].word)
  assert_equal('alpha', lspserver.completeItems[1].word)
  assert_equal('beta', lspserver.completeItems[2].word)

  :%bw!
enddef

def g:Test_Completion_Preselect_NoopWithoutPreselect()
  silent! edit XCompletionPreselectNoop.vim
  setline(1, ['f'])
  cursor(1, 2)

  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }

  var cItems = [{
    label: 'alpha',
    sortText: 'a',
  }, {
    label: 'beta',
    sortText: 'b',
  }, {
    label: 'gamma',
    sortText: 'c',
  }]

  completion.CompletionReply(lspserver, cItems)

  assert_false(lspserver.omniCompletePending)
  assert_equal(3, lspserver.completeItems->len())
  assert_equal('alpha', lspserver.completeItems[0].word)
  assert_equal('beta', lspserver.completeItems[1].word)
  assert_equal('gamma', lspserver.completeItems[2].word)

  :%bw!
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
