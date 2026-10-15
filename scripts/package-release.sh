#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
if (( $# > 0 )); then
  VERSION="$1"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
fi
STAGE="$ROOT/dist/Groq-AI語音輸入-v$VERSION"
ZIP="$ROOT/dist/Groq-AI-Voice-Input-macOS-v$VERSION.zip"

if [[ "${PACKAGE_EXISTING_BUILD:-0}" != 1 ]]; then
  "$ROOT/scripts/build.sh"
fi
codesign --verify --deep --strict "$ROOT/build/AI語音輸入.app"
rm -rf "$STAGE" "$ZIP" "$ZIP.sha256"
mkdir -p "$STAGE"
ditto "$ROOT/build/AI語音輸入.app" "$STAGE/AI語音輸入.app"
cp "$ROOT/Packaging/安裝.command" "$STAGE/安裝.command"
cp "$ROOT/Packaging/移除.command" "$STAGE/移除.command"
cp "$ROOT/Packaging/使用說明.md" "$STAGE/使用說明.md"
chmod +x "$STAGE/安裝.command" "$STAGE/移除.command"

ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"
(cd "$ROOT/dist" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")
echo "Packaged: $ZIP"
