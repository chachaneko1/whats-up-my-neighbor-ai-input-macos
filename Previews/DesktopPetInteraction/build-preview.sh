#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
SOURCE="$ROOT/Previews/DesktopPetInteraction"
OUTPUT="$ROOT/build/desktop-pet-interaction"
APP="$OUTPUT/小黑貓互動預覽.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/DesktopPet" "$OUTPUT/renders"
ditto "$SOURCE/BaseArtwork" "$APP/Contents/Resources/DesktopPet"
cp "$SOURCE"/ExtraArtwork/*.svg "$APP/Contents/Resources/DesktopPet/"
mkdir -p "$APP/Contents/Resources/DesktopPet/Pickup"
rm -f "$APP/Contents/Resources/DesktopPet/Pickup/"*.png(N)
cp "$SOURCE"/GeminiArtwork/Direct32/Frames/*.png "$APP/Contents/Resources/DesktopPet/Pickup/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>tw.panh.NekoInteractionPreview</string>
<key>CFBundleName</key><string>小黑貓互動預覽</string>
<key>CFBundleExecutable</key><string>NekoInteractionPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.7</string>
<key>CFBundleVersion</key><string>20261018.7</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
swiftc -swift-version 5 -framework AppKit -framework ApplicationServices -framework QuartzCore \
  "$SOURCE/DesktopPetModel.swift" "$SOURCE/DesktopPetView.swift" \
  "$SOURCE/DesktopPetController.swift" "$SOURCE/PreviewMain.swift" \
  -o "$APP/Contents/MacOS/NekoInteractionPreview"
swiftc -swift-version 5 -D DESKTOP_PET_TESTS -framework AppKit -framework ApplicationServices -framework QuartzCore \
  "$SOURCE/DesktopPetModel.swift" "$SOURCE/DesktopPetView.swift" \
  "$SOURCE/DesktopPetController.swift" "$SOURCE/PreviewTests.swift" \
  -o "$OUTPUT/PreviewTests"
"$OUTPUT/PreviewTests" "$APP/Contents/Resources/DesktopPet" "$OUTPUT/renders"
plutil -lint "$APP/Contents/Info.plist"
print -r -- "$APP"
