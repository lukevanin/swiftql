#!/bin/bash

set -euo pipefail

if [[ "$#" -eq 0 ]]; then
    printf 'usage: %s BUILD_LOG [BUILD_LOG ...]\n' "$0" >&2
    exit 64
fi

available_logs=()
for log in "$@"; do
    if [[ -f "$log" ]]; then
        available_logs+=("$log")
    else
        printf 'Diagnostic log was not produced: %s\n' "$log"
    fi
done

if [[ "${#available_logs[@]}" -eq 0 ]]; then
    printf '%s\n' "SWIFTQL_FIRST_PARTY_DIAGNOSTICS"
    printf '%s\n' "<unavailable: no build logs>"
    printf '%s\n' "SWIFTQL_DEPENDENCY_DIAGNOSTICS"
    printf '%s\n' "<unavailable: no build logs>"
    exit 0
fi
warnings="$(grep -h 'warning:' "${available_logs[@]}" || true)"
dependency_pattern="/(\\.build|SourcePackages)/checkouts/|warning: ['\"]?(grdb\\.swift|swift-syntax|swift-docc-plugin|swift-docc-symbolkit)['\"]?:"
dependency_warnings="$(
    printf '%s\n' "$warnings" |
        grep -Ei "$dependency_pattern" || true
)"
first_party_warnings="$(
    printf '%s\n' "$warnings" |
        grep -Eiv "$dependency_pattern" || true
)"

printf '%s\n' "SWIFTQL_FIRST_PARTY_DIAGNOSTICS"
if [[ -n "$first_party_warnings" ]]; then
    printf '%s\n' "$first_party_warnings"
else
    printf '%s\n' "<none>"
fi

printf '%s\n' "SWIFTQL_DEPENDENCY_DIAGNOSTICS"
if [[ -n "$dependency_warnings" ]]; then
    printf '%s\n' "$dependency_warnings"
else
    printf '%s\n' "<none>"
fi
