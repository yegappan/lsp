vim9script

import '../autoload/lsp/buffer.vim' as buf
import '../autoload/lsp/util.vim' as util

source common.vim

g:markdown_fenced_languages = ['c']

var lspServers = [
  {
    name: 'marksman',
    filetype: 'markdown',
    path: (exepath('marksman') ?? expand('~') .. '/.local/bin/marksman'),
    args: ['server'],
  },
  {
    name: 'clangd',
    filetype: 'markdown',
    path: (exepath('clangd-15') ?? exepath('clangd')),
    args: ['--background-index', '--clang-tidy'],
    syntaxAssociatedLSP: ['markdownHighlight_c', 'markdownHighlightc'],

  },
]
call LspAddServer(lspServers)

def FillDummyFile()
  :silent edit dummy.md
  sleep 200m
  var lines: list<string> =<< trim END
    # Title
 
    ```c
    int f1() {
      int x;
      int y;
      x = 1;
      y = 2;
      return x + y;
    }
    ```
  END
  setline(1, lines)
enddef

def g:Test_ChoseDefaultLspIfNoSyntaxMatch()
  FillDummyFile()
  search('Title')
  var selected_lsp =  buf.BufLspServerGet(bufnr(), 'hover')
  assert_true(selected_lsp->has_key('name'))
  assert_equal(selected_lsp.name, 'marksman')
enddef

def g:Test_ChooseCorrectLspIfSyntaxMatch()
  FillDummyFile()
  search('int')
  var selected_lsp =  buf.BufLspServerGet(bufnr(), 'hover')
  assert_true(selected_lsp->has_key('name'))
  assert_equal(selected_lsp.name, 'clangd')
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
