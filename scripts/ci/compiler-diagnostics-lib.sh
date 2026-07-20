#!/bin/bash

# Shared warning classification for SwiftPM CI checks. Callers are expected to
# enable their own shell options before sourcing this file.

swiftql_print_diagnostic_section() {
    local heading="$1"
    shift

    printf '%s\n' "$heading"
    if [[ "$#" -eq 0 ]]; then
        printf '%s\n' "<none>"
    else
        printf '%s\n' "$@"
    fi
}

swiftql_is_root_manifest_build_warning() {
    local warning="$1"
    local source_root="$2"
    local package_identity="${source_root##*/}"

    [[ "$warning" == "warning: '$package_identity': "* ]] && \
        [[ "$warning" == *" -primary-file $source_root/Package.swift "* ]] && \
        [[ "$warning" == *" -package-description-version 5.9.0 "* ]] && \
        [[ "$warning" == *" -module-name main "* ]]
}

swiftql_diagnostic_source_path() {
    local diagnostic="$1"
    local location_pattern
    local source_path

    # Compiler locations use PATH:LINE[:COLUMN]: warning/note. Keep location
    # extraction separate from the diagnostic message so a path mentioned by
    # the message cannot change provenance. SwiftPM's CI paths do not contain
    # `:`.
    location_pattern='^([^:]+):[0-9]+(:[0-9]+)?:[[:space:]]+(warning|note):'
    if [[ ! "$diagnostic" =~ $location_pattern ]]; then
        return 1
    fi

    source_path="${BASH_REMATCH[1]}"
    case "$source_path" in
        /*|Sources/*|Tests/*|Benchmarks/*|Research/*|Package.swift)
            ;;
        *" /"*)
            # Macro-origin notes are rendered with a tree prefix before the
            # absolute source path.
            source_path="/${source_path#*/}"
            ;;
        *)
            return 1
            ;;
    esac

    printf '%s\n' "$source_path"
}

