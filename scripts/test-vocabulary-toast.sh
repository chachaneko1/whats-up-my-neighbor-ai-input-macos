#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 \
 "$ROOT/Sources/GroqVoiceInput/VocabularyToastPresentation.swift" \
 "$ROOT/Tests/VocabularyToastPresentationTests.swift" \
 -o "$ROOT/build/VocabularyToastPresentationTests"
"$ROOT/build/VocabularyToastPresentationTests"
