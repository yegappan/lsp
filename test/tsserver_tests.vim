vim9script
# Unit tests for Vim Language Server Protocol (LSP) typescript client

source common.vim
source term_util.vim
source screendump.vim

var lspOpts = {autoComplete: false}
g:LspOptionsSet(lspOpts)

var lspServers = [{
      filetype: ['typescript', 'javascript'],
      path: exepath('typescript-language-server'),
      args: ['--stdio']
  }]
call LspAddServer(lspServers)
echomsg systemlist($'{lspServers[0].path} --version')

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

# Test for auto-import using omni completion
def g:Test_autoimport()
  :silent! edit autoImportMod1.ts
  sleep 200m
  var lines =<< trim END
    export function getNumber() {
      return 1;
    }
  END
  setline(1, lines)
  :redraw!
  g:WaitForServerFileLoad(0)

  var save_completopt = &completeopt
  set completeopt=

  :split autoImportMod2.ts
  :sleep 200m
  setline(1, 'console.log(getNum')
  g:WaitForServerFileLoad(2)
  feedkeys("A\<C-X>\<C-O>());", 'xt')
  var expected =<< trim END
    import { getNumber } from "./autoImportMod1";

    ());console.log(getNumber
  END
  assert_equal(expected, getline(1, '$'))

  &completeopt = save_completopt

  :%bw!
enddef

# Start the typescript language server.  Returns true on success and false on
# failure.
def g:StartLangServer(): bool
  return g:StartLangServerWithFile('Xtest.ts')
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
