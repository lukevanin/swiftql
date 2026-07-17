#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    printf 'usage: %s SOURCE_TAG EXPECTED_SHA [MAIN_REF]\n' "$0" >&2
    exit 64
fi

source_tag="$1"
expected_sha="$2"
main_ref="${3:-refs/remotes/origin/main}"

release_component='(0|[1-9][0-9]*)'
production_pattern="^v${release_component}\\.${release_component}\\.${release_component}$"
dry_run_pattern="^release-test/v${release_component}\\.${release_component}\\.${release_component}$"

if [[ "$source_tag" =~ $production_pattern ]]; then
    mode=publish
    release_tag="$source_tag"
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
elif [[ "$source_tag" =~ $dry_run_pattern ]]; then
    mode=dry-run
    release_tag="${source_tag#release-test/}"
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
else
    fail "release tag must be vMAJOR.MINOR.PATCH or release-test/vMAJOR.MINOR.PATCH: $source_tag"
fi

if [[ "$major" == 0 || ( "$major" == 1 && "$minor" == 0 ) ]]; then
    fail "new SwiftQL release tags begin at v1.1.0: $release_tag"
fi

if [[ ! "$expected_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
    fail "expected SHA is not a full Git object ID: $expected_sha"
fi

tag_commit="$(git rev-parse --verify "refs/tags/$source_tag^{commit}")" ||
    fail "could not peel tag to a commit: $source_tag"
event_commit="$(git rev-parse --verify "$expected_sha^{commit}")" ||
    fail "could not peel event SHA to a commit: $expected_sha"
head_commit="$(git rev-parse --verify 'HEAD^{commit}')" ||
    fail 'could not resolve HEAD'
main_commit="$(git rev-parse --verify "$main_ref^{commit}")" ||
    fail "could not resolve main ref: $main_ref"

if [[ "$tag_commit" != "$event_commit" ]]; then
    fail "tag commit $tag_commit does not match event commit $event_commit"
fi
if [[ "$head_commit" != "$event_commit" ]]; then
    fail "checked-out HEAD $head_commit does not match event commit $event_commit"
fi
if ! git merge-base --is-ancestor "$tag_commit" "$main_commit"; then
    fail "tag commit $tag_commit is not reachable from $main_ref ($main_commit)"
fi

printf 'mode=%s\n' "$mode"
printf 'source_tag=%s\n' "$source_tag"
printf 'release_tag=%s\n' "$release_tag"
printf 'commit_sha=%s\n' "$tag_commit"
printf 'SWIFTQL_RELEASE_REF ok %s %s %s\n' \
    "$mode" "$source_tag" "$tag_commit" >&2
