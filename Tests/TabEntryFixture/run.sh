#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output=${1:-"$repo_root/docs/screenshots"}
mkdir -p "$output"
output=$(CDPATH= cd -- "$output" && pwd)
cd "$repo_root"
SEARCH_PROBE="tab-entry-$$" BROWSE_SCREENSHOT_DIR="$output" \
    swift test --filter NewTabScreenshotTests
