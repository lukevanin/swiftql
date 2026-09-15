#!/usr/bin/env bash
#
# Record SwiftQL's performance baselines at one revision into new dated files.
#
# Records three pieces of evidence (issue #670):
#
#   1. the phase harness: three independent release processes of
#      `swiftql-benchmark` with 50 warmups and 500 samples;
#   2. the cross-library comparison (Benchmarks/Comparison/run.py); and
#   3. the consumer compile-time matrix (Benchmarks/CompileTime/run.py).
#
# Every file is new. The script refuses to overwrite an existing baseline, so
# earlier recordings stay in the repository.
#
# Each harness records whether the checkout is clean when it starts, and an
# output file inside the checkout makes it dirty. The phase harness and the
# compile-time matrix therefore write to a stage outside the checkout; both
# reports use only paths inside their own directory, so they stay valid when
# they are copied in. The comparison runs last and writes directly to its final
# directory, because its report refers to the checked-in Northwind fixture by
# a path relative to the report, which a copy would break. The staged files
# are copied into the repository only after every selected step has passed its
# own validator.
#
# Record on an otherwise idle host, from a clean checkout of the revision.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Benchmarks/record-baselines.sh --revision REV [options]

Required:
  --revision REV           Commit to record. HEAD must be this commit.

Options:
  --date YYYY-MM-DD        Date in the file names (default: today, UTC).
  --machine LABEL          Machine label in the file names
                           (default: hw.model, lowercase, "," -> "-").
  --compile-time-matrix M  Compile-time matrix preset (default: extended).
  --compile-time-repetitions N
                           Build processes per compile-time cell (default: 3).
  --skip-phase             Do not record the phase harness.
  --skip-comparison        Do not record the cross-library comparison.
  --skip-compile-time      Do not record the compile-time matrix.
  --stage DIRECTORY        Empty directory for staged output
                           (default: a new temporary directory).
  --dry-run                Print the plan and every command; run nothing.
  -h, --help               Show this help.

Output (DATE and MACHINE from the options above):
  Benchmarks/Baselines/DATE-MACHINE-run-{1,2,3}.json
  Benchmarks/Comparison/Recordings/DATE-MACHINE/comparison-results.json (+ Runs/)
  Benchmarks/CompileTime/Recordings/DATE-MACHINE/compile-time-results.json (+ Runs/)
USAGE
}

revision=""
record_date="$(date -u +%F)"
machine=""
compile_time_matrix="extended"
compile_time_repetitions=3
record_phase=1
record_comparison=1
record_compile_time=1
stage=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revision) revision="${2:?--revision needs a value}"; shift 2 ;;
    --date) record_date="${2:?--date needs a value}"; shift 2 ;;
    --machine) machine="${2:?--machine needs a value}"; shift 2 ;;
    --compile-time-matrix) compile_time_matrix="${2:?--compile-time-matrix needs a value}"; shift 2 ;;
    --compile-time-repetitions) compile_time_repetitions="${2:?--compile-time-repetitions needs a value}"; shift 2 ;;
    --skip-phase) record_phase=0; shift ;;
    --skip-comparison) record_comparison=0; shift ;;
    --skip-compile-time) record_compile_time=0; shift ;;
    --stage) stage="${2:?--stage needs a value}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -n "$revision" ]] || { usage >&2; fail "--revision is required"; }
[[ "$record_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "--date must be YYYY-MM-DD: $record_date"
[[ "$compile_time_repetitions" =~ ^[1-9][0-9]*$ ]] || fail "--compile-time-repetitions must be a positive integer"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ -z "$machine" ]]; then
  model="$(sysctl -n hw.model 2>/dev/null || uname -m)"
  machine="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]' | tr ',' '-')"
