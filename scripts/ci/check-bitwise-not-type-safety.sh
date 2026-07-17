#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$script_directory/../.." && pwd -P)"
positive_fixture="$source_root/Tests/CompileFail/BitwiseNotInteger.swift"
negative_fixture="$source_root/Tests/CompileFail/BitwiseNotDouble.swift"
diagnostic_log="$(
    mktemp "${TMPDIR:-/tmp}/swiftql-bitwise-not-type-safety.XXXXXX"
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

# Prove that the standalone compiler invocation and valid integer overloads work
# before interpreting a failure from the negative fixture as API evidence.
"${compiler[@]}" "$positive_fixture"

if "${compiler[@]}" "$negative_fixture" >"$diagnostic_log" 2>&1; then
    printf 'error: Double-valued SQL expression unexpectedly accepted prefix ~\n' >&2
    exit 1
fi

expected_line="$(
    awk '/expected-error/ { print NR; exit }' "$negative_fixture"
)"
if [[ -z "$expected_line" ]] || \
    ! grep -F "$negative_fixture:$expected_line:" "$diagnostic_log" >/dev/null; then
    printf 'error: negative fixture did not fail at its expected-error line\n' >&2
    cat "$diagnostic_log" >&2
    exit 1
fi

cat "$diagnostic_log"
printf 'SWIFTQL_BITWISE_NOT_TYPE_SAFETY PASS\n'
