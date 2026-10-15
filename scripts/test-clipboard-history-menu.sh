#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -framework AppKit \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryStore.swift" \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryMenuController.swift" \
  "$ROOT/Tests/ClipboardHistoryMenuTests.swift" \
  -o "$ROOT/build/ClipboardHistoryMenuTests"
"$ROOT/build/ClipboardHistoryMenuTests"
