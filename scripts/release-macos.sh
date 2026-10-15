#!/bin/zsh
set -euo pipefail
umask 077
ROOT="${0:A:h:h}"
cd "$ROOT"

for required in RELEASE_VERSION RELEASE_BUILD MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_SHA1 SPARKLE_PRIVATE_KEY; do
  [[ -n "${(P)required:-}" ]] || { print -u2 "Missing release credential/config: $required"; exit 1; }
done
python3 "$ROOT/scripts/release_metadata.py" "v$RELEASE_VERSION" 1 >/dev/null
[[ "$RELEASE_BUILD" =~ '^[1-9][0-9]{0,3}$' ]] || { print -u2 'Invalid release build'; exit 1; }
[[ "$MACOS_SIGNING_SHA1" =~ '^[A-F0-9]{40}$' ]] || { print -u2 'Invalid signing fingerprint'; exit 1; }

RELEASE_TEMP="$(mktemp -d)"
KEYCHAIN="$RELEASE_TEMP/release.keychain-db"
RELEASE_SEARCH_SNAPSHOT="$RELEASE_TEMP/keychain-search.json"
cleanup() {
  python3 "$ROOT/scripts/temporary-keychain.py" restore "$RELEASE_SEARCH_SNAPSHOT" || print -u2 'Warning: keychain search-list restoration failed'
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
# Select by certificate fingerprint, not by a paid Apple certificate category.
# codesign also consults the user search list for the identity's private key.
# Add this keychain only for packaging, then restore the exact list on exit.
python3 "$ROOT/scripts/temporary-keychain.py" add "$KEYCHAIN" "$RELEASE_SEARCH_SNAPSHOT"
security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "$MACOS_SIGNING_SHA1" >/dev/null || { print -u2 'Pinned signing identity is missing, expired or unavailable'; exit 1; }
export MAC_CODESIGN_IDENTITY="$MACOS_SIGNING_SHA1" MAC_CODESIGN_KEYCHAIN="$KEYCHAIN" RELEASE_SIGNING=1
"$ROOT/scripts/build.sh"
APP="$ROOT/build/AI語音輸入.app"
codesign --verify --deep --strict --verbose=2 "$APP"
python3 "$ROOT/scripts/validate-signing.py" "$APP" "$MACOS_SIGNING_SHA1"

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