swiftql_is_dependency_warning() {
    local warning="$1"
    local source_root="$2"
    local scratch_root="$3"
    local source_path

    if source_path="$(swiftql_diagnostic_source_path "$warning")"; then
        case "$source_path" in
            "$scratch_root"/checkouts/*|"$source_root"/.build/checkouts/*|\
            */SourcePackages/checkouts/*|*/.build/checkouts/*)
                return 0
                ;;
        esac
    else
        if [[ "$warning" == *" -primary-file $scratch_root/checkouts/"* ]] || \
            [[ "$warning" == *" -primary-file $source_root/.build/checkouts/"* ]]; then
            return 0
        fi
        case "$warning" in
            "warning: 'grdb.swift':"*|"warning: 'swift-syntax':"*|\
            "warning: 'swift-docc-plugin':"*|\
            "warning: 'swift-docc-symbolkit':"*)
                return 0
                ;;
        esac
    fi

    return 1
}

swiftql_is_other_build_warning() {
    local warning="$1"
    local source_path

    if source_path="$(swiftql_diagnostic_source_path "$warning")"; then
        case "$source_path" in
            /Applications/*|/Library/Developer/*|/System/Library/*|/usr/*)
                return 0
                ;;
        esac
    else
        case "$warning" in
            ld:\ warning:\ *|clang:\ warning:\ *|swiftc:\ warning:\ *)
                return 0
                ;;
        esac
    fi

    return 1
}

swiftql_is_first_party_warning() {
    local warning="$1"
    local source_root="$2"
    local source_path

    if ! source_path="$(swiftql_diagnostic_source_path "$warning")"; then
        return 1
    fi

    case "$source_path" in
        "$source_root"/Sources/*|"$source_root"/Tests/*|\
        "$source_root"/Benchmarks/*|"$source_root"/Research/*|\
        "$source_root"/Package.swift|Sources/*|Tests/*|Benchmarks/*|\
        Research/*|Package.swift)
            return 0
            ;;
    esac

    return 1
}

swiftql_is_first_party_macro_origin() {
    local origin_note="$1"
    local source_root="$2"
    local source_path

    if ! source_path="$(swiftql_diagnostic_source_path "$origin_note")"; then
        return 1
    fi

    case "$source_path" in
        "$source_root"/Sources/*|"$source_root"/Tests/*|\
        "$source_root"/Benchmarks/*|"$source_root"/Research/*)
            return 0
            ;;
    esac

    return 1
}

swiftql_warning_records() {
    local build_log="$1"

    awk '
        function is_warning_header(line) {
            return line ~ /^[^[:space:]].*:[0-9]+(:[0-9]+)?: warning:/ ||
                line ~ /^macro expansion .*: warning:/ ||
                line ~ /^warning: / ||
                line ~ /^[^[:space:]][^:]*: warning: /
        }

        function is_source_excerpt(line) {
            return line ~ /^[[:space:]]*[0-9]+[[:space:]]*\|/ ||
                line ~ /^[[:space:]]*\|/
        }

        function is_unknown_warning_header(line) {
            return line ~ /^[^[:space:]].*warning:/ &&
                !is_source_excerpt(line)
        }

        function emit_record() {
            if (header != "") {
                print header "\t" origin
            }
        }

        {
            if (is_warning_header($0)) {
                emit_record()
                header = $0
                origin = ""
                is_macro = $0 ~ /^macro expansion .*: warning:/
                next
            }

            if (is_unknown_warning_header($0)) {
                emit_record()
                header = $0
                origin = ""
                is_macro = 0
                next
            }

            if (is_macro && origin == "" &&
                $0 ~ /: note: expanded code originates here[[:space:]]*$/) {
                origin = $0
            }
        }

        END {
            emit_record()
        }
    ' "$build_log" | awk '!seen[$0]++'
}

swiftql_classify_build_log() {
    local build_log="$1"
    local source_root="$2"
    local scratch_root="$3"
    local output_prefix="$4"
    local failure_message="$5"
    local warning_records
    local warning
    local origin_note
    local classified_warning
    local -a dependency_warnings=()
    local -a other_build_warnings=()
    local -a first_party_warnings=()
    local -a unclassified_warnings=()

    if [[ ! -f "$build_log" ]]; then
        printf 'error: compiler diagnostic log does not exist: %s\n' \
            "$build_log" >&2
        return 1
    fi

    warning_records="$(swiftql_warning_records "$build_log")"

    while IFS=$'\t' read -r warning origin_note; do
        [[ -z "$warning" ]] && continue

        classified_warning="$warning"
        if [[ -n "$origin_note" ]]; then
            classified_warning+=" [expanded-code origin: $origin_note]"
        fi

        case "$warning" in
            macro\ expansion\ *)
                if [[ -z "$origin_note" ]]; then
                    unclassified_warnings+=("$classified_warning")
                elif swiftql_is_first_party_macro_origin \
                    "$origin_note" "$source_root"; then
                    first_party_warnings+=("$classified_warning")
                elif swiftql_is_dependency_warning \
                    "$origin_note" "$source_root" "$scratch_root"; then
                    dependency_warnings+=("$classified_warning")
                else
                    unclassified_warnings+=("$classified_warning")
                fi
                continue
                ;;
        esac

        if swiftql_is_root_manifest_build_warning \
            "$warning" "$source_root"; then
            other_build_warnings+=("$classified_warning")
        elif swiftql_is_first_party_warning "$warning" "$source_root"; then
            first_party_warnings+=("$classified_warning")
        elif swiftql_is_dependency_warning \
            "$warning" "$source_root" "$scratch_root"; then
            dependency_warnings+=("$classified_warning")
        elif swiftql_is_other_build_warning "$warning"; then
            other_build_warnings+=("$classified_warning")
        else
            unclassified_warnings+=("$classified_warning")
        fi
    done < <(printf '%s\n' "$warning_records")

    # Bash 3.2 treats an empty array expansion as unset under `set -u`.
    set +u
    swiftql_print_diagnostic_section \
        "${output_prefix}_FIRST_PARTY_WARNINGS" \
        "${first_party_warnings[@]}"
    swiftql_print_diagnostic_section \
        "${output_prefix}_DEPENDENCY_WARNINGS" \
        "${dependency_warnings[@]}"
    swiftql_print_diagnostic_section \
        "${output_prefix}_OTHER_BUILD_WARNINGS" \
        "${other_build_warnings[@]}"
    swiftql_print_diagnostic_section \
        "${output_prefix}_UNCLASSIFIED_WARNINGS" \
        "${unclassified_warnings[@]}"
    set -u

    if [[ "${#first_party_warnings[@]}" -ne 0 ]] || \
        [[ "${#unclassified_warnings[@]}" -ne 0 ]]; then
        printf 'error: %s\n' "$failure_message" >&2
        return 1
    fi

    printf '%s\n' "${output_prefix}_STATUS clean"
}

swiftql_diagnostic_section_contains() {
    local output="$1"
    local output_prefix="$2"
    local expected_section="$3"
    local expected_output="$4"

    printf '%s\n' "$output" | awk \
        -v target="${output_prefix}_${expected_section}" \
        -v first_party="${output_prefix}_FIRST_PARTY_WARNINGS" \
        -v dependency="${output_prefix}_DEPENDENCY_WARNINGS" \
        -v other_build="${output_prefix}_OTHER_BUILD_WARNINGS" \
        -v unclassified="${output_prefix}_UNCLASSIFIED_WARNINGS" \
        -v status="${output_prefix}_STATUS clean" \
        -v expected="$expected_output" '
            $0 == first_party || $0 == dependency ||
                $0 == other_build || $0 == unclassified || $0 == status {
                inside = ($0 == target)
                next
            }

            inside && index($0, expected) != 0 {
                found = 1
            }

            END {
                exit found ? 0 : 1
            }
        '
}

swiftql_self_test_rejected_warning() {
    local self_test_log="$1"
    local source_root="$2"
    local scratch_root="$3"
    local output_prefix="$4"
    local fixture="$5"
    local expected_section="$6"
    local description="$7"
    local expected_output="${8:-$fixture}"
    local output

    printf '%s\n' "$fixture" > "$self_test_log"
    if output="$(
        swiftql_classify_build_log \
            "$self_test_log" \
            "$source_root" \
            "$scratch_root" \
            "$output_prefix" \
            "simulated classifier failure" 2>&1
    )"; then
        printf 'error: diagnostic classifier self-test accepted %s\n' \
            "$description" >&2
        return 1
    fi

    if ! swiftql_diagnostic_section_contains \
        "$output" "$output_prefix" "$expected_section" "$expected_output"; then
        printf 'error: diagnostic classifier self-test did not classify %s\n' \
            "$description" >&2
        return 1
    fi
}

swiftql_self_test_accepted_warning() {
    local self_test_log="$1"
    local source_root="$2"
    local scratch_root="$3"
    local output_prefix="$4"
    local fixture="$5"
    local expected_section="$6"
    local description="$7"
    local expected_output="${8:-$fixture}"
    local output

    printf '%s\n' "$fixture" > "$self_test_log"
    if ! output="$(
        swiftql_classify_build_log \
            "$self_test_log" \
            "$source_root" \
            "$scratch_root" \
            "$output_prefix" \
            "simulated classifier failure" 2>&1
    )"; then
        printf 'error: diagnostic classifier self-test rejected %s\n' \
            "$description" >&2
        return 1
    fi

    if ! swiftql_diagnostic_section_contains \
        "$output" "$output_prefix" "$expected_section" "$expected_output" || \
        ! grep -Fq "${output_prefix}_STATUS clean" <<< "$output"; then
        printf 'error: diagnostic classifier self-test did not classify %s\n' \
            "$description" >&2
        return 1
    fi
}

swiftql_run_diagnostic_classifier_self_tests() {
    local source_root="$1"
    local scratch_root="$2"
    local output_prefix="$3"
    local package_identity="${source_root##*/}"
    local self_test_log
    local fixture
    local macro_header
    local macro_origin
    local system_prefix_source_root

    self_test_log="$(
        mktemp "${TMPDIR:-/tmp}/swiftql-diagnostic-classifier-self-test.XXXXXX"
    )"

    fixture="$source_root/Sources/SwiftQL/Fixture.swift:1:1: warning: simulated first-party diagnostic"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "FIRST_PARTY_WARNINGS" "a first-party warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="$source_root/Research/Fixture/Sources/Fixture.swift:1:1: warning: simulated research-target diagnostic"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "FIRST_PARTY_WARNINGS" \
        "a first-party research-target warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="$source_root/Sources/SwiftQL/Fixture.swift:1:1: warning: referenced $scratch_root/checkouts/Dependency"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "FIRST_PARTY_WARNINGS" \
        "a first-party warning whose message mentions a dependency path"; then
        rm -f "$self_test_log"
        return 1
    fi

    system_prefix_source_root="/usr/local/src/swiftql-classifier-self-test"
    fixture="$system_prefix_source_root/Sources/SwiftQL/Fixture.swift:1:1: warning: simulated first-party diagnostic"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" \
        "$system_prefix_source_root" \
        "$system_prefix_source_root/.build" \
        "$output_prefix" \
        "$fixture" \
        "FIRST_PARTY_WARNINGS" \
        "a first-party warning below a system-path prefix"; then
        rm -f "$self_test_log"
        return 1
    fi

    macro_header="macro expansion @Fixture:1:1: warning: simulated macro diagnostic"
    macro_origin="\`- $source_root/Tests/SQLTests/Fixture.swift:1:1: note: expanded code originates here"
    fixture="$macro_header"$'\n'"$macro_origin"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "FIRST_PARTY_WARNINGS" \
        "a first-party macro-expansion warning" "$macro_origin"; then
        rm -f "$self_test_log"
        return 1
    fi

    macro_origin="\`- $scratch_root/checkouts/Dependency/Sources/Fixture.swift:1:1: note: expanded code originates here"
    fixture="$macro_header"$'\n'"$macro_origin"
    if ! swiftql_self_test_accepted_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "DEPENDENCY_WARNINGS" \
        "a dependency macro-expansion warning" "$macro_origin"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="$macro_header"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "UNCLASSIFIED_WARNINGS" \
        "a macro-expansion warning without an origin note"; then
        rm -f "$self_test_log"
        return 1
    fi

    macro_origin="\`- /tmp/UnknownPackage/Sources/Fixture.swift:1:1: note: expanded code originates here"
    fixture="$macro_header"$'\n'"$macro_origin"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "UNCLASSIFIED_WARNINGS" \
        "a macro-expansion warning with an unknown origin" "$macro_origin"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="<unknown>:0: warning: simulated unclassified diagnostic"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "UNCLASSIFIED_WARNINGS" "an unclassified warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="swift-driver warning: simulated new-format diagnostic"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "UNCLASSIFIED_WARNINGS" \
        "a warning with an unknown header format"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="$scratch_root/checkouts/Dependency/Sources/Fixture.swift:1:1: warning: simulated dependency diagnostic"
    if ! swiftql_self_test_accepted_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "DEPENDENCY_WARNINGS" "a dependency warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="warning: 'opencombine': /tool/swift-frontend"
    fixture+=" -primary-file $scratch_root/checkouts/OpenCombine/Package.swift"
    fixture+=" -package-description-version 5.5.0 -module-name main -o /tmp/Package.o"
    if ! swiftql_self_test_accepted_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "DEPENDENCY_WARNINGS" \
        "a dependency-manifest build warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="warning: '$package_identity': /tool/swift-frontend"
    fixture+=" -primary-file $source_root/Package.swift"
    fixture+=" -package-description-version 5.9.0 -module-name main -o /tmp/Package.o"
    if ! swiftql_self_test_accepted_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "OTHER_BUILD_WARNINGS" \
        "the exact root-manifest build warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="warning: '$package_identity': /tool/swift-frontend"
    fixture+=" -primary-file $source_root/Package.swift"
    fixture+=" -package-description-version 6.0.0 -module-name main -o /tmp/Package.o"
    if ! swiftql_self_test_rejected_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "UNCLASSIFIED_WARNINGS" \
        "a near-match root-manifest warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="ld: warning: simulated system linker diagnostic"
    if ! swiftql_self_test_accepted_warning \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "$fixture" "OTHER_BUILD_WARNINGS" "a system warning"; then
        rm -f "$self_test_log"
        return 1
    fi

    fixture="    $source_root/Sources/SwiftQL/Fixture.swift:1:1: warning: simulated source excerpt"
    printf '%s\n' "$fixture" > "$self_test_log"
    if ! swiftql_classify_build_log \
        "$self_test_log" "$source_root" "$scratch_root" "$output_prefix" \
        "simulated classifier failure" >/dev/null; then
        rm -f "$self_test_log"
        printf '%s\n' \
            "error: diagnostic classifier self-test treated an indented source excerpt as a diagnostic header" \
            >&2
        return 1
    fi

    rm -f "$self_test_log"
}

swiftql_prepare_scratch_root() {
    local source_root="$1"
    local requested_scratch_root="$2"
    local scratch_root

    scratch_root="$requested_scratch_root"
    if [[ -z "$scratch_root" ]]; then
        scratch_root="$source_root/.build"
    elif [[ "$scratch_root" != /* ]]; then
        scratch_root="$source_root/$scratch_root"
    fi

    mkdir -p "$scratch_root"
    (cd "$scratch_root" && pwd -P)
}
