#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    printf 'usage: %s SOURCE_TAG RELEASE_TAG [CHANGELOG]\n' "$0" >&2
    exit 64
fi

source_tag="$1"
release_tag="$2"
changelog="${3:-CHANGELOG.md}"

if [[ "$source_tag" == release-test/* ]]; then
    printf 'SWIFTQL_RELEASE_CHANGELOG skipped %s\n' "$source_tag"
    exit 0
fi
if [[ "$source_tag" != "$release_tag" ]]; then
    fail "production source tag does not match release tag: $source_tag"
fi
[[ -f "$changelog" ]] || fail "changelog does not exist: $changelog"
version="${release_tag#v}"
escaped_version="${version//./\\.}"
dated_heading="^## \\[$escaped_version\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"
dated_count="$(grep -Ec "$dated_heading" "$changelog" || true)"
if [[ "$dated_count" -ne 1 ]]; then
    fail "CHANGELOG.md must contain one dated heading for $release_tag"
fi
if grep -F "## [$version] - Unreleased" "$changelog" > /dev/null; then
    fail "CHANGELOG.md still marks $release_tag as Unreleased"
fi

printf 'SWIFTQL_RELEASE_CHANGELOG ok %s\n' "$release_tag"
