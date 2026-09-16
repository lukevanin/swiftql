#!/bin/bash

# Issue #663: proves that an `@SQLBindings` packet turns a misspelled binding
# name, a misspelled value label, and a missing value into compile errors, and
# that the macro rejects the two declarations that would let a missing value
# compile: a property with an initial value and a declared initializer. The
# fixtures use macros, so the standalone compiler loads SwiftQL's macro plugin.

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$script_directory/../.." && pwd -P)"
positive_fixture="$source_root/Tests/CompileFail/NamedBindingPacketValid.swift"
negative_fixtures=(
    "$source_root/Tests/CompileFail/NamedBindingPacketMisspelledReference.swift"
    "$source_root/Tests/CompileFail/NamedBindingPacketMisspelledLabel.swift"
    "$source_root/Tests/CompileFail/NamedBindingPacketMissingValue.swift"
    "$source_root/Tests/CompileFail/NamedBindingPacketInitialValue.swift"
    "$source_root/Tests/CompileFail/NamedBindingPacketCustomInitializer.swift"
)
diagnostic_log="$(
    mktemp "${TMPDIR:-/tmp}/swiftql-named-binding-packet.XXXXXX"
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

# SwiftPM 5.9 names the macro executable `SQLMacros-tool`; newer toolchains
# name it after the target.
macro_plugin="$(
    find "$bin_path" -maxdepth 1 -type f \
        \( -name 'SQLMacros-tool' -o -name 'SQLMacros' \) -perm -u+x -print |
        head -n 1
)"

if [[ -z "$swiftql_module" ]]; then
    printf 'error: could not find SwiftQL.swiftmodule below %s\n' \
        "$bin_path" >&2
    exit 1
fi
if [[ -z "$macro_plugin" ]]; then
    printf 'error: could not find the SQLMacros plugin executable in %s\n' \
        "$bin_path" >&2
    exit 1
fi
if [[ ! -f "$csqlite_module_map" ]]; then
    printf 'error: expected CSQLite module map at %s\n' \
        "$csqlite_module_map" >&2
    exit 1
fi

compiler=(
    swiftc
    -typecheck
    -swift-version 5
    -Xcc "-fmodule-map-file=$csqlite_module_map"
    -load-plugin-executable "$macro_plugin#SQLMacros"
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

# Prove that the standalone compiler invocation expands the macros and accepts
# a correct packet before interpreting failures from the negative fixtures as
# API evidence.
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
        printf 'error: invalid named-binding packet unexpectedly typechecked: %s\n' \
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

printf 'SWIFTQL_NAMED_BINDING_PACKET_TYPE_SAFETY PASS\n'
