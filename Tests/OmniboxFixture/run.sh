#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/browse-omnibox-fixture.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
output=${1:-"$repo_root/docs/screenshots"}
source="$repo_root/Sources/Search/Omnibox.swift"
if [ "${2:-}" = "--before" ]; then
    git -C "$repo_root" show 3241006e72b8b4c4212095552eaed8f9d99f226a:Sources/Search/Omnibox.swift > "$test_root/Omnibox.swift"
    source="$test_root/Omnibox.swift"
fi
swiftc -parse-as-library -swift-version 5 \
    "$repo_root/Sources/Search/Design.swift" \
    "$repo_root/Sources/Search/Address.swift" \
    "$source" \
    "$repo_root/Tests/OmniboxFixture/Stubs.swift" \
    "$repo_root/Tests/OmniboxFixture/main.swift" \
    -o "$test_root/fixture"
mkdir -p "$output"
"$test_root/fixture" "$output" "${2:-}"
