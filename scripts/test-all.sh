#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
export LC_ALL=C
mkdir -p "$ROOT/build"
for suite in audio-input-policy legacy-parity text-pipeline transcription-client cat updates; do
  "$ROOT/scripts/test-$suite.sh"
done
# The separate remote parity wrapper needs a sibling iOS repo.
swiftc -swift-version 5 "$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Tests/RemoteProtocolTests.swift" -o "$ROOT/build/RemoteProtocolTests"
"$ROOT/build/RemoteProtocolTests"
print 'All 7 offline suites passed.'
