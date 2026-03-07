vim9script

# Script to run language server unit tests
# The global variable TestName should be set to the name of the file
# containing the tests.

source common.vim

def LspRunTests()
  :set nomore
  :set debug=beep
  # Use a list to accumulate all results, then write once for better I/O
  var all_results: list<string> = []

  # ROBUST DISCOVERY: Capture functions defined in the sourced test file
  # The regex is tightened to handle compiled vs non-compiled function headers
  var fns: list<string> = execute('function /^Test_')
    ->split("\n")
    ->map((_, v) => v->substitute('^\(def\|func\)\s\+\(Test_\w\+\).*', '\2', ''))
    ->filter((_, v) => v =~ '^Test_')
    ->sort()

  if fns->empty()
    writefile([$'No tests found in {g:TestName}'], 'results.txt', 'a')
    return
  endif

  for f in fns
    v:errors = []
    v:errmsg = ''
    try
      # ISOLATION: Clear hidden buffers and reset options that might leak
      # silent! %bwipeout! is good, but we also ensure no leftover windows
      silent! :%bwipeout!

      # Execute the test function
      exe $'call {f}()'
    catch
      add(v:errors, $'EXCEPTION: {f} -> {v:exception} at {v:throwpoint}')
    endtry

    # Check for both v:errors (assertions) and v:errmsg (Vim core errors)
    if v:errmsg != ''
      add(v:errors, $'ERROR: {f} generated {v:errmsg}')
    endif

    if !v:errors->empty()
      extend(all_results, v:errors)
      add(all_results, $'{f}: FAIL')
    else
      add(all_results, $'{f}: pass')
    endif
  endfor

  # Final write-back of all test results
  writefile(all_results, 'results.txt', 'a')
enddef

# --- Main Execution Flow ---
try
  # Ensure results.txt is empty before starting
  writefile([], 'results.txt')

  g:LoadLspPlugin()

  if filereadable(g:TestName)
    exe $'source {g:TestName}'
    # Start the server; if this fails, the catch block will log it
    g:StartLangServer()
    LspRunTests()
  else
    writefile([$'FAIL: Test file "{g:TestName}" not found'], 'results.txt', 'a')
  endif
catch
  var msg = $'FAIL: Global exception in {g:TestName}: {v:exception} at {v:throwpoint}'
  writefile([msg], 'results.txt', 'a')
endtry

# Stop the LSP server if a helper exists, then exit
if exists('*g:StopLangServer')
  g:StopLangServer()
endif

qall!

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
