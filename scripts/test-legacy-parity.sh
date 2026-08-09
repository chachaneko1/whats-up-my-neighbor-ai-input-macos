#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/LegacyParityTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/GroqTranscriptionClient.swift" \
  "$ROOT/Tests/LegacyParityTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
