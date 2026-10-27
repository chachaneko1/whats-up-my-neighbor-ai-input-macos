#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AudioSilenceTrimmerTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/AudioSilenceTrimmer.swift" \
  "$ROOT/Tests/AudioSilenceTrimmerTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"

