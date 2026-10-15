#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
swiftc -swift-version 5 -D NEKO_HUD_TESTING -framework AppKit \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Sources/GroqVoiceInput/DictationCoordinator.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoSignalMeter.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoRecordingHUD.swift" \
  "$ROOT/Tests/NekoHUDTests.swift" \
  -o "$ROOT/build/NekoHUDTests"
"$ROOT/build/NekoHUDTests" "$ROOT/Resources/neko-base.png"
