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
swift build "${build_arguments[@]}" --target SwiftQL
bin_path="$(swift build "${build_arguments[@]}" --show-bin-path)"
grdbsqlite_module_map="$scratch_path/checkouts/GRDB.swift/Sources/GRDBSQLite/module.modulemap"

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
if [[ ! -f "$grdbsqlite_module_map" ]]; then
    printf 'error: expected GRDBSQLite module map at %s\n' \
        "$grdbsqlite_module_map" >&2
    exit 1
fi

compiler=(
    swiftc
    -typecheck
    -swift-version 5
    -Xcc "-fmodule-map-file=$grdbsqlite_module_map"
)
for module_search_path in "${module_search_paths[@]}"; do
    compiler+=(
        -I "$module_search_path"
    )
done

# Swift 6 on Linux loads every module SwiftQL depends on, including
# OpenCombine's C helper target, COpenCombineHelpers. That target has no
# checked-in module map; SwiftPM generates one in the target's build
# directory. Swift 5.9 tolerated its absence, but Swift 6.3 fails with
# "missing required module". Pass each generated C-target module map. Host
# tool copies (`*-tool.build`) would redefine the same modules, and Swift
# targets' generated maps (`-Swift.h`) are not C modules, so both are skipped.
# Apple builds link no OpenCombine (#669), so the macOS invocation is left
# unchanged.
if [[ "$(uname -s)" == Linux ]]; then
    while IFS= read -r generated_module_map; do
        if grep -Fq -- '-Swift.h' "$generated_module_map"; then
            continue
        fi
        compiler+=(-Xcc "-fmodule-map-file=$generated_module_map")
    done < <(
        find "$bin_path" -name '*-tool.build' -prune -o \
            -path '*.build/module.modulemap' -print | sort
    )
fi

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
