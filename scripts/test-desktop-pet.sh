#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/cat-render/desktop-pet"
swiftc -swift-version 5 -D DESKTOP_PET_TESTS -framework AppKit -framework ApplicationServices \
  "$ROOT"/Sources/GroqVoiceInput/CatCoat*.swift \
  "$ROOT"/Sources/GroqVoiceInput/DesktopPet*.swift \
  "$ROOT/Tests/DesktopPetTests.swift" -o "$ROOT/build/DesktopPetTests"
"$ROOT/build/DesktopPetTests" "$ROOT/Resources/DesktopPet" "$ROOT/build/cat-render/desktop-pet"
