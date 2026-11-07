vim9script
# Unit tests for Vim Language Server Protocol (LSP) for various functionality 

import '../autoload/lsp/completion.vim' as completion
import '../autoload/lsp/buffer.vim' as buf
import '../autoload/lsp/capabilities.vim' as capabilities
import '../autoload/lsp/util.vim' as util

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

  completion.CompletionReply(lspserver, cItems, {})

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

  completion.CompletionReply(lspserver, cItems, {})

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

  completion.CompletionReply(lspserver, cItems, {})

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

  completion.CompletionReply(lspserver, cItems, {})

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

  completion.CompletionReply(lspserver, cItems, {})

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

  completion.CompletionReply(lspserver, cItems, {})

  assert_false(lspserver.omniCompletePending)
  assert_equal(3, lspserver.completeItems->len())
  assert_equal('alpha', lspserver.completeItems[0].word)
  assert_equal('beta', lspserver.completeItems[1].word)
  assert_equal('gamma', lspserver.completeItems[2].word)

  :%bw!
enddef

# Regression test for documentOnTypeFormattingProvider trigger char capture.
def g:Test_OnTypeFormattingCapability()
  var lspserver = {
    caps: {
      documentOnTypeFormattingProvider: {
        firstTriggerCharacter: '}',
        moreTriggerCharacter: [';', "\n"],
      }
    },
    forceOffsetEncoding: '',
  }

  capabilities.ProcessServerCaps(lspserver, lspserver.caps)

  assert_true(lspserver.isDocumentOnTypeFormattingProvider)
  assert_equal(['}', ';', "\n"], lspserver.onTypeFormattingTriggers)
enddef

# Return a stub language server attached to the current buffer which replies
# to a completion request with "cItems".
def AttachCompletionStubServer(id: number, cItems: any): dict<any>
  var lspserver: dict<any> = {
    id: id,
    name: 'test',
    running: true,
    ready: true,
    isCompletionProvider: true,
    completionTriggerChars: ['.'],
    completionLazyDoc: false,
    omniCompletePending: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
    features: {completion: true},
  }
  lspserver.featureEnabled = (_) => true
  lspserver.getCompletion = (_, _) => {
    completion.CompletionReply(lspserver, cItems->deepcopy(), {})
  }
  buf.BufLspServerSet(bufnr(), lspserver)
  return lspserver
enddef

# Return a completion item which replaces the text from column "startCol" to
# "endCol" (0-based) in line "lnum" (0-based) with "newText".
def TextEditItem(label: string, newText: string, lnum: number, startCol: number,
		 endCol: number): dict<any>
  return {
    label: label,
    textEdit: {
      newText: newText,
      range: {
	start: {line: lnum, character: startCol},
	end: {line: lnum, character: endCol}
      }
    }
  }
enddef

