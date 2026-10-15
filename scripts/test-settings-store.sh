#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/SettingsStoreTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  -framework Carbon \
  "$ROOT/Sources/GroqVoiceInput/HotKeyManager.swift" \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Sources/GroqVoiceInput/SettingsStore.swift" \
  "$ROOT/Tests/SettingsStoreTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
