vim9script
# Script to run a language server unit tests
# The global variable TestName should be set to the name of the file
# containing the tests.

source common.vim

def LspRunTests()
  :set nomore
  :set debug=beep
  delete('results.txt')

  # Get the list of test functions in this file and call them
  var fns: list<string> = execute('function /^Test_')
		    ->split("\n")
		    ->map("v:val->substitute('^def ', '', '')")
		    ->sort()
  if fns->empty()
    # No tests are found
    writefile(['No tests are found'], 'results.txt')
    return
  endif
  for f in fns
    v:errors = []
    v:errmsg = ''
    try
      :%bw!
      exe $'g:{f}'
    catch
      call add(v:errors, $'Error: Test {f} failed with exception {v:exception} at {v:throwpoint}')
    endtry
    if v:errmsg != ''
      call add(v:errors, $'Error: Test {f} generated error {v:errmsg}')
    endif
    if !v:errors->empty()
      writefile(v:errors, 'results.txt', 'a')
      writefile([$'{f}: FAIL'], 'results.txt', 'a')
    else
      writefile([$'{f}: pass'], 'results.txt', 'a')
    endif
  endfor
enddef

try
  g:LoadLspPlugin()
  exe $'source {g:TestName}'
  g:StartLangServer()
  LspRunTests()
catch
  writefile(['FAIL: Tests in ' .. g:TestName .. ' failed with exception ' .. v:exception .. ' at ' .. v:throwpoint], 'results.txt', 'a')
endtry

qall!

# vim: shiftwidth=2 softtabstop=2 noexpandtab
