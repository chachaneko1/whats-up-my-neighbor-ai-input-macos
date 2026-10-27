#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
"$ROOT/Previews/CatAppearance/build-preview.sh"
APP="$ROOT/build/tuxedo-preview/賓士貓口鼻修正預覽.app"
mkdir -p "$ROOT/build/tuxedo-preview"
ditto "$ROOT/build/appearance/自然毛色預覽.app" "$APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier tw.panh.NekoTuxedoMuzzlePreview' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 賓士貓口鼻修正預覽' "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
print -r -- "$APP"
