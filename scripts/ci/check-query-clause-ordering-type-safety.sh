#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$script_directory/../.." && pwd -P)"
positive_fixture="$source_root/Tests/CompileFail/QueryClauseOrderingValid.swift"
negative_fixtures=(
    "$source_root/Tests/CompileFail/HavingWithoutGroupBy.swift"
    "$source_root/Tests/CompileFail/OffsetWithoutLimit.swift"
    "$source_root/Tests/CompileFail/WhereAfterOrderBy.swift"
    "$source_root/Tests/CompileFail/WhereRequiresBoolean.swift"
)
diagnostic_log="$(
    mktemp "${TMPDIR:-/tmp}/swiftql-query-clause-ordering.XXXXXX"
)"
scratch_path="${SWIFTQL_SCRATCH_PATH:-$source_root/.build}"

trap 'rm -f "$diagnostic_log"' EXIT

if [[ "$scratch_path" != /* ]]; then
    scratch_path="$source_root/$scratch_path"
fi

build_arguments=(
    --package-path "$source_root"
    --scratch-path "$scratch_path"
)

# Make the gate independently runnable while remaining an incremental no-op
# immediately after the compatibility matrix's warning-clean build.
xcrun swift build "${build_arguments[@]}" --target SwiftQL
bin_path="$(xcrun swift build "${build_arguments[@]}" --show-bin-path)"
csqlite_module_map="$scratch_path/checkouts/GRDB.swift/Sources/CSQLite/module.modulemap"

module_search_paths=()
swiftql_module=""

# SwiftPM 5.9 writes target modules directly into the configuration's binary
# directory, while newer toolchains collect them under `Modules`. Discover every
# emitted module parent so this invocation works with either artifact layout.
while IFS= read -r module; do
    module_search_paths+=("$(dirname "$module")")
    if [[ "$(basename "$module")" == "SwiftQL.swiftmodule" ]]; then
        swiftql_module="$module"
    fi
done < <(find "$bin_path" -name '*.swiftmodule' -prune -print)

if [[ -z "$swiftql_module" ]]; then
    printf 'error: could not find SwiftQL.swiftmodule below %s\n' \
        "$bin_path" >&2
    exit 1
fi
if [[ ! -f "$csqlite_module_map" ]]; then
    printf 'error: expected CSQLite module map at %s\n' \
        "$csqlite_module_map" >&2
    exit 1
fi

compiler=(
    xcrun swiftc
    -typecheck
    -swift-version 5
    -Xcc "-fmodule-map-file=$csqlite_module_map"
)
for module_search_path in "${module_search_paths[@]}"; do
    compiler+=(
        -I "$module_search_path"
    )
done

# Prove that the standalone compiler invocation accepts each valid transition
# before interpreting failures from the negative fixtures as API evidence.
"${compiler[@]}" "$positive_fixture"

for negative_fixture in "${negative_fixtures[@]}"; do
    marker_count="$(awk '/expected-error/ { count += 1 } END { print count + 0 }' "$negative_fixture")"
    expected_line="$(awk '/expected-error/ { print NR; exit }' "$negative_fixture")"

    if [[ "$marker_count" -ne 1 ]] || [[ -z "$expected_line" ]]; then
        printf 'error: expected exactly one expected-error marker in %s\n' \
            "$negative_fixture" >&2
        exit 1
    fi

    if "${compiler[@]}" "$negative_fixture" >"$diagnostic_log" 2>&1; then
        printf 'error: invalid query clause ordering unexpectedly typechecked: %s\n' \
            "$negative_fixture" >&2
        exit 1
    fi

    diagnostic_error_lines="$(
        awk -v fixture="$negative_fixture" '
            index($0, fixture ":") == 1 && /: error:/ {
                location = substr($0, length(fixture) + 2)
                split(location, parts, ":")
                print parts[1]
            }
        ' "$diagnostic_log" | sort -u
    )"

    if [[ "$diagnostic_error_lines" != "$expected_line" ]]; then
        printf 'error: negative fixture did not fail exactly at its expected-error line: %s\n' \
            "$negative_fixture" >&2
        cat "$diagnostic_log" >&2
        exit 1
    fi

    cat "$diagnostic_log"
done

printf 'SWIFTQL_QUERY_CLAUSE_ORDERING_TYPE_SAFETY PASS\n'
