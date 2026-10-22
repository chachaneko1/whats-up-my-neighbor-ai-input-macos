#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
APP="$ROOT/build/appearance/貓咪花色選單預覽.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>tw.panh.CatCoatMenuPreview</string>
<key>CFBundleName</key><string>貓咪花色選單預覽</string>
<key>CFBundleExecutable</key><string>CatCoatMenuPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
swiftc -target arm64-apple-macos13.0 -swift-version 5 -framework AppKit \
  "$ROOT/Sources/GroqVoiceInput/CatAppearance.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatCoatMenu.swift" \
  "$ROOT/Previews/CatCoatMenu/PreviewMain.swift" \
  -o "$APP/Contents/MacOS/CatCoatMenuPreview"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
print -r -- "$APP"
