#!/bin/zsh
set -euo pipefail

# Renders Packaging/install.sh.template for one release archive and checksum.
ROOT="${0:A:h:h}"
(( $# == 4 )) || { print -u2 'Usage: render-install-script.sh <version> <download-url> <zip-sha256> <output>'; exit 1; }
VERSION="$1"
DOWNLOAD_URL="$2"
ZIP_SHA256="$3"
OUTPUT="$4"

[[ "$VERSION" =~ '^[1-9][0-9]{0,3}\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$' ]] || { print -u2 "Invalid version: $VERSION"; exit 1; }
[[ "$ZIP_SHA256" =~ '^[0-9a-f]{64}$' ]] || { print -u2 'Invalid SHA-256'; exit 1; }
# file:// is only for offline tests. The character set keeps sed and the
# single-quoted shell value free of special characters.
[[ "$DOWNLOAD_URL" =~ '^(https|file)://[A-Za-z0-9._~/%+-]+$' ]] || { print -u2 "Invalid download URL: $DOWNLOAD_URL"; exit 1; }

sed -e "s|@VERSION@|$VERSION|g" -e "s|@DOWNLOAD_URL@|$DOWNLOAD_URL|g" -e "s|@ZIP_SHA256@|$ZIP_SHA256|g" \
  "$ROOT/Packaging/install.sh.template" > "$OUTPUT"
if grep -q '@[A-Z0-9_]*@' "$OUTPUT"; then
  print -u2 'Unrendered placeholder in install script'
  exit 1
fi
zsh -n "$OUTPUT"
chmod +x "$OUTPUT"
