#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AudioInputPolicyTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/AudioInputPolicy.swift" \
  "$ROOT/Tests/AudioInputPolicyTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
