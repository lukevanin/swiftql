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
    : > "$output_log"
    # Each client and the marker it prints when it succeeds. The second
    # depends on the SwiftQLSQLite product alone (issue #790); both share the
    # scratch path, so this proves that client compiles and runs without
    # importing GRDB, and the core boundary check proves the product reaches
    # no GRDB.
    run_client SwiftQLSwift5Client SWIFTQL_DOWNSTREAM_SWIFT5_CLIENT || return 1
    run_client SwiftQLSwift5SQLiteClient SWIFTQL_DOWNSTREAM_SWIFT5_SQLITE_CLIENT || return 1

    test -f "$fixture_root/Package.resolved"
    if [[ "$resolution_mode" == "committed" ]]; then
        cmp "$source_root/Package.resolved" "$fixture_root/Package.resolved"
    fi
}

# Runs one of the fixture's executables, appending to the output log, and
# requires its success marker exactly once in that run's output.
run_client() {
    local product="$1"
    local marker="$2"
    local run_log
    local marker_count

    # Called as `run_client ... || return 1`, so errexit does not apply in
    # here: every step checks its own status.
    run_log="$(mktemp "${TMPDIR:-/tmp}/swiftql-swift5-client-run.XXXXXX")" || return 1
    if ! xcrun swift run \
        --package-path "$fixture_root" \
        --scratch-path "$scratch_path" \
        --force-resolved-versions \
        -v "$product" 2>&1 | tee "$run_log"; then
        cat "$run_log" >> "$output_log"
        rm -f "$run_log"
        printf 'error: %s failed\n' "$product" >&2
        return 1
    fi
    cat "$run_log" >> "$output_log" || return 1

    marker_count="$(grep -c "^$marker ok\$" "$run_log" || true)"
    rm -f "$run_log"
    if [[ "$marker_count" -ne 1 ]]; then
        printf 'error: expected one %s success marker; found %s\n' \
            "$product" "$marker_count" >&2
        return 1
    fi
}

main "$@"
