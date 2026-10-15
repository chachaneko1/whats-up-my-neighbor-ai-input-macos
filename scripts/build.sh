#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AI語音輸入.app"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$OUTPUT/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/neko-base.png" "$OUTPUT/Contents/Resources/neko-base.png"
cp "$ROOT/cat.config.json" "$ROOT/CAT-CONFIG.md" "$OUTPUT/Contents/Resources/"

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

codesign --force --deep --sign - \
  --requirements '=designated => identifier "tw.panh.FreeVoiceType"' \
  "$OUTPUT"

codesign --verify --deep --strict --verbose=2 "$OUTPUT"
echo "Built: $OUTPUT"
