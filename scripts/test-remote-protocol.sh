#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
IOS_PROTOCOL="$ROOT/../groq-ai-voice-input-ios/Sources/Remote/RemoteMessages.swift"
MAC_PROTOCOL="$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift"
IOS_VOCABULARY_SYNC="$ROOT/../groq-ai-voice-input-ios/Sources/Remote/VocabularySyncModels.swift"
MAC_VOCABULARY_SYNC="$ROOT/Sources/GroqVoiceInput/VocabularySyncModels.swift"
OUTPUT="$ROOT/build/RemoteProtocolTests"

mkdir -p "$ROOT/build"

if [[ -f "$IOS_PROTOCOL" ]]; then
    cmp "$MAC_PROTOCOL" "$IOS_PROTOCOL"
    cmp "$MAC_VOCABULARY_SYNC" "$IOS_VOCABULARY_SYNC"
else
  print -u2 "iOS sibling project not found; skipping cross-project protocol comparison."
fi

swiftc \
  -swift-version 5 \
  "$MAC_VOCABULARY_SYNC" \
  "$MAC_PROTOCOL" \
  "$ROOT/Sources/GroqVoiceInput/MacVocabularyStore.swift" \
  "$ROOT/Sources/GroqVoiceInput/MacVocabularyCorrection.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Tests/RemoteProtocolTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
