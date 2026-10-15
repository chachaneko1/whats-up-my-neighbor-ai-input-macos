#!/bin/zsh
set -euo pipefail
umask 077
ROOT="${0:A:h:h}"
cd "$ROOT"

[[ "${GITHUB_ACTIONS:-}" == true ]] || { print -u2 'Release credentials are only imported on an ephemeral Actions runner'; exit 1; }
for required in RELEASE_VERSION RELEASE_BUILD MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_TEAM_ID APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID SPARKLE_PRIVATE_KEY; do
  [[ -n "${(P)required:-}" ]] || { print -u2 "Missing release credential/config: $required"; exit 1; }
done
python3 "$ROOT/scripts/release_metadata.py" "v$RELEASE_VERSION" 1 >/dev/null
[[ "$RELEASE_BUILD" =~ '^[1-9][0-9]{0,3}$' ]] || { print -u2 'Invalid release build'; exit 1; }
[[ "$MACOS_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || { print -u2 'Invalid Team ID'; exit 1; }

RELEASE_TEMP="$(mktemp -d)"
KEYCHAIN="$RELEASE_TEMP/release.keychain-db"
cleanup() {
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$RELEASE_TEMP"
}
trap cleanup EXIT
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
print -rn -- "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$RELEASE_TEMP/certificate.p12"
security import "$RELEASE_TEMP/certificate.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
MAC_CODESIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
[[ -n "$MAC_CODESIGN_IDENTITY" && "$MAC_CODESIGN_IDENTITY" == *"($MACOS_TEAM_ID)" ]] || { print -u2 'Matching Developer ID Application identity not found'; exit 1; }
export MAC_CODESIGN_IDENTITY RELEASE_SIGNING=1
"$ROOT/scripts/build.sh"
APP="$ROOT/build/AI語音輸入.app"
print -rn -- "$APPLE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$RELEASE_TEMP/AuthKey.p8"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_TEMP/notary.zip"
xcrun notarytool submit "$RELEASE_TEMP/notary.zip" --key "$RELEASE_TEMP/AuthKey.p8" \
  --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --timeout 30m
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# Sparkle updates contain only .app; first installations use a separate archive.
rm -rf "$ROOT/dist/update"
mkdir -p "$ROOT/dist/update"
UPDATE_ARCHIVE="$ROOT/dist/update/Neighbor-macOS-$RELEASE_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPDATE_ARCHIVE"
cp "$ROOT/RELEASE_NOTES.md" "${UPDATE_ARCHIVE:r}.md"
SPARKLE_ROOT="$ROOT/build/Sparkle-2.10.0"
print -rn -- "$SPARKLE_PRIVATE_KEY" > "$RELEASE_TEMP/sparkle.key"
"$SPARKLE_ROOT/bin/generate_appcast" --ed-key-file "$RELEASE_TEMP/sparkle.key" \
  --download-url-prefix "https://github.com/yuipan0611/groq-ai-voice-input-macos/releases/download/v$RELEASE_VERSION/" \
  --maximum-deltas 0 --embed-release-notes "$ROOT/dist/update"
python3 "$ROOT/scripts/validate-release.py" "$APP" "$ROOT/dist/update/appcast.xml" "$UPDATE_ARCHIVE"
PACKAGE_EXISTING_BUILD=1 "$ROOT/scripts/package-release.sh" "$RELEASE_VERSION"
(cd "$ROOT/dist/update" && shasum -a 256 *.zip > SHA256SUMS.txt)
