#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/AI語音輸入.app"
SIGNING_IDENTITY="${MAC_CODESIGN_IDENTITY:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning |
      awk '/Apple Development:/ { identity = $2 } END { print identity }'
  )"
fi

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$OUTPUT/Contents/Resources/AppIcon.icns"

SOURCES=("$ROOT"/Sources/GroqVoiceInput/*.swift)

swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Carbon \
  -framework Security \
  -framework MultipeerConnectivity \
  "${SOURCES[@]}" \
  -o "$OUTPUT/Contents/MacOS/FreeVoiceType"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    print -u2 "找不到指定的 Mac 簽章身分：$SIGNING_IDENTITY"
    exit 1
  fi
  codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$OUTPUT"
else
  print -u2 "警告：找不到 Apple Development 憑證，改用 ad-hoc 簽章。重新建置後可能需要重新允許輔助使用。"
  codesign --force --deep --sign - \
    --requirements '=designated => identifier "tw.panh.FreeVoiceType"' \
    "$OUTPUT"
fi

codesign --verify --deep --strict --verbose=2 "$OUTPUT"
codesign -d -r- "$OUTPUT"
echo "Built: $OUTPUT"
