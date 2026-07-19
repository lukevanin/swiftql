#!/bin/bash

set -euo pipefail

fail() {
    printf 'error: live-query stress: %s\n' "$*" >&2
    exit 1
}

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
repository_root="$(cd "$script_directory/../.." && pwd -P)"

if [[ "$#" -ne 1 ]]; then
    printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
    exit 64
fi

iterations="${SWIFTQL_LIVE_QUERY_STRESS_ITERATIONS:-10}"
maximum_iterations=50
if [[ ! "$iterations" =~ ^[1-9][0-9]*$ ]]; then
    fail "SWIFTQL_LIVE_QUERY_STRESS_ITERATIONS must be a positive integer"
fi
if (( iterations > maximum_iterations )); then
    fail "iteration count $iterations exceeds the hard bound of $maximum_iterations"
fi

skip_build="${SWIFTQL_LIVE_QUERY_STRESS_SKIP_BUILD:-0}"
if [[ "$skip_build" != "0" && "$skip_build" != "1" ]]; then
    fail "SWIFTQL_LIVE_QUERY_STRESS_SKIP_BUILD must be 0 or 1"
fi

output_directory="$1"
mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd -P)"
if [[ -n "$(find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    fail "output directory is not clean: $output_directory"
fi

temporary_root="$(
    mktemp -d "${TMPDIR:-/tmp}/swiftql-live-query-stress.XXXXXX"
)"
trap 'rm -rf "$temporary_root"' EXIT

test_filter='XLPublisherTests|XLGRDBLiveQueryRetryTests'
source_commit="$(git -C "$repository_root" rev-parse HEAD)"
started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
summary_path="$output_directory/summary.md"
metadata_path="$output_directory/metadata.txt"

{
    printf 'source_commit=%s\n' "$source_commit"
    printf 'started_at=%s\n' "$started_at"
    printf 'planned_iterations=%s\n' "$iterations"
    printf 'maximum_iterations=%s\n' "$maximum_iterations"
    printf 'test_filter=%s\n' "$test_filter"
    printf 'skip_build=%s\n' "$skip_build"
} > "$metadata_path"

{
    printf '## Live-query repeated stress\n\n'
    printf -- '- Source commit: `%s`\n' "$source_commit"
    printf -- '- Focused filter: `%s`\n' "$test_filter"
    printf -- '- Clean test processes: %s (hard maximum %s)\n' \
        "$iterations" "$maximum_iterations"
    printf -- '- Database isolation: one private temporary root per process\n\n'
    printf '| Run | Result | Process log |\n'
    printf '| ---: | :--- | :--- |\n'
} > "$summary_path"

swift_test_arguments=(
    --filter "$test_filter"
)
if [[ "$skip_build" == "1" ]]; then
    swift_test_arguments=(
        --skip-build
        "${swift_test_arguments[@]}"
    )
fi

completed_iterations=0
cd "$repository_root"
for ((iteration = 1; iteration <= iterations; iteration += 1)); do
    run_name="run-$(printf '%02d' "$iteration")"
    run_temporary_directory="$temporary_root/$run_name"
    run_log="$output_directory/$run_name.log"
    mkdir -p "$run_temporary_directory"

    printf 'SWIFTQL_LIVE_QUERY_STRESS run=%s/%s temp=%s\n' \
        "$iteration" "$iterations" "$run_name"

    set +e
    TMPDIR="$run_temporary_directory" \
        xcrun swift test "${swift_test_arguments[@]}" 2>&1 | tee "$run_log"
    test_status="${PIPESTATUS[0]}"
    set -e

    if [[ "$test_status" -ne 0 ]]; then
        printf '| %s | FAIL (%s) | `%s.log` |\n' \
            "$iteration" "$test_status" "$run_name" >> "$summary_path"
        {
            printf '\n**Result: FAIL.** Completed %s of %s planned processes.\n' \
                "$completed_iterations" "$iterations"
        } >> "$summary_path"
        printf 'result=fail\ncompleted_iterations=%s\nfailed_iteration=%s\n' \
            "$completed_iterations" "$iteration" \
            > "$output_directory/result.txt"
        exit "$test_status"
    fi

    completed_iterations="$iteration"
    printf '| %s | PASS | `%s.log` |\n' \
        "$iteration" "$run_name" >> "$summary_path"
done

finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
    printf '\n**Result: PASS.** All %s clean processes completed.\n' \
        "$completed_iterations"
} >> "$summary_path"
{
    printf 'result=pass\n'
    printf 'completed_iterations=%s\n' "$completed_iterations"
    printf 'finished_at=%s\n' "$finished_at"
} > "$output_directory/result.txt"

printf 'SWIFTQL_LIVE_QUERY_STRESS PASS iterations=%s evidence=%s\n' \
    "$completed_iterations" "$output_directory"
