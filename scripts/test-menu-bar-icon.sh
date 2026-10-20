#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -framework AppKit \
  "$ROOT/Sources/GroqVoiceInput/NekoMenuBarIcon.swift" \
  "$ROOT/Tests/NekoMenuBarIconTests.swift" -o "$ROOT/build/NekoMenuBarIconTests"
"$ROOT/build/NekoMenuBarIconTests" "$ROOT"
swiftc -swift-version 5 -framework AppKit \
  "$ROOT/Sources/GroqVoiceInput/NekoMenuBarIcon.swift" \
  "$ROOT/Tests/NekoIconVectorTests.swift" -o "$ROOT/build/NekoIconVectorTests"
"$ROOT/build/NekoIconVectorTests" "$ROOT"
