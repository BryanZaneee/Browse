#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output=${1:-"$repo_root/docs/screenshots"}
mkdir -p "$output"
output=$(CDPATH= cd -- "$output" && pwd)
cd "$repo_root"
BROWSE_PERSISTENCE_SCREENSHOT_DIR="$output" \
    python3 Tests/run-unit-tests.py --filter PersistenceTests/testCapturePersistenceNotices
