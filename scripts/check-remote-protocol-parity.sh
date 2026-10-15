#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MAC_PROTOCOL="$ROOT/Sources/GroqVoiceInput/RemoteMessages.swift"

if [[ $# -ne 1 ]]; then
  print -u2 -- "Usage: $0 /path/to/ios/Sources/Remote/RemoteMessages.swift"
  exit 64
fi

IOS_PROTOCOL="$1"
if [[ ! -f "$IOS_PROTOCOL" || ! -r "$IOS_PROTOCOL" ]]; then
  print -u2 -- "iOS protocol file does not exist or is not readable: $IOS_PROTOCOL"
  exit 66
fi

if ! cmp -s "$MAC_PROTOCOL" "$IOS_PROTOCOL"; then
  print -u2 -- "Remote protocol parity failed: macOS and iOS files differ."
  exit 1
fi

print -- "Remote protocol parity passed."
