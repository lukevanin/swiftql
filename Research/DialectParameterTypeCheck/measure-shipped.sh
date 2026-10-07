#!/bin/bash

# Measures what the type checker spends on the same query bodies against two
# or more builds of SwiftQL, such as the base branch and a branch that changes
# the query surface (issue #789). `measure.sh` measures stand-in surfaces; this
# script measures the shipped one.
#
# Usage:
#   Research/DialectParameterTypeCheck/measure-shipped.sh \
#       <label>=<package-root> [<label>=<package-root> ...]
#
# Each package root must already be built (`swift build --target SwiftQL`).
# REPETITIONS sets the number of runs per body (default 15). The work
# directory is a new temporary directory; nothing is written into the
# repository.
#
# For every body the script reports the median time of the function body from
# `-debug-time-function-bodies`. The roots are interleaved inside each
# repetition, so drift across the run falls on all of them alike. For the
# bodies that hold a mistake it reports the wall time of the compile and the
# first error instead, because the error path is where the type checker can
# spend the longest.

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-shipped-gate.XXXXXX")"
repetitions="${REPETITIONS:-15}"

labels=()
roots=()
for argument in "$@"; do
    labels+=("${argument%%=*}")
    roots+=("$(cd "${argument#*=}" && pwd -P)")
done
if [[ "${#labels[@]}" -lt 1 ]]; then
    printf 'usage: %s <label>=<package-root> ...\n' "$0" >&2
    exit 2
fi

python3 "$script_directory/generate_shipped.py" "$work/generated"

builds=()
plugins=()
for root in "${roots[@]}"; do
    # SwiftPM's binary directory depends on the toolchain and build system,
    # so ask for it rather than assume `.build/debug`. SwiftPM 5.9 names the
    # macro executable `SQLMacros-tool`; newer toolchains name it after the
    # target.
    build="$(swift build --package-path "$root" --show-bin-path)"
    plugin="$(
        find "$build" -maxdepth 1 -type f \
            \( -name 'SQLMacros-tool' -o -name 'SQLMacros' \) -perm -u+x -print |
            head -n 1
    )"
    if [[ -z "$plugin" ]]; then
        printf 'error: no SQLMacros plugin in %s; build the package first\n' "$build" >&2
        exit 1
    fi
    builds+=("$build")
    plugins+=("$plugin")
done

compile() {
    local index="$1"
    shift
    local root="${roots[$index]}"
    swiftc -swift-version 6 -typecheck \
        -I "${builds[$index]}" \
        -I "$root/.build/checkouts/GRDB.swift/Sources/GRDBSQLite" \
        -load-plugin-executable "${plugins[$index]}#SQLMacros" \
        "$@"
}

printf '== type-check time of one query body (median of %s) ==\n' "$repetitions"
: >"$work/raw.txt"
for _ in $(seq 1 "$repetitions"); do
    for body in clauses-30 clauses-120 clauses-450 chain-2 chain-4 chain-6 chain-8 chain-12 chain-16; do
        for index in "${!labels[@]}"; do
            if ! diagnostics="$(
                compile "$index" -Xfrontend -debug-time-function-bodies \
                    "$work/generated/$body.swift" 2>&1
            )"; then
                printf 'error: %s did not type-check against %s\n' "$body" "${labels[$index]}" >&2
                printf '%s\n' "$diagnostics" >&2
                exit 1
            fi
            milliseconds="$(
                printf '%s\n' "$diagnostics" | awk '/gateQuery/ { print $1; exit }'
            )"
            printf '%s %s %s\n' "${labels[$index]}" "$body" "${milliseconds%ms}" >>"$work/raw.txt"
        done
    done
done
python3 - "$work/raw.txt" "${labels[@]}" <<'EOF'
import statistics
import sys
from collections import defaultdict

raw, labels = sys.argv[1], sys.argv[2:]
samples = defaultdict(list)
bodies = []
for line in open(raw):
    label, body, value = line.split()
    samples[(label, body)].append(float(value))
    if body not in bodies:
        bodies.append(body)
print("| body | " + " | ".join(labels) + " |")
print("| --- |" + " ---: |" * len(labels))
for body in bodies:
    base = statistics.median(samples[(labels[0], body)])
    cells = []
    for label in labels:
        median = statistics.median(samples[(label, body)])
        if label == labels[0]:
            cells.append(f"{median:.1f} ms")
        else:
            cells.append(f"{median:.1f} ms ({(median - base) / base * 100:+.0f} %)")
    print(f"| {body} | " + " | ".join(cells) + " |")
EOF

printf '\n== a mistake in the last term of one && chain (wall time, first error) ==\n'
for kind in misspelled wrong-type; do
    for count in 2 4 6 8 12 16; do
        body="chain-$kind-$count"
        for index in "${!labels[@]}"; do
            start="$(python3 -c 'import time; print(time.time())')"
            message="$(
                compile "$index" "$work/generated/$body.swift" 2>&1 |
                    awk '/: error: / { sub(/.*: error: /, ""); print; exit }' || true
            )"
            end="$(python3 -c 'import time; print(time.time())')"
            printf '%-24s %-10s %5.1f s  %s\n' "$body" "${labels[$index]}" \
                "$(python3 -c "print($end - $start)")" "${message:-ACCEPTED}"
        done
    done
done

printf '\nwork directory: %s\n' "$work"
