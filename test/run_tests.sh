#!/bin/bash

# Script to run the unit-tests for the LSP Vim plugin

VIMPRG=${VIMPRG:=$(which vim)}
if [ -z "$VIMPRG" ]; then
  echo "ERROR: $VIMPRG is not found in PATH"
  exit 1
fi

VIM_CMD="$VIMPRG -u NONE -U NONE -i NONE --noplugin -N --not-a-term"

$VIM_CMD -S unit_tests.vim

echo "LSP unit test results:"
echo

if ! [ -f results.txt ]; then
  echo "ERROR: Test results file 'results.txt' is not found."
  exit 2
fi

cat results.txt

echo
grep -w FAIL results.txt >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "ERROR: Some test(s) failed."
  exit 3
fi

echo "SUCCESS: All the tests passed."
exit 0
