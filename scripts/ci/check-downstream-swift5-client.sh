#!/bin/bash

set -euo pipefail

main() {
    local resolution_mode
    local source_root
    local fixture_root
    local scratch_path
    local output_log
    local marker_count

    if [[ "$#" -gt 2 ]]; then
        printf 'usage: %s [committed|clean] [OUTPUT_LOG]\n' "$0" >&2
        return 64
    fi

    resolution_mode="${1:-committed}"
    case "$resolution_mode" in
        committed|clean)
            ;;
        *)
            printf 'error: unsupported resolution mode: %s\n' "$resolution_mode" >&2
            return 64
            ;;
    esac

    source_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
    fixture_root="$source_root/IntegrationTests/Swift5Client"
    scratch_path="${SWIFTQL_DOWNSTREAM_SCRATCH_PATH:-${TMPDIR:-/tmp}/swiftql-swift5-client-build}"
    output_log="${2:-${TMPDIR:-/tmp}/swiftql-swift5-client.log}"

    if [[ "$resolution_mode" == "committed" ]]; then
        test -f "$source_root/Package.resolved"
        test -f "$fixture_root/Package.resolved"
        cmp "$source_root/Package.resolved" "$fixture_root/Package.resolved"
    else
        test ! -e "$fixture_root/Package.resolved"
        xcrun swift package \
            --package-path "$fixture_root" \
            --scratch-path "$scratch_path" \
            resolve
        test -f "$fixture_root/Package.resolved"
    fi

    xcrun swift package \
        --package-path "$fixture_root" \
        --scratch-path "$scratch_path" \
        clean
    xcrun swift run \
        --package-path "$fixture_root" \
        --scratch-path "$scratch_path" \
        --force-resolved-versions \
        -v 2>&1 | tee "$output_log"

    marker_count="$(grep -c '^SWIFTQL_DOWNSTREAM_SWIFT5_CLIENT ok$' "$output_log" || true)"
    if [[ "$marker_count" -ne 1 ]]; then
        printf 'error: expected one downstream client success marker; found %s\n' \
            "$marker_count" >&2
        return 1
    fi

    test -f "$fixture_root/Package.resolved"
    if [[ "$resolution_mode" == "committed" ]]; then
        cmp "$source_root/Package.resolved" "$fixture_root/Package.resolved"
    fi
}

main "$@"
