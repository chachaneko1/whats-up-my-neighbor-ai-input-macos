#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/TextInsertionTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/PasteDiagnostics.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/FocusTargetService.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextInsertionService.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetController.swift" \
  "$ROOT/Tests/TextInsertionTests.swift" \
  -o "$OUTPUT"

exec "$OUTPUT"
