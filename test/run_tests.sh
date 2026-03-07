#!/bin/bash

# Use the environment VIMPRG or find it in PATH
VIMPRG="${VIMPRG:-$(command -v vim)}"

if [[ ! -x "$VIMPRG" ]]; then
  echo "ERROR: vim ($VIMPRG) not found or not executable."
  exit 1
fi

# Clean up results from a previous crashed run
rm -f results.txt

# --- Configuration ---
VIM_CMD="$VIMPRG -u NONE -U NONE -i NONE --noplugin -N --not-a-term"

# Use arguments if provided, otherwise run the full suite
ALL_TESTS=(
  "clangd_tests.vim"
  "tsserver_tests.vim"
  "gopls_tests.vim"
  "not_lspserver_related_tests.vim"
  "markdown_tests.vim"
  "rust_tests.vim"
)
TESTS_TO_RUN="${@:-${ALL_TESTS[@]}}"

RunTestsInFile() {
  local testfile=$1
  local encoding=${2:-"utf-8"}

  # Use a unique results file name to allow potential parallel runs later
  local res_file="results_${testfile}_${encoding}.txt"
  rm -f "$res_file"

  echo "===> Running: $testfile (Encoding: $encoding)"

  export LSP_OFFSET_ENCODING="$encoding"

  # Execute Vim and redirect its internal 'results.txt' logic if possible,
  # or handle the renaming here.
  $VIM_CMD -c "let g:TestName='$testfile'" -S runner.vim

  # Standardizing the results file name if runner.vim always outputs 'results.txt'
  if [[ -f results.txt ]]; then
    mv results.txt "$res_file"
  fi

  if [[ ! -f "$res_file" ]]; then
    echo "ERROR: Test results file '$res_file' not found."
    return 2
  fi

  cat "$res_file"

  if grep -qw "FAIL" "$res_file"; then
    echo "RESULT: Some tests in $testfile FAILED."
    return 3
  fi

  echo "RESULT: All tests in $testfile PASSED."
  echo ""
  rm "$res_file"
}

# --- Main Execution ---

# 1. Standard Suite
for testfile in $TESTS_TO_RUN; do
  RunTestsInFile "$testfile" || exit $?
done

# 2. Clangd Encoding Specific Suite
# Only run if we are running all tests or specifically clangd tests
if [[ "$*" == "" || "$*" == *"clangd"* ]]; then
  for encoding in "utf-8" "utf-16" "utf-32"; do
    RunTestsInFile "clangd_offsetencoding.vim" "$encoding" || exit $?
  done
fi

echo "---------------------------------------"
echo "SUCCESS: All specified tests passed."
exit 0

# vim: tabstop=2 shiftwidth=2 softtabstop=2 expandtab
