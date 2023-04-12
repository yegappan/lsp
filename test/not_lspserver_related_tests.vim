vim9script
# Unit tests for Vim Language Server Protocol (LSP) for various functionality 

# Test for no duplicates in helptags
def g:Test_Helptags()
  :helptags ../doc
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
