#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AI語音輸入.app"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$OUTPUT/Contents/Resources/AppIcon.icns"

swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Carbon \
  -framework Security \
  "$ROOT/Sources/GroqVoiceInput/main.swift" \
  -o "$OUTPUT/Contents/MacOS/FreeVoiceType"

codesign --force --deep --sign - \
  --requirements '=designated => identifier "tw.panh.FreeVoiceType"' \
  "$OUTPUT"

codesign --verify --deep --strict --verbose=2 "$OUTPUT"
echo "Built: $OUTPUT"
