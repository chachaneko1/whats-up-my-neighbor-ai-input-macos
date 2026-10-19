#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/cat-render/desktop-pet"
swiftc -swift-version 5 -D DESKTOP_PET_TESTS -framework AppKit -framework ApplicationServices \
  "$ROOT"/Sources/GroqVoiceInput/DesktopPet*.swift \
  "$ROOT/Sources/GroqVoiceInput/CatAppearance.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatAnatomy.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatAppearanceArtwork.swift" \
  "$ROOT/Tests/DesktopPetTests.swift" -o "$ROOT/build/DesktopPetTests"
"$ROOT/build/DesktopPetTests" "$ROOT/Resources/DesktopPet" "$ROOT/build/cat-render/desktop-pet"
