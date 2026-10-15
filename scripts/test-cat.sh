#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/cat-render"
python3 "$ROOT/Tests/test_cat_routing.py"
swiftc -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/CatConfiguration.swift" \
  "$ROOT/Tests/CatConfigurationTests.swift" \
  -o "$ROOT/build/CatConfigurationTests"
"$ROOT/build/CatConfigurationTests"
swiftc -swift-version 5 -D CAT_OVERLAY_TESTS -framework AppKit \
  "$ROOT/Sources/GroqVoiceInput/CatConfiguration.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatOverlay.swift" \
  "$ROOT/Tests/CatOverlayTests.swift" \
  -o "$ROOT/build/CatOverlayTests"
"$ROOT/build/CatOverlayTests" "$ROOT/Resources/neko-base.png" "$ROOT/build/cat-render"
