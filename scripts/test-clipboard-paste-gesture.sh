#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -framework AppKit -framework ApplicationServices -framework Carbon \
  "$ROOT/Sources/GroqVoiceInput/ClipboardPasteGesture.swift" \
  "$ROOT/Tests/ClipboardPasteGestureTests.swift" -o "$ROOT/build/ClipboardPasteGestureTests"
"$ROOT/build/ClipboardPasteGestureTests"
