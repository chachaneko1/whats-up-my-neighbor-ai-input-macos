#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/VPSDesktopAvailabilityTests"

mkdir -p "$ROOT/build"

swiftc \
  -swift-version 5 \
  "$ROOT/Sources/GroqVoiceInput/VPSDesktopAvailability.swift" \
  "$ROOT/Tests/VPSDesktopAvailabilityTests.swift" \
  -o "$OUTPUT"

"$OUTPUT"
