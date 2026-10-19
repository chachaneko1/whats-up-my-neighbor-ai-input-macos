#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/appearance"
swiftc -O -swift-version 5 -D DESKTOP_PET_TESTS -D CAT_OVERLAY_TESTS \
  -framework AppKit -framework ApplicationServices -framework QuartzCore \
  "$ROOT"/Sources/GroqVoiceInput/DesktopPet*.swift \
  "$ROOT/Sources/GroqVoiceInput/CatAppearance.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatAnatomy.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatAppearanceArtwork.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatConfiguration.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatOverlay.swift" \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Sources/GroqVoiceInput/DictationCoordinator.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoSignalMeter.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoRecordingHUD.swift" \
  "$ROOT/Tests/CatAppearanceTests.swift" -o "$ROOT/build/appearance/CatAppearanceTests"
"$ROOT/build/appearance/CatAppearanceTests" "$ROOT" "$ROOT/build/appearance"
