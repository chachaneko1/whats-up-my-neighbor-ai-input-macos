#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MAC_PROTOCOL="$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift"
OUTPUT="$ROOT/build/RemoteProtocolTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$MAC_PROTOCOL" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Tests/RemoteProtocolTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
