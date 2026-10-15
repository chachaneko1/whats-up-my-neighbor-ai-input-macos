#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/PasteCorrectionMonitorTests"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/PasteDiagnostics.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/FocusTargetService.swift" \
  "$ROOT/Sources/GroqVoiceInput/VocabularySyncModels.swift" \
  "$ROOT/Sources/GroqVoiceInput/MacVocabularyStore.swift" \
  "$ROOT/Sources/GroqVoiceInput/MacVocabularyCorrection.swift" \
  "$ROOT/Sources/GroqVoiceInput/PasteCorrectionMonitor.swift" \
  "$ROOT/Tests/PasteCorrectionMonitorTests.swift" \
  -o "$OUTPUT"
exec "$OUTPUT"
