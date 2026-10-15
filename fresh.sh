#!/bin/bash
# ./fresh.sh [again|wipe] [--world NAME] [--visible]
# Build first with ./build.sh debug. Only this checkout's owned world is reset.
set -euo pipefail
cd "$(dirname "$0")"
action=fresh
if [[ "${1:-}" == again || "${1:-}" == wipe ]]; then action="$1"; shift; fi
exec python3 Tests/support/world.py "$action" "$@"
