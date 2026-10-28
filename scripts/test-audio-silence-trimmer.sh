#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AudioSilenceTrimmerTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/AudioSilenceTrimmer.swift" \
  "$ROOT/Sources/GroqVoiceInput/GroqDictationTranscriber.swift" \
  "$ROOT/Sources/GroqVoiceInput/GroqTranscriptionClient.swift" \
  "$ROOT/Sources/GroqVoiceInput/DictationCoordinator.swift" \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Tests/AudioSilenceTrimmerTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"

