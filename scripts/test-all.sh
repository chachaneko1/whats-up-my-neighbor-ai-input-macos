#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
export LC_ALL=C
integer test_count=0
mkdir -p "$ROOT/build"
for test_script in "$ROOT"/scripts/test-*.sh(N); do
  [[ "$test_script" == "${0:A}" ]] && continue
  print -r -- "Running ${test_script:t}"
  "$test_script"
  (( test_count += 1 ))
done
(( test_count > 0 )) || exit 1
print -- "All $test_count offline test suites passed."
