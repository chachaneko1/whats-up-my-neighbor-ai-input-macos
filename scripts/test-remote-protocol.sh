#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
IOS_PROTOCOL="$ROOT/../groq-ai-voice-input-ios/Sources/Remote/RemoteMessages.swift"
MAC_PROTOCOL="$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift"
OUTPUT="$ROOT/build/RemoteProtocolTests"

cmp "$MAC_PROTOCOL" "$IOS_PROTOCOL"

swiftc \
  -swift-version 5 \
  "$MAC_PROTOCOL" \
  "$ROOT/Sources/GroqVoiceInput/RemoteTargetValidationPolicy.swift" \
  "$ROOT/Tests/RemoteProtocolTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
