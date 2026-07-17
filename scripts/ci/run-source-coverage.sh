#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: source coverage: %s\n' "$*" >&2
    exit 1
}

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
repository_root="$(cd "$script_directory/../.." && pwd -P)"

if [[ "$#" -ne 1 ]]; then
    printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
    exit 64
fi

output_directory="$1"
scratch_path="${SWIFTQL_COVERAGE_SCRATCH_PATH:-$repository_root/.build/source-coverage}"
mkdir -p "$output_directory" "$scratch_path"
output_directory="$(cd "$output_directory" && pwd -P)"
scratch_path="$(cd "$scratch_path" && pwd -P)"

if [[ -n "$(find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    fail "output directory is not clean: $output_directory"
fi

for output in \
    llvm-coverage.json \
    llvm-coverage.lcov \
    first-party-coverage.json \
    included-sources.txt \
    allowed-uninstrumented-sources.txt \
    summary.md \
    swift-test.log \
    xcode-version.txt \
    swift-version.txt \
    sdk-version.txt \
    llvm-cov-version.txt \
    llvm-profdata-version.txt \
    platform.txt \
    architecture.txt \
    runner-image.txt \
    resolved-dependencies.txt; do
    [[ ! -e "$output_directory/$output" ]] || \
        fail "output directory is not clean: $output_directory/$output already exists"
done

cd "$repository_root"
source_commit="$(git rev-parse HEAD)"
[[ -n "$source_commit" ]] || fail "could not determine source commit"
if [[ -z "$(git status --porcelain)" ]]; then
    source_tree_state="clean"
else
    source_tree_state="dirty"
fi
if [[ "$source_tree_state" != "clean" && "${SWIFTQL_ALLOW_DIRTY_COVERAGE:-0}" != "1" ]]; then
    fail "source tree is dirty; commit the capture inputs or set SWIFTQL_ALLOW_DIRTY_COVERAGE=1 for diagnostic-only output"
fi

xcodebuild -version > "$output_directory/xcode-version.txt"
xcrun swift --version > "$output_directory/swift-version.txt"
xcrun --sdk macosx --show-sdk-version > "$output_directory/sdk-version.txt"
{
    xcrun --find llvm-cov
    xcrun llvm-cov --version
} > "$output_directory/llvm-cov-version.txt"
{
    xcrun --find llvm-profdata
    xcrun llvm-profdata --version
} > "$output_directory/llvm-profdata-version.txt"
uname -a > "$output_directory/platform.txt"
uname -m > "$output_directory/architecture.txt"
printf '%s %s\n' "${ImageOS:-local}" "${ImageVersion:-unavailable}" \
    > "$output_directory/runner-image.txt"

xcrun swift package --scratch-path "$scratch_path" resolve
git diff --exit-code -- Package.resolved
SWIFTQL_SCRATCH_PATH="$scratch_path" \
    "$script_directory/report-resolved-dependencies.sh" \
    > "$output_directory/resolved-dependencies.txt"
xcrun swift package --scratch-path "$scratch_path" clean

coverage_command='xcrun swift test --scratch-path <scratch-path> --enable-code-coverage'
xcrun swift test \
        --scratch-path "$scratch_path" \
        --enable-code-coverage \
        2>&1 | tee "$output_directory/swift-test.log"

raw_coverage_json="$(
    xcrun swift test \
        --scratch-path "$scratch_path" \
        --show-codecov-path
)"
[[ -s "$raw_coverage_json" ]] || \
    fail "SwiftPM did not produce a non-empty LLVM JSON report: $raw_coverage_json"
cp "$raw_coverage_json" "$output_directory/llvm-coverage.json"

profile_data="$(dirname "$raw_coverage_json")/default.profdata"
[[ -s "$profile_data" ]] || \
    fail "SwiftPM did not produce profile data: $profile_data"
binary_directory="$(
    xcrun swift build \
        --scratch-path "$scratch_path" \
        --show-bin-path
)"
test_binary="$binary_directory/SwiftQLPackageTests.xctest/Contents/MacOS/SwiftQLPackageTests"
[[ -x "$test_binary" ]] || fail "could not find coverage test binary: $test_binary"
xcrun llvm-cov export \
    "$test_binary" \
    -instr-profile "$profile_data" \
    -format=lcov \
    > "$output_directory/llvm-coverage.lcov"
[[ -s "$output_directory/llvm-coverage.lcov" ]] || \
    fail "llvm-cov produced an empty LCOV export"

python3 "$script_directory/source-coverage-report.py" \
    --llvm-json "$output_directory/llvm-coverage.json" \
    --repository-root "$repository_root" \
    --config "$script_directory/source-coverage-config.json" \
    --output-directory "$output_directory" \
    --source-commit "$source_commit" \
    --xcode-version "$(cat "$output_directory/xcode-version.txt")" \
    --swift-version "$(cat "$output_directory/swift-version.txt")" \
    --sdk-version "$(cat "$output_directory/sdk-version.txt")" \
    --llvm-cov-version "$(cat "$output_directory/llvm-cov-version.txt")" \
    --llvm-profdata-version "$(cat "$output_directory/llvm-profdata-version.txt")" \
    --platform "$(cat "$output_directory/platform.txt")" \
    --architecture "$(cat "$output_directory/architecture.txt")" \
    --runner-image "$(cat "$output_directory/runner-image.txt")" \
    --source-tree-state "$source_tree_state" \
    --coverage-command "$coverage_command"

printf 'SWIFTQL_SOURCE_COVERAGE %s\n' "$output_directory/first-party-coverage.json"
