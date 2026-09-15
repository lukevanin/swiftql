#!/bin/bash
#
# Requires every published-version claim on the tagged commit to name the
# version being released (RELEASING.md, "Documentation currency").
#
# The claim about which version is published lives in six places: README.md,
# GettingStarted.md, SwiftQL.md, SKILL.md's front-matter description and its
# body, and Website/index.html. A published release is immutable, so a claim
# left on the previous version ships stale and cannot be corrected in place.
# The Swift test suite checks only that those documents agree with the newest
# dated CHANGELOG heading, which keeps a version bump free of test edits; this
# gate is what ties them to the tag.
#
# Each claim is matched as a whole sentence, after collapsing whitespace, so a
# claim re-wrapped across lines still counts. Every Swift Package Manager
# requirement on SwiftQL in the same documents must name the version too, so a
# bumped sentence cannot sit beside a stale `from:` line.
#
# Test tags below `release-test/` are skipped outright, exactly as
# check-release-changelog.sh skips them: their version is a placeholder that
# no document names.

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    printf 'usage: %s SOURCE_TAG RELEASE_TAG [REPOSITORY_ROOT]\n' "$0" >&2
    exit 64
fi

source_tag="$1"
release_tag="$2"
repository_root="${3:-.}"

if [[ "$source_tag" == release-test/* ]]; then
    printf 'SWIFTQL_RELEASE_VERSION_CLAIMS skipped %s\n' "$source_tag"
    exit 0
fi
if [[ "$source_tag" != "$release_tag" ]]; then
    fail "production source tag does not match release tag: $source_tag"
fi
if [[ ! "$release_tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    fail "release tag is not vMAJOR.MINOR.PATCH: $release_tag"
fi
version="${BASH_REMATCH[1]}"

failures=0

report() {
    printf 'error: %s\n' "$*" >&2
    failures=$((failures + 1))
}

# Runs in this shell, never inside `$(...)`: a failure counted in a command
# substitution's subshell would be lost, and a missing document would pass.
require_document() {
    local path="$repository_root/$1"
    if [[ ! -f "$path" || -L "$path" ]]; then
        report "missing or unsafe version-claim document: $1"
        return 1
    fi
}

# Collapses every run of whitespace, newlines included, to one space.
normalized() {
    tr -s '[:space:]' ' '
}

require_claim() {
    local document="$1"
    local claim="$2"
    local contents

    require_document "$document" || return 0
    contents="$(cat "$repository_root/$document")"
    if ! grep -Fq -- "$claim" <<< "$(normalized <<< "$contents")"; then
        report "$document does not claim $version is published; expected: $claim"
    fi
}

# The first `description:` line of SKILL.md's YAML front matter.
require_skill_description_claim() {
    local claim="$1"
    local contents
    local description

    require_document SKILL.md || return 0
    contents="$(cat "$repository_root/SKILL.md")"
    description="$(
        awk 'NR == 1 && $0 != "---" { exit }
             NR > 1 && $0 == "---" { exit }
             NR > 1 && /^description:/ { print; exit }' <<< "$contents"
    )"
    if [[ -z "$description" ]]; then
        report "SKILL.md has no front-matter description line"
    elif ! grep -Fq -- "$claim" <<< "$description"; then
        report "SKILL.md's front-matter description does not claim $version is published; expected: $claim"
    fi
}

require_current_package_requirements() {
    local document="$1"
    local contents
    local requirement
    local expected=".package(url: \"https://github.com/lukevanin/swiftql.git\", from: \"$version\")"

    # Presence is already reported by require_claim for every document.
    [[ -f "$repository_root/$document" && ! -L "$repository_root/$document" ]] ||
        return 0
    contents="$(cat "$repository_root/$document")"
    while IFS= read -r requirement; do
        [[ -n "$requirement" ]] || continue
        if [[ "$requirement" != "$expected" ]]; then
            report "$document requires a different SwiftQL version: $requirement"
        fi
    done < <(
        grep -oE '\.package\(url: "https://github\.com/lukevanin/swiftql\.git", from: "[^"]*"\)' \
            <<< "$contents" || true
    )
}

require_claim README.md "\`$version\` is the latest published package"
require_claim Sources/SwiftQL/SwiftQL.docc/GettingStarted.md \
    "Version $version is the published package"
require_claim Sources/SwiftQL/SwiftQL.docc/SwiftQL.md \
    "Version $version is the latest published package"
require_skill_description_claim "$version is the latest published package"
require_claim SKILL.md "\`$version\` is the latest published package"
require_claim Website/index.html \
    ".package(url: \"https://github.com/lukevanin/swiftql.git\", from: \"$version\")"

for document in \
    README.md \
    Sources/SwiftQL/SwiftQL.docc/GettingStarted.md \
    Sources/SwiftQL/SwiftQL.docc/SwiftQL.md \
    SKILL.md \
    Website/index.html; do
    require_current_package_requirements "$document"
done

if (( failures != 0 )); then
    fail "$failures published-version claim(s) do not name $release_tag"
fi

printf 'SWIFTQL_RELEASE_VERSION_CLAIMS ok %s\n' "$release_tag"
