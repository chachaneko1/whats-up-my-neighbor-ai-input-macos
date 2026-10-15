#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/ClipboardHistoryInsertionTests"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -framework AppKit -framework ImageIO \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryStore.swift" \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryMonitor.swift" \
  "$ROOT/Sources/GroqVoiceInput/PasteDiagnostics.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/FocusTargetService.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextInsertionService.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetController.swift" \
  "$ROOT/Tests/ClipboardHistoryInsertionTests.swift" \
  -o "$OUTPUT"
exec "$OUTPUT"
