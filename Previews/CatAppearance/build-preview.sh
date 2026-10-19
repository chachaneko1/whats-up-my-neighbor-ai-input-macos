#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
APP="$ROOT/build/appearance/自然毛色預覽.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto "$ROOT/Resources/DesktopPet" "$APP/Contents/Resources/DesktopPet"
ditto "$ROOT/Examples/CatAppearance" "$APP/Contents/Resources/Examples"
cp "$ROOT/Resources/neko-base.png" "$APP/Contents/Resources/neko-base.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>tw.panh.NekoAppearancePreview</string>
<key>CFBundleName</key><string>自然毛色預覽</string>
<key>CFBundleExecutable</key><string>NekoAppearancePreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
swiftc -O -swift-version 5 -framework AppKit -framework ApplicationServices -framework QuartzCore \
  "$ROOT"/Sources/GroqVoiceInput/DesktopPet*.swift \
  "$ROOT/Sources/GroqVoiceInput/CatAppearance.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatAnatomy.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatAppearanceArtwork.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatConfiguration.swift" \
  "$ROOT/Sources/GroqVoiceInput/CatOverlay.swift" \
  "$ROOT/Sources/GroqVoiceInput/LanguagePolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextPostProcessor.swift" \
  "$ROOT/Sources/GroqVoiceInput/DictationCoordinator.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoSignalMeter.swift" \
  "$ROOT/Sources/GroqVoiceInput/NekoRecordingHUD.swift" \
  "$ROOT/Previews/CatAppearance/PreviewMain.swift" \
  -o "$APP/Contents/MacOS/NekoAppearancePreview"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
print -r -- "$APP"
