vim9script
# Unit tests for Vim Language Server Protocol (LSP) typescript client

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
    'export obj = {',
    '  foo: 1,',
    '  bar: 2,',
    '  baz: 3',
    '}'
  ]

  setline(1, lines)
  :sleep 1
  g:WaitForDiags(2)
  :redraw!
  :LspDiagShow
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal('quickfix', getwinvar(winnr('$'), '&buftype'))
  assert_equal(bnr, qfl[0].bufnr)
  assert_equal(2, qfl->len())
  assert_equal([1, 1, 'E'], [qfl[0].lnum, qfl[0].col, qfl[0].type])
  assert_equal([1, 8, 'E'], [qfl[1].lnum, qfl[1].col, qfl[1].type])
  close

  :sleep 100m
  cursor(5, 1)
  assert_equal('', execute('LspDiagPrev'))
  assert_equal([1, 8], [line('.'), col('.')])

  assert_equal('', execute('LspDiagPrev'))
  assert_equal([1, 1], [line('.'), col('.')])

  var output = execute('LspDiagPrev')->split("\n")
  assert_equal('Error: No more diagnostics found', output[0])

  cursor(5, 1)
  assert_equal('', execute('LspDiagFirst'))
  assert_equal([1, 1], [line('.'), col('.')])
  assert_equal('', execute('LspDiagNext'))
  assert_equal([1, 8], [line('.'), col('.')])

  :%bw!
enddef

# Start the typescript language server.  Returns true on success and false on
# failure.
def g:StartLangServer(): bool
  # Edit a dummy .ts file to start the LSP server
  :edit Xtest.ts
  # Wait for the LSP server to become ready (max 10 seconds)
  var maxcount = 100
  while maxcount > 0 && !g:LspServerReady()
    :sleep 100m
    maxcount -= 1
  endwhile
  var serverStatus: bool = g:LspServerReady()
  :%bw!

  return serverStatus
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
