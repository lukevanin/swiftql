#!/bin/bash

# Measures what a dialect type parameter costs the Swift type checker, and
# shows what it buys. See ../DialectParameterTypeCheckCost.md for the recorded
# result and the method.
#
# Usage: Research/DialectParameterTypeCheck/measure.sh [work-directory]
#
# The work directory defaults to a fresh temporary directory. Nothing is
# written inside the repository.

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
source_root="$(cd "$script_directory/../.." && pwd -P)"
work="${1:-$(mktemp -d "${TMPDIR:-/tmp}/swiftql-dialect-gate.XXXXXX")}"

mkdir -p "$work/generated" "$work/build"

python3 "$script_directory/generate.py" "$source_root" "$work"
python3 "$script_directory/fixtures.py" "$work"

kinds=(current existential concrete wrapper)
modules=(GateCurrent GateExistential GateConcrete GateWrapper)

for index in "${!kinds[@]}"; do
    swiftc -swift-version 6 \
        -emit-module \
        -emit-module-path "$work/build/${modules[$index]}.swiftmodule" \
        -module-name "${modules[$index]}" \
        "$work/generated/${kinds[$index]}-surface.swift"
done

printf '\n== type-check time of one query body ==\n'
: >"$work/raw.txt"
# The repetition is the outer loop, so the surfaces are interleaved. Drift
# across the run, such as thermal throttling, then falls on all four alike
# instead of on whichever one ran last.
for _ in $(seq 1 15); do
    for clauses in 30 120 450; do
        for kind in "${kinds[@]}"; do
            query="$work/generated/$kind-query-$clauses.swift"
            if ! diagnostics="$(
                swiftc -swift-version 6 -typecheck -I "$work/build" \
                    -Xfrontend -debug-time-function-bodies "$query" 2>&1
            )"; then
                printf 'error: %s did not type-check\n' "$query" >&2
                printf '%s\n' "$diagnostics" >&2
                exit 1
            fi
            milliseconds="$(
                printf '%s\n' "$diagnostics" |
                    awk '/gateQuery/ { print $1; exit }'
            )"
            if [[ -z "$milliseconds" ]]; then
                printf 'error: no timing for %s\n' "$query" >&2
                exit 1
            fi
            printf '%s %s %s\n' "$kind" "$clauses" "$milliseconds" \
                >>"$work/raw.txt"
        done
    done
done
python3 "$script_directory/report.py" "$work/raw.txt"

printf '\n== a SQLite-only operation on each query ==\n'
for kind in "${kinds[@]}"; do
    for fixture in collate-sqlite-column collate-sqlite-composed \
        collate-postgresql-column collate-postgresql-composed \
        mixed-dialect-comparison; do
        fixture_path="$work/generated/$kind-refusal-$fixture.swift"
        if [[ ! -f "$fixture_path" ]]; then
            printf '%s/%s: NOT EXPRESSIBLE\n' "$kind" "$fixture"
            continue
        fi
        if diagnostic="$(
            swiftc -swift-version 6 -typecheck -I "$work/build" \
                "$fixture_path" 2>&1
        )"; then
            printf '%s/%s: ACCEPTED\n' "$kind" "$fixture"
            continue
        fi
        message="$(
            printf '%s\n' "$diagnostic" |
                awk -F'error: ' '/: error: /{ print $2; exit }'
        )"
        # A compile failure is only a refusal when the compiler names the two
        # dialects. Any other failure is a fault in the harness, and saying
        # REFUSED would read as evidence the parameter did not earn.
        if [[ "$message" == *XLGateSQLite* ]] &&
            [[ "$message" == *XLGatePostgreSQL* ]]; then
            printf '%s/%s: REFUSED -- %s\n' "$kind" "$fixture" "$message"
        else
            printf '%s/%s: HARNESS FAULT -- %s\n' "$kind" "$fixture" "$message"
        fi
    done
done

printf '\n== an ordinary mistake in the query body ==\n'
for fixture in mistake-type-mismatch mistake-misspelled-column \
    mistake-mismatched-columns; do
    printf '%s\n' "$fixture"
    for kind in "${kinds[@]}"; do
        if diagnostics="$(
            swiftc -swift-version 6 -typecheck -I "$work/build" \
                "$work/generated/$kind-$fixture.swift" 2>&1
        )"; then
            printf '  %-12s %s\n' "$kind" "ACCEPTED -- the surface does not catch it"
            continue
        fi
        message="$(
            printf '%s\n' "$diagnostics" |
                awk -v name="$kind-$fixture.swift:" '
                    index($0, name) && /: error: / {
                        print substr($0, index($0, name) + length(name))
                        exit
                    }'
        )"
        printf '  %-12s %s\n' "$kind" "${message:-UNPARSED -- see the work directory}"
    done
done

printf '\nwork directory: %s\n' "$work"