fi
[[ "$machine" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || fail "--machine must be a lowercase file-name label: $machine"

expected_commit="$(git rev-parse --verify "${revision}^{commit}")" || fail "unknown revision: $revision"
head_commit="$(git rev-parse HEAD)"
[[ "$head_commit" == "$expected_commit" ]] ||
  fail "HEAD is $head_commit, not $expected_commit; check out the revision first"

if [[ "$dry_run" -eq 0 && -n "$(git status --porcelain=v1 --untracked-files=normal)" ]]; then
  fail "the checkout has uncommitted or untracked changes; record from a clean checkout"
fi

stem="${record_date}-${machine}"
phase_targets=()
for run in 1 2 3; do
  phase_targets+=("Benchmarks/Baselines/${stem}-run-${run}.json")
done
comparison_target="Benchmarks/Comparison/Recordings/${stem}"
compile_time_target="Benchmarks/CompileTime/Recordings/${stem}"

if [[ "$record_phase" -eq 1 ]]; then
  for target in "${phase_targets[@]}"; do
    [[ ! -e "$target" ]] || fail "refusing to overwrite $target"
  done
fi
if [[ "$record_comparison" -eq 1 && -e "$comparison_target" ]]; then
  fail "refusing to overwrite $comparison_target"
fi
if [[ "$record_compile_time" -eq 1 && -e "$compile_time_target" ]]; then
  fail "refusing to overwrite $compile_time_target"
fi

if [[ -z "$stage" ]]; then
  if [[ "$dry_run" -eq 1 ]]; then
    stage="<temporary directory>"
  else
    stage="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-baselines.XXXXXX")"
  fi
elif [[ "$dry_run" -eq 0 ]]; then
  mkdir -p "$stage"
  [[ -z "$(ls -A "$stage")" ]] || fail "--stage must be empty: $stage"
  stage="$(cd "$stage" && pwd)"
fi
case "$stage/" in
  "$root"/*) fail "--stage must be outside the checkout: $stage" ;;
esac

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$dry_run" -eq 0 ]]; then
    "$@"
  fi
}

echo "SwiftQL baseline recording"
echo "  revision:     $expected_commit"
echo "  date/machine: $stem"
echo "  stage:        $stage"
echo

if [[ "$record_phase" -eq 1 ]]; then
  echo "== Phase harness (3 release processes, 50 warmups, 500 samples) =="
  run swift build -c release --product swiftql-benchmark
  for run_index in 1 2 3; do
    run swift run -c release --skip-build swiftql-benchmark \
      --warmups 50 \
      --samples 500 \
      --output "$stage/Baselines/${stem}-run-${run_index}.json"
  done
  echo
fi

if [[ "$record_compile_time" -eq 1 ]]; then
  echo "== Compile-time matrix ($compile_time_matrix) =="
  run python3 Benchmarks/CompileTime/run.py \
    --workspace "$stage/workspaces/compile-time" \
    --swiftql-checkout "$root" \
    --matrix "$compile_time_matrix" \
    --repetitions "$compile_time_repetitions" \
    --output "$stage/CompileTime/${stem}/compile-time-results.json"
  # Exits non-zero when any sample's wall time is inconsistent with its log.
  run python3 Benchmarks/CompileTime/summarize.py \
    "$stage/CompileTime/${stem}/compile-time-results.json"
  echo
fi

if [[ "$record_comparison" -eq 1 ]]; then
  # Last, and directly into the repository: see the comment at the top.
  echo "== Cross-library comparison =="
  run mkdir -p Benchmarks/Comparison/Recordings
  run python3 Benchmarks/Comparison/run.py \
    --workspace "$stage/workspaces/comparison" \
    --swiftql-checkout "$root" \
    --output "$comparison_target/comparison-results.json" \
    --cooldown-seconds 180
  run python3 Benchmarks/Comparison/summarize.py \
    "$comparison_target/comparison-results.json"
  echo
fi

echo "== Copy staged files into the repository =="
if [[ "$record_phase" -eq 1 ]]; then
  for run_index in 1 2 3; do
    run cp -n "$stage/Baselines/${stem}-run-${run_index}.json" \
      "Benchmarks/Baselines/${stem}-run-${run_index}.json"
  done
fi
if [[ "$record_compile_time" -eq 1 ]]; then
  run mkdir -p Benchmarks/CompileTime/Recordings
  run cp -R "$stage/CompileTime/${stem}" "$compile_time_target"
fi

cat <<EOF

Done. Next:
  1. Run the Swift benchmark tests and the Python harness tests.
  2. Fill in the "Current baseline" section of BENCHMARKS.md with
     revision $expected_commit and date $record_date.
  3. Commit the new files. Keep every earlier baseline file.
EOF
