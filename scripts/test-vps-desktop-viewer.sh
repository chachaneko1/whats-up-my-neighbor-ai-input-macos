#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
NODE="$(command -v node || true)"
for candidate in /opt/homebrew/opt/node@24/bin/node /opt/homebrew/bin/node /usr/local/bin/node; do
  [[ -n "$NODE" ]] && break
  [[ -x "$candidate" ]] && NODE="$candidate"
done
if [[ -z "$NODE" ]]; then
  print -- "Skipping VPS desktop viewer tests: Node.js is not installed."
  exit 0
fi
"$NODE" --test "$ROOT/Tests/vps-desktop-viewer.test.mjs"
