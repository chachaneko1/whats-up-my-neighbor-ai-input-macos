#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/cat-render/interaction"
swiftc -swift-version 5 -D DESKTOP_PET_TESTS -framework AppKit -framework ApplicationServices -framework QuartzCore \
  "$ROOT"/Sources/GroqVoiceInput/DesktopPet*.swift \
  "$ROOT/Tests/DesktopPetInteractionTests.swift" -o "$ROOT/build/DesktopPetInteractionTests"
"$ROOT/build/DesktopPetInteractionTests" "$ROOT/Resources/DesktopPet" "$ROOT/build/cat-render/interaction"
