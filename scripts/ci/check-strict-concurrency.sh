#!/bin/bash

set -euo pipefail

if [[ "$#" -gt 1 ]]; then
    printf 'usage: %s [BUILD_LOG]\n' "$0" >&2
    exit 64
fi

build_log="${1:-${TMPDIR:-/tmp}/swiftql-strict-concurrency.log}"
source_root="$(pwd -P)"

# A clean build prevents an incremental no-op from hiding compiler diagnostics.
if [[ -n "${SWIFTQL_SCRATCH_PATH:-}" ]]; then
    xcrun swift package --scratch-path "$SWIFTQL_SCRATCH_PATH" clean
    xcrun swift build --scratch-path "$SWIFTQL_SCRATCH_PATH" --build-tests -v \
        -Xswiftc -strict-concurrency=complete \
        -Xswiftc -warn-concurrency 2>&1 | tee "$build_log"
else
    xcrun swift package clean
    xcrun swift build --build-tests -v \
        -Xswiftc -strict-concurrency=complete \
        -Xswiftc -warn-concurrency 2>&1 | tee "$build_log"
fi

allowed_ordinary_warnings=()
dependency_warnings=()
other_build_warnings=()
unexpected_first_party_warnings=()

is_known_ordinary_warning() {
    case "$1" in
        *"warning: 'result' is deprecated:"*)
            return 0
            ;;
        *"warning: TODO:"*)
            return 0
            ;;
        *"warning: variable 'output' was never mutated;"*)
            return 0
            ;;
        *"warning: variable 'config' was never mutated;"*)
            return 0
            ;;
    esac
    return 1
}

warning_headers="$({
    grep -E \
        '(^/.*:[0-9]+:[0-9]+: warning:|^(Sources|Tests|Benchmarks)/.*:[0-9]+:[0-9]+: warning:|^macro expansion .*: warning:|^warning: )' \
        "$build_log" || true
} | awk '!seen[$0]++')"

while IFS= read -r warning; do
    [[ -z "$warning" ]] && continue

    case "$warning" in
        *"/.build/checkouts/"*|*"/SourcePackages/checkouts/"*|\
        "warning: 'grdb.swift':"*|"warning: 'swift-syntax':"*|\
        "warning: 'swift-docc-plugin':"*|"warning: 'swift-docc-symbolkit':"*)
            dependency_warnings+=("$warning")
            continue
            ;;
    esac

    case "$warning" in
        /Applications/*|/Library/Developer/*|/usr/*)
            other_build_warnings+=("$warning")
            ;;
        "$source_root"/*|/*|Sources/*|Tests/*|Benchmarks/*|macro\ expansion\ *)
            if is_known_ordinary_warning "$warning"; then
                allowed_ordinary_warnings+=("$warning")
            else
                unexpected_first_party_warnings+=("$warning")
            fi
            ;;
        *)
            other_build_warnings+=("$warning")
            ;;
    esac
done < <(printf '%s\n' "$warning_headers")

print_section() {
    local heading="$1"
    shift
    printf '%s\n' "$heading"
    if [[ "$#" -eq 0 ]]; then
        printf '%s\n' "<none>"
    else
        printf '%s\n' "$@"
    fi
}

# Bash 3.2 treats an empty array expansion as unset under `set -u`.
set +u
print_section \
    "SWIFTQL_STRICT_CONCURRENCY_ALLOWED_ORDINARY_WARNINGS" \
    "${allowed_ordinary_warnings[@]}"
print_section \
    "SWIFTQL_STRICT_CONCURRENCY_DEPENDENCY_WARNINGS" \
    "${dependency_warnings[@]}"
print_section \
    "SWIFTQL_STRICT_CONCURRENCY_OTHER_BUILD_WARNINGS" \
    "${other_build_warnings[@]}"
print_section \
    "SWIFTQL_STRICT_CONCURRENCY_UNEXPECTED_FIRST_PARTY_WARNINGS" \
    "${unexpected_first_party_warnings[@]}"
set -u

if [[ "${#unexpected_first_party_warnings[@]}" -ne 0 ]]; then
    printf '%s\n' \
        "error: complete strict-concurrency checking emitted unexpected first-party warnings" \
        >&2
    exit 1
fi

printf '%s\n' "SWIFTQL_STRICT_CONCURRENCY_STATUS clean"