# Test for the start of the completion and the inserted text when the textEdit
# range of a completion item starts before the keyword
def g:Test_Completion_TextEditRangeBeforeKeyword()
  for matcher in ['case', 'icase', 'fuzzy']
    g:LspOptionsSet({completionMatcher: matcher})

    # typescript: the textEdit of one of the items replaces the "."
    silent! edit XCompletionTextEdit.ts
    setline(1, ['    this.con'])
    cursor(1, 13)
    var myProp = TextEditItem('my-prop', '["my-prop"]', 0, 8, 9)
    myProp.filterText = '.my-prop'
    var cItems = [TextEditItem('context', 'context', 0, 9, 12), myProp]
    var lspserver = {
      name: 'test',
      omniCompletePending: true,
      completionLazyDoc: false,
      completeItems: [],
      completeItemsIsIncomplete: false,
    }
    completion.CompletionReply(lspserver, cItems, {})
    assert_false(lspserver.omniCompletePending)
    assert_equal(8, lspserver.omniCompleteStart)
    assert_equal(['.context'],
		 lspserver.completeItems->mapnew((_, v) => v.word))

    # The "my-prop" item replaces the "."
    setline(1, ['    this.my'])
    cursor(1, 12)
    myProp.textEdit.range.end.character = 9
    cItems = [TextEditItem('context', 'context', 0, 9, 11), myProp]
    lspserver.omniCompletePending = true
    completion.CompletionReply(lspserver, cItems, {})
    assert_equal(8, lspserver.omniCompleteStart)
    assert_equal(['["my-prop"]'],
		 lspserver.completeItems->mapnew((_, v) => v.word))

    # terraform: the textEdit range starts at "var"
    setline(1, ['  value = var.g'])
    cursor(1, 16)
    cItems = [TextEditItem('var.greeting', 'var.greeting', 0, 10, 15)]
    lspserver.omniCompletePending = true
    completion.CompletionReply(lspserver, cItems, {})
    assert_equal(10, lspserver.omniCompleteStart)
    assert_equal(['var.greeting'],
		 lspserver.completeItems->mapnew((_, v) => v.word))

    # vue: the textEdit range starts at "v-" or "@".  An item without a
    # textEdit starts at the keyword.
    setline(1, ['  <span v-i'])
    cursor(1, 12)
    cItems = [TextEditItem('v-if', 'v-if', 0, 8, 11),
	      TextEditItem('@click', '@click', 0, 8, 11),
	      {label: 'id'}]
    lspserver.omniCompletePending = true
    completion.CompletionReply(lspserver, cItems, {})
    assert_equal(8, lspserver.omniCompleteStart)
    assert_equal(['v-id', 'v-if'],
		 lspserver.completeItems->mapnew((_, v) => v.word)->sort())

    :%bw!
  endfor
  g:LspOptionsSet({completionMatcher: 'case'})
enddef

# Test for omni completion with completion items replacing the text before the
# keyword
def g:Test_OmniComplete_TextEditRangeBeforeKeyword()
  for matcher in ['case', 'fuzzy']
    g:LspOptionsSet({completionMatcher: matcher})

    silent! edit XOmniCompleteTextEdit.ts
    setlocal omnifunc=g:LspOmniFunc
    setline(1, ['    this.con'])
    var lspserver = AttachCompletionStubServer(9101,
      [TextEditItem('context', 'context', 0, 9, 12),
       TextEditItem('my-prop', '["my-prop"]', 0, 8, 9)
	 ->extend({filterText: '.my-prop'})])
    feedkeys("A\<C-X>\<C-O>", 'xt')
    assert_equal('    this.context', getline(1))
    buf.BufLspServerRemove(bufnr(), lspserver)
    :%bw!

    silent! edit XOmniCompleteTextEdit.tf
    setlocal omnifunc=g:LspOmniFunc
    setline(1, ['  value = var.g'])
    lspserver = AttachCompletionStubServer(9102,
      [TextEditItem('var.greeting', 'var.greeting', 0, 10, 15)])
    feedkeys("A\<C-X>\<C-O>", 'xt')
    assert_equal('  value = var.greeting', getline(1))
    buf.BufLspServerRemove(bufnr(), lspserver)
    :%bw!

    silent! edit XOmniCompleteTextEdit.vue
    setlocal omnifunc=g:LspOmniFunc
    setline(1, ['  <span v-i'])
    lspserver = AttachCompletionStubServer(9103,
      [TextEditItem('v-if', 'v-if', 0, 8, 11),
       TextEditItem('@click', '@click', 0, 8, 11)])
    feedkeys("A\<C-X>\<C-O>", 'xt')
    assert_equal('  <span v-if', getline(1))
    # Items starting with "@" are not filtered out
    setline(1, ['  <span @'])
    lspserver.getCompletion = (_, _) => {
      completion.CompletionReply(lspserver,
	[TextEditItem('v-if', 'v-if', 0, 8, 9),
	 TextEditItem('@click', '@click', 0, 8, 9)], {})
    }
    lspserver.completionTriggerChars = ['@']
    feedkeys("A\<C-X>\<C-O>", 'xt')
    assert_equal('  <span @click', getline(1))
    buf.BufLspServerRemove(bufnr(), lspserver)
    :%bw!
  endfor
  g:LspOptionsSet({completionMatcher: 'case'})
enddef

