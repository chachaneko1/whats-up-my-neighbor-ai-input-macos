#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
APP="$ROOT/build/ClipboardPickerTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/neko-base.png" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>ClipboardPickerTests</string><key>CFBundleIdentifier</key><string>tw.panh.ClipboardPickerTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -swift-version 5 -D CLIPBOARD_PICKER_TESTING -framework AppKit -framework ImageIO \
  "$ROOT/Sources/GroqVoiceInput/ClipboardHistoryStore.swift" \
  "$ROOT/Sources/GroqVoiceInput/PasteDiagnostics.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Sources/GroqVoiceInput/FocusTargetService.swift" \
  "$ROOT/Sources/GroqVoiceInput/TextInsertionService.swift" \
  "$ROOT/Sources/GroqVoiceInput/ClipboardPickerController.swift" \
  "$ROOT/Tests/ClipboardPickerTests.swift" \
  -o "$APP/Contents/MacOS/ClipboardPickerTests"
"$APP/Contents/MacOS/ClipboardPickerTests" "$ROOT/build"
