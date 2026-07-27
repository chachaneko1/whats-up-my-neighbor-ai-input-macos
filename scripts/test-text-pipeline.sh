#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/TextPipelineTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Tests/TextPipelineTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
