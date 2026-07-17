#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=compiler-diagnostics-lib.sh
source "$script_directory/compiler-diagnostics-lib.sh"

main() {
    local build_log
    local source_root
    local scratch_root

    if [[ "$#" -gt 1 ]]; then
        printf 'usage: %s [BUILD_LOG]\n' "$0" >&2
        return 64
    fi

    source_root="$(cd "$script_directory/../.." && pwd -P)"
    build_log="${1:-${TMPDIR:-/tmp}/swiftql-first-party-warnings.log}"
    scratch_root="$(
        swiftql_prepare_scratch_root \
            "$source_root" "${SWIFTQL_SCRATCH_PATH:-}"
    )"

    swiftql_run_diagnostic_classifier_self_tests \
        "$source_root" "$scratch_root" "SWIFTQL_FIRST_PARTY_WARNING_GATE"

    # A clean --build-tests build covers every first-party product and test
    # target and prevents an incremental no-op from hiding diagnostics.
    cd "$source_root"
    xcrun swift package --scratch-path "$scratch_root" clean
    xcrun swift build --scratch-path "$scratch_root" --build-tests -v \
        2>&1 | tee "$build_log"

    if [[ ! -s "$build_log" ]]; then
        printf 'error: compiler diagnostic log is empty: %s\n' "$build_log" >&2
        return 1
    fi

    swiftql_classify_build_log \
        "$build_log" \
        "$source_root" \
        "$scratch_root" \
        "SWIFTQL_FIRST_PARTY_WARNING_GATE" \
        "first-party warnings-as-errors gate emitted blocking warnings"
}

main "$@"