# Test for omni completion when the reply from the language server arrives
# after the omni completion function is called
def g:Test_OmniComplete_AsyncReply()
  silent! edit XOmniCompleteAsyncReply.txt
  setlocal filetype=text
  setlocal omnifunc=g:LspOmniFunc
  setlocal completeopt=menuone,noinsert
  setline(1, ['foo.'])
  var lspserver = AttachCompletionStubServer(9104, [])
  lspserver.getCompletion = (_, _) => {
    timer_start(20, (_) => {
      completion.CompletionReply(lspserver, [{label: 'bar'}, {label: 'baz'}], {})
    })
  }
  inoremap <buffer> <F3> <ScriptCmd>g:LspTestWords = complete_info(['items']).items->mapnew((_, v) => v.word)<CR>
  g:LspTestWords = []
  feedkeys("A\<C-X>\<C-O>\<F3>\<C-E>\<Esc>", 'xt')
  assert_equal(['bar', 'baz'], g:LspTestWords)
  unlet g:LspTestWords
  buf.BufLspServerRemove(bufnr(), lspserver)
  :%bw!
enddef

# Test for a snippet completion item inserted as plain text
def g:Test_Completion_SnippetAsPlainText()
  silent! edit XCompletionSnippet.txt
  setline(1, ['x'])
  cursor(1, 2)
  var lspserver = {
    name: 'test',
    omniCompletePending: true,
    completionLazyDoc: false,
    completeItems: [],
    completeItemsIsIncomplete: false,
  }
  var snippets = {
    'v-if="$1"': 'v-if=""',
    'v-for="${1:value} in ${2:source}"': 'v-for="value in source"',
    'foo(${1:a}, ${2:${3:b}})$0': 'foo(a, b)',
    '${1|one,two|} \$x \} \\': 'one $x } \',
    '${TM_FILENAME:file} $TM_LINE_NUMBER': 'file ',
  }
  completion.CompletionReply(lspserver, snippets->keys()->mapnew((_, v) => ({
    label: 'x', insertText: v, insertTextFormat: 2})), {})
  assert_equal(snippets->values()->sort(),
	       lspserver.completeItems->mapnew((_, v) => v.word)->sort())

  # textEdit with a snippet
  :%bw!
  silent! edit XOmniCompleteSnippet.vue
  setlocal omnifunc=g:LspOmniFunc
  setline(1, ['  <p v-i'])
  var srv = AttachCompletionStubServer(9105,
    [TextEditItem('v-if', 'v-if="$1"', 0, 5, 8)->extend({insertTextFormat: 2})])
  feedkeys("A\<C-X>\<C-O>", 'xt')
  assert_equal('  <p v-if=""', getline(1))
  buf.BufLspServerRemove(bufnr(), srv)
  :%bw!
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# Regression test for $HOME as workspace root being ignored
def g:Test_WorkspaceIgnoredPaths_HomeRoot()
  var ignored: list<string> = [$"{$HOME}"]
  var root: string = $HOME
  assert_true(util.IsIgnoredRoot(root, ignored))
enddef

# Glob pattern matches children even under a symlink
def g:Test_WorkspaceIgnoredPaths_GlobSymlink()
  var tmpdir: string = tempname()
  var real: string = $'{tmpdir}/real'
  var link: string = $'{tmpdir}/link'
  mkdir($'{real}/.cargo/registry/src/index', 'p')
  system($'ln -s {shellescape(real)} {shellescape(link)}')
  assert_equal(0, v:shell_error)
  var ignored: list<string> = [$'{link}/.cargo/**']
  var root: string = $'{real}/.cargo/registry/src/index/package'
  try
    assert_true(util.IsIgnoredRoot(root, ignored))
  finally
    delete(tmpdir, 'rf')
  endtry
enddef

# Root not ignored if it doesn't exist in the list
def g:Test_WorkspaceIgnoredPaths_NormalRoot()
  var ignored: list<string> = [$"{$HOME}"]
  var root: string = $"{$HOME}/project"
  assert_false(util.IsIgnoredRoot(root, ignored))
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
