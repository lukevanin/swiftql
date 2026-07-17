#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    printf 'usage: %s RELEASE_TAG [ISSUES_JSON]\n' "$0" >&2
    exit 64
fi

release_tag="$1"
issues_json="${2:-}"

if [[ "$release_tag" != v1.1.0 ]]; then
    printf 'SWIFTQL_RELEASE_READINESS skipped %s\n' "$release_tag"
    exit 0
fi

temporary_issues=''
cleanup() {
    if [[ -n "$temporary_issues" ]]; then
        rm -f "$temporary_issues"
    fi
}
trap cleanup EXIT

if [[ -z "$issues_json" ]]; then
    repository="${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY}"
    gh_bin="${SWIFTQL_GH_BIN:-gh}"
    temporary_issues="$(mktemp "${TMPDIR:-/tmp}/swiftql-release-issues.XXXXXX")"
    "$gh_bin" api \
        --paginate \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2026-03-10' \
        "repos/$repository/issues?milestone=7&state=open&per_page=100" |
        jq -s 'add' > "$temporary_issues"
    issues_json="$temporary_issues"
fi

if [[ ! -f "$issues_json" ]]; then
    fail "issues JSON does not exist: $issues_json"
fi
if ! jq -e 'type == "array"' "$issues_json" > /dev/null; then
    fail "issues JSON is not an array: $issues_json"
fi

actual_open_issues="$(jq -c \
    '[.[] | select(.pull_request == null) | .number] | sort' \
    "$issues_json")"
expected_open_issues='[118,119]'

if [[ "$actual_open_issues" != "$expected_open_issues" ]]; then
    printf 'error: v1.1.0 requires milestone 7 to have only #118 and #119 open\n' >&2
    printf 'expected: %s\n' "$expected_open_issues" >&2
    printf 'actual:   %s\n' "$actual_open_issues" >&2
    jq -r \
        '.[] | select(.pull_request == null) | "#\(.number) \(.title // "<untitled>")"' \
        "$issues_json" >&2
    exit 1
fi

printf 'SWIFTQL_RELEASE_READINESS ok v1.1.0 open=%s\n' \
    "$actual_open_issues"
