#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/ClipboardHistoryMonitorTests"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -framework AppKit -framework ImageIO \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryStore.swift" \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryMonitor.swift" \
  "$ROOT/Tests/ClipboardHistoryMonitorTests.swift" \
  -o "$OUTPUT"
exec "$OUTPUT"
