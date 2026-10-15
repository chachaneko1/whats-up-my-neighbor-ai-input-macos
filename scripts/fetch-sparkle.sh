#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
ARCHIVE="$ROOT/build/Sparkle-$VERSION.tar.xz"
DESTINATION="$ROOT/build/Sparkle-$VERSION"
mkdir -p "$ROOT/build"
if [[ ! -f "$ARCHIVE" ]] || [[ "$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)" != "$SHA256" ]]; then
  curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.download"
  [[ "$(shasum -a 256 "$ARCHIVE.download" | cut -d ' ' -f 1)" == "$SHA256" ]] || { print -u2 'Sparkle checksum mismatch'; exit 1; }
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
# Re-extract from the verified archive rather than trusting a stale cached framework.
rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
tar -xJf "$ARCHIVE" -C "$DESTINATION"
print -r -- "$DESTINATION"
