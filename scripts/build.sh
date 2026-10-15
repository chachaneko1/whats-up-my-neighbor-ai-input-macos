#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AI語音輸入.app"

# Package the same cat artwork used by the in-app HUD and dictionary.
swift "$ROOT/scripts/generate-app-icon.swift" "$ROOT/Resources"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$OUTPUT/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/neko-base.png" "$OUTPUT/Contents/Resources/neko-base.png"

SOURCES=("$ROOT"/Sources/GroqVoiceInput/*.swift)

swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework CoreAudio \
  -framework Carbon \
  -framework Security \
  -framework MultipeerConnectivity \
  "${SOURCES[@]}" \
  -o "$OUTPUT/Contents/MacOS/FreeVoiceType"

# Local installation pins an existing certificate; public builds may remain ad-hoc.
# Keep the established designated requirement so the installed app retains its identity.
codesign --force --deep --timestamp=none --sign "${MAC_CODESIGN_IDENTITY:--}" \
  --requirements '=designated => identifier "tw.panh.FreeVoiceType"' \
  "$OUTPUT"

codesign --verify --deep --strict --verbose=2 "$OUTPUT"
echo "Built: $OUTPUT"
