#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/cat-coat"
swiftc -swift-version 5 -D CAT_COAT_TESTS -D DESKTOP_PET_TESTS -framework AppKit -framework ApplicationServices \
  "$ROOT"/Sources/GroqVoiceInput/CatCoat*.swift \
  "$ROOT/Sources/GroqVoiceInput/CatAdoptionController.swift" \
  "$ROOT"/Sources/GroqVoiceInput/DesktopPet*.swift \
  "$ROOT/Sources/GroqVoiceInput/StatusMenuController.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoMenuBarIcon.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoSignalMeter.swift" \
  "$ROOT/Sources/GroqVoiceInput/DictationCoordinator.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Tests/CatCoatTests.swift" -o "$ROOT/build/CatCoatTests"
"$ROOT/build/CatCoatTests" "$ROOT/Resources/DesktopPet" "$ROOT/build/cat-coat"
