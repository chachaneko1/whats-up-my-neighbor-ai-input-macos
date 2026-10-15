#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
export LC_ALL=C
integer test_count=0

# Keep offline test wrappers named test-*.sh. Network spikes and cross-repo
# protocol parity checks are explicit, separate commands.
for test_script in "$ROOT"/scripts/test-*.sh(N); do
  [[ "$test_script" == "${0:A}" ]] && continue
  print -r -- "Running ${test_script:t}"
  "$test_script"
  (( test_count += 1 ))
done

if (( test_count == 0 )); then
  print -u2 -- "No offline test scripts found."
  exit 1
fi

print -- "All $test_count offline test suites passed."
