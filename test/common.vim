vim9script
# Common routines used for running the unit tests

# Load the LSP plugin.  Also enable syntax, file type detection.
def g:LoadLspPlugin()
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

  g:LSPTest = true
  source ../plugin/lsp.vim
enddef

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

# Wait for up to five seconds for "expr" to become true.  "expr" can be a
# stringified expression to evaluate, or a funcref without arguments.
# Using a lambda works best.  Example:
#	call WaitFor({-> status == "ok"})
#
# A second argument can be used to specify a different timeout in msec.
#
# When successful the time slept is returned.
# When running into the timeout an exception is thrown, thus the function does
# not return.
func g:WaitFor(expr, ...)
  let timeout = get(a:000, 0, 5000)
  let slept = g:WaitForCommon(a:expr, v:null, timeout)
  if slept < 0
    throw 'WaitFor() timed out after ' .. timeout .. ' msec'
  endif
  return slept
endfunc

# Wait for diagnostic messages from the LSP server.
# Waits for a maximum of (150 * 200) / 1000 = 30 seconds
def g:WaitForDiags(errCount: number)
  var retries = 0
  while retries < 200
    var d = lsp#lsp#ErrorCount()
    if d.Error == errCount
      break
    endif
    retries += 1
    :sleep 150m
  endwhile

  assert_equal(errCount, lsp#lsp#ErrorCount().Error)
  if lsp#lsp#ErrorCount().Error != errCount
    :LspDiag show
    assert_report(getloclist(0)->string())
    :lclose
  endif
enddef

# Wait for the LSP server to load and process a file.  This works by waiting
# for a certain number of diagnostic messages from the server.
def g:WaitForServerFileLoad(diagCount: number)
  :redraw!
  var waitCount = diagCount
  if waitCount == 0
    # Introduce a temporary diagnostic
    append('$', '-')
    redraw!
    waitCount = 1
  endif
  g:WaitForDiags(waitCount)
  if waitCount != diagCount
    # Remove the temporary line
    deletebufline('%', '$')
    redraw!
    g:WaitForDiags(0)
  endif
enddef

# Start the language server.  Returns true on success and false on failure.
# 'fname' is the name of a dummy file to start the server.
def g:StartLangServerWithFile(fname: string): bool
  # Edit a dummy file to start the LSP server
  exe ':silent! edit ' .. fname
  # Wait for the LSP server to become ready (max 10 seconds)
  var maxcount = 100
  while maxcount > 0 && !g:LspServerReady()
    :sleep 100m
    maxcount -= 1
  endwhile
  var serverStatus: bool = g:LspServerReady()
  :bw!

  if !serverStatus
    writefile(['FAIL: Not able to start the language server'], 'results.txt')
    qall!
  endif

  return serverStatus
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
