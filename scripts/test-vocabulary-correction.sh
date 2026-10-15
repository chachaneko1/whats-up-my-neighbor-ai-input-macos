#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 \
 "$ROOT/Sources/GroqVoiceInput/GroqTranscriptionClient.swift" \
 "$ROOT/Sources/GroqVoiceInput/VocabularySyncModels.swift" \
 "$ROOT/Sources/GroqVoiceInput/MacVocabularyStore.swift" \
 "$ROOT/Sources/GroqVoiceInput/MacVocabularyCorrection.swift" \
 "$ROOT/Tests/VocabularyCorrectionTests.swift" \
 -o "$ROOT/build/VocabularyCorrectionTests"
"$ROOT/build/VocabularyCorrectionTests"
