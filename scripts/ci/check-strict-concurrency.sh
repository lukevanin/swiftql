#!/bin/bash

set -euo pipefail

is_known_ordinary_warning() {
    local warning="$1"

    case "$warning" in
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

is_known_manifest_warning() {
    local warning="$1"
    local source_root="$2"

    [[ "$warning" == "warning: 'swiftql': "* ]] && \
        [[ "$warning" == *" -primary-file $source_root/Package.swift "* ]] && \
        [[ "$warning" == *" -package-description-version 5.9.0 "* ]] && \
        [[ "$warning" == *" -module-name main "* ]]
}

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

classify_build_log() {
    local build_log="$1"
    local source_root="$2"
    local warning_headers
    local warning
    local -a allowed_ordinary_warnings=()
    local -a dependency_warnings=()
    local -a other_build_warnings=()
    local -a unexpected_first_party_warnings=()
    local -a unclassified_warnings=()

    warning_headers="$({
        grep -E \
            '(^[^[:space:]].*:[0-9]+(:[0-9]+)?: warning:|^macro expansion .*: warning:|^warning: |^[^[:space:]][^:]*: warning: )' \
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

        if is_known_manifest_warning "$warning" "$source_root"; then
            allowed_ordinary_warnings+=("$warning")
            continue
        fi

        case "$warning" in
            /Applications/*|/Library/Developer/*|/usr/*|ld:\ warning:\ *|clang:\ warning:\ *)
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
                unclassified_warnings+=("$warning")
                ;;
        esac
    done < <(printf '%s\n' "$warning_headers")

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
    print_section \
        "SWIFTQL_STRICT_CONCURRENCY_UNCLASSIFIED_WARNINGS" \
        "${unclassified_warnings[@]}"
    set -u

    if [[ "${#unexpected_first_party_warnings[@]}" -ne 0 ]] || \
        [[ "${#unclassified_warnings[@]}" -ne 0 ]]; then
        printf '%s\n' \
            "error: complete strict-concurrency checking emitted blocking warnings" \
            >&2
        return 1
    fi

    printf '%s\n' "SWIFTQL_STRICT_CONCURRENCY_STATUS clean"
}

run_classifier_self_test() {
    local source_root="$1"
    local manifest_fixture
    local self_test_log
    local self_test_output

    self_test_log="$(mktemp "${TMPDIR:-/tmp}/swiftql-strict-concurrency-self-test.XXXXXX")"
    printf '%s\n' \
        '<unknown>:0: warning: TODO: simulated unrecognized compiler diagnostic' \
        > "$self_test_log"

    if self_test_output="$(classify_build_log "$self_test_log" "$source_root" 2>&1)"; then
        rm -f "$self_test_log"
        printf '%s\n' \
            "error: strict-concurrency classifier self-test accepted an unclassified warning" \
            >&2
        return 1
    fi
    if ! grep -q \
        'SWIFTQL_STRICT_CONCURRENCY_UNCLASSIFIED_WARNINGS' \
        <<< "$self_test_output"; then
        rm -f "$self_test_log"
        printf '%s\n' \
            "error: strict-concurrency classifier self-test did not classify its fixture" \
            >&2
        return 1
    fi

    manifest_fixture="warning: 'swiftql': /tool/swift-frontend"
    manifest_fixture+=" -primary-file $source_root/Package.swift"
    manifest_fixture+=" -package-description-version 5.9.0 -module-name main -o /tmp/Package.o"
    printf '%s\n' "$manifest_fixture" > "$self_test_log"
    if ! self_test_output="$(classify_build_log "$self_test_log" "$source_root" 2>&1)"; then
        rm -f "$self_test_log"
        printf '%s\n' \
            "error: strict-concurrency classifier self-test rejected the known package-manifest diagnostic" \
            >&2
        return 1
    fi
    rm -f "$self_test_log"

    if ! grep -q 'SWIFTQL_STRICT_CONCURRENCY_STATUS clean' \
        <<< "$self_test_output" || \
        ! grep -Fq "warning: 'swiftql':" <<< "$self_test_output"; then
        printf '%s\n' \
            "error: strict-concurrency classifier self-test did not accept its known fixture" \
            >&2
        return 1
    fi
}

main() {
    local build_log
    local source_root

    if [[ "$#" -gt 1 ]]; then
        printf 'usage: %s [BUILD_LOG]\n' "$0" >&2
        return 64
    fi

    build_log="${1:-${TMPDIR:-/tmp}/swiftql-strict-concurrency.log}"
    source_root="$(pwd -P)"

    run_classifier_self_test "$source_root"

    # A clean build prevents an incremental no-op from hiding diagnostics.
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

    classify_build_log "$build_log" "$source_root"
}

main "$@"
