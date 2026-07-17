#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    printf 'usage: %s SOURCE_TAG RELEASE_TAG COMMIT_SHA\n' "$0" >&2
    exit 64
fi

source_tag="$1"
release_tag="$2"
commit_sha="$3"
script_directory="$(cd "$(dirname "$0")" && pwd -P)"

git fetch --force origin \
    'refs/heads/main:refs/remotes/origin/main' \
    "+refs/tags/$source_tag:refs/tags/$source_tag"
"$script_directory/check-release-ref.sh" \
    "$source_tag" "$commit_sha" > /dev/null
"$script_directory/check-release-readiness.sh" "$release_tag"
"$script_directory/check-release-changelog.sh" \
    "$source_tag" "$release_tag"

printf 'SWIFTQL_PRE_PUBLISH_CHECK ok %s %s\n' \
    "$source_tag" "$commit_sha"
