vim9script
# Script to run a language server unit tests
# The global variable TestName should be set to the name of the file
# containing the tests.

syntax on
filetype on
filetype plugin on
filetype indent on

# Set the $LSP_PROFILE environment variable to profile the LSP plugin
var do_profile: bool = false
if exists('$LSP_PROFILE')
  do_profile = true
endif

if do_profile
  # profile the LSP plugin
  profile start lsp_profile.txt
  profile! file */lsp/*
endif

source ../plugin/lsp.vim

g:LSPTest = true

# The WaitFor*() functions are reused from the Vim test suite.
#
# Wait for up to five seconds for "assert" to return zero.  "assert" must be a
# (lambda) function containing one assert function.  Example:
#	call WaitForAssert({-> assert_equal("dead", job_status(job)})
#
# A second argument can be used to specify a different timeout in msec.
#
# Return zero for success, one for failure (like the assert function).
func g:WaitForAssert(assert, ...)
  let timeout = get(a:000, 0, 5000)
  if g:WaitForCommon(v:null, a:assert, timeout) < 0
    return 1
  endif
  return 0
endfunc

# Either "expr" or "assert" is not v:null
# Return the waiting time for success, -1 for failure.
func g:WaitForCommon(expr, assert, timeout)
  " using reltime() is more accurate, but not always available
  let slept = 0
  if exists('*reltimefloat')
    let start = reltime()
  endif

  while 1
    if type(a:expr) == v:t_func
      let success = a:expr()
    elseif type(a:assert) == v:t_func
      let success = a:assert() == 0
    else
      let success = eval(a:expr)
    endif
    if success
      return slept
    endif

    if slept >= a:timeout
      break
    endif
    if type(a:assert) == v:t_func
      " Remove the error added by the assert function.
      call remove(v:errors, -1)
    endif

    sleep 10m
    if exists('*reltimefloat')
      let slept = float2nr(reltimefloat(reltime(start)) * 1000)
    else
      let slept += 10
    endif
  endwhile

  return -1  " timed out
endfunc

# Wait for diagnostic messages from the LSP server
def g:WaitForDiags(errCount: number)
  var retries = 0
  while retries < 150
    var d = lsp#lsp#ErrorCount()
    if d.Error == errCount
      break
    endif
    retries += 1
    :sleep 100m
  endwhile
enddef

def LspRunTests()
  :set nomore
  :set debug=beep
  delete('results.txt')

  # Get the list of test functions in this file and call them
  var fns: list<string> = execute('function /Test_')
		    ->split("\n")
		    ->map("v:val->substitute('^def ', '', '')")
  for f in fns
    v:errors = []
    v:errmsg = ''
    try
      :%bw!
      exe 'g:' .. f
    catch
      call add(v:errors, "Error: Test " .. f .. " failed with exception " .. v:exception .. " at " .. v:throwpoint)
    endtry
    if v:errmsg != ''
      call add(v:errors, "Error: Test " .. f .. " generated error " .. v:errmsg)
    endif
    if !v:errors->empty()
      writefile(v:errors, 'results.txt', 'a')
      writefile([f .. ': FAIL'], 'results.txt', 'a')
    else
      writefile([f .. ': pass'], 'results.txt', 'a')
    endif
  endfor
enddef

exe 'source ' .. g:TestName

if !g:StartLangServer()
  writefile(['FAIL: Not able to start the language server'], 'results.txt')
  qall!
endif

LspRunTests()
qall!

# vim: shiftwidth=2 softtabstop=2 noexpandtab
