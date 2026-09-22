#!/bin/bash

# Issue #771. `Int` and `Double` conform to `XLExpression`, so a plain number
# also matches SwiftQL's generic prefix `-`, `+`, and `~`. Swift 6.3 picked the
# SwiftQL operator for such an operand, and ordinary client code stopped
# compiling. `Tests/SQLTests/SQLNumericPrefixOperatorTests.swift` covers the
# same rule inside the package. This gate compiles a file outside the package
# against the built module, which is the shape the report described.

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$script_directory/../.." && pwd -P)"
positive_fixture="$source_root/Tests/CompileFail/NumericPrefixOperatorValid.swift"
scratch_path="${SWIFTQL_SCRATCH_PATH:-$source_root/.build}"

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

"${compiler[@]}" "$positive_fixture"

printf 'SWIFTQL_NUMERIC_PREFIX_OPERATOR_TYPE_SAFETY PASS\n'
