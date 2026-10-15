#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/meeting -p 'test_*.py' -v
