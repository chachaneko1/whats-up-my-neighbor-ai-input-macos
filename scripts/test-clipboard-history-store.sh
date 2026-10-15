#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryStore.swift" \
  "$ROOT/Tests/ClipboardHistoryStoreTests.swift" \
  -o "$ROOT/build/ClipboardHistoryStoreTests"
"$ROOT/build/ClipboardHistoryStoreTests"
