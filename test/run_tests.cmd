@echo off

REM Script to run the unit-tests for the LSP Vim plugin on MS-Windows

SETLOCAL
SET VIMPRG="vim.exe"
SET VIM_CMD=%VIMPRG% -u NONE -U NONE -i NONE --noplugin -N --not-a-term

%VIM_CMD% -c "let g:TestName='clangd_tests.vim'" -S runner.vim

echo LSP unit test results
type results.txt

findstr /I FAIL results.txt > nul 2>&1
if %ERRORLEVEL% EQU 0 echo ERROR: Some test failed.
if %ERRORLEVEL% NEQ 0 echo SUCCESS: All the tests passed.

