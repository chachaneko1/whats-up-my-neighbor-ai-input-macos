#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Neko Desktop Preview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/module-cache" -Onone -framework AppKit -framework SwiftUI -framework WebKit Sources/*.swift -o "$APP/Contents/MacOS/NekoDesktopPreview"
cp -R Viewer "$APP/Contents/Resources/"
cp Resources/cat.png "$APP/Contents/Resources/cat.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NekoDesktopPreview</string>
<key>CFBundleIdentifier</key><string>tw.panh.NekoDesktopSakuraPreview</string>
<key>CFBundleName</key><string>Neko Desktop Preview</string>
<key>CFBundleDisplayName</key><string>Neko 桌面 Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
