#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AI語音輸入.app"
SPARKLE_ROOT="$("$ROOT/scripts/fetch-sparkle.sh")"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources" "$OUTPUT/Contents/Frameworks"
cp "$ROOT/Resources/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$OUTPUT/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/neko-base.png" "$OUTPUT/Contents/Resources/neko-base.png"
cp "$ROOT/cat.config.json" "$ROOT/CAT-CONFIG.md" "$OUTPUT/Contents/Resources/"
cp "$SPARKLE_ROOT/LICENSE" "$OUTPUT/Contents/Resources/Sparkle-LICENSE.txt"
ditto "$SPARKLE_ROOT/Sparkle.framework" "$OUTPUT/Contents/Frameworks/Sparkle.framework"

# CI supplies version metadata to the output bundle, never to tracked sources.
if [[ -n "${RELEASE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$OUTPUT/Contents/Info.plist"
fi
if [[ -n "${RELEASE_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_BUILD" "$OUTPUT/Contents/Info.plist"
fi

SOURCES=("$ROOT"/Sources/GroqVoiceInput/*.swift)

for architecture in arm64 x86_64; do
swiftc \
  -target "$architecture-apple-macos13.0" \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework CoreAudio \
  -framework Carbon \
  -framework Security \
  -framework MultipeerConnectivity \
  -framework UserNotifications \
  -F "$SPARKLE_ROOT" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "${SOURCES[@]}" \
  -o "$ROOT/build/FreeVoiceType-$architecture"
done
lipo -create "$ROOT/build/FreeVoiceType-arm64" "$ROOT/build/FreeVoiceType-x86_64" \
  -output "$OUTPUT/Contents/MacOS/FreeVoiceType"

if [[ "${RELEASE_SIGNING:-0}" == 1 ]]; then
  : "${MAC_CODESIGN_IDENTITY:?Release requires a Developer ID identity}"
  [[ "$MAC_CODESIGN_IDENTITY" == 'Developer ID Application: '* ]] || { print -u2 'Developer ID Application identity required'; exit 1; }
  # Sign nested helpers inside-out. Do not use --deep for production signing.
  FRAMEWORK="$OUTPUT/Contents/Frameworks/Sparkle.framework/Versions/B"
  for helper in "$FRAMEWORK"/XPCServices/*.xpc(N) "$FRAMEWORK"/Updater.app; do
    codesign --force --options runtime --timestamp --sign "$MAC_CODESIGN_IDENTITY" "$helper"
  done
  codesign --force --options runtime --timestamp --sign "$MAC_CODESIGN_IDENTITY" "$FRAMEWORK/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$MAC_CODESIGN_IDENTITY" "$OUTPUT/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --entitlements "$ROOT/Resources/Release.entitlements" \
    --sign "$MAC_CODESIGN_IDENTITY" "$OUTPUT"
else
  # Preserve the established designated requirement for local installs.
  codesign --force --timestamp=none --sign "${MAC_CODESIGN_IDENTITY:--}" \
    --requirements '=designated => identifier "tw.panh.FreeVoiceType"' "$OUTPUT"
fi

codesign --verify --deep --strict --verbose=2 "$OUTPUT"
echo "Built: $OUTPUT"
