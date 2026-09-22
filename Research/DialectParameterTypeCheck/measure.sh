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

kinds=(current existential concrete)
modules=(GateCurrent GateExistential GateConcrete)

for index in 0 1 2; do
    swiftc -swift-version 6 \
        -emit-module \
        -emit-module-path "$work/build/${modules[$index]}.swiftmodule" \
        -module-name "${modules[$index]}" \
        "$work/generated/${kinds[$index]}-surface.swift"
done

printf '\n== type-check time of one query body ==\n'
: >"$work/raw.txt"
for clauses in 30 120 450; do
    for kind in "${kinds[@]}"; do
        for _ in 1 2 3 4 5 6 7; do
            milliseconds="$(
                swiftc -swift-version 6 -typecheck -I "$work/build" \
                    -Xfrontend -debug-time-function-bodies \
                    "$work/generated/$kind-query-$clauses.swift" 2>&1 |
                    awk '/gateQuery/ { print $1; exit }'
            )"
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
        if diagnostic="$(
            swiftc -swift-version 6 -typecheck -I "$work/build" \
                "$work/generated/$kind-refusal-$fixture.swift" 2>&1
        )"; then
            printf '%s/%s: ACCEPTED\n' "$kind" "$fixture"
        else
            printf '%s/%s: REFUSED -- %s\n' "$kind" "$fixture" \
                "$(printf '%s\n' "$diagnostic" |
                    awk -F'error: ' '/: error: /{ print $2; exit }')"
        fi
    done
done

printf '\n== an ordinary mistake in the query body ==\n'
for fixture in mistake-type-mismatch mistake-misspelled-column \
    mistake-mismatched-columns; do
    printf '%s\n' "$fixture"
    for kind in "${kinds[@]}"; do
        printf '  %-12s %s\n' "$kind" "$(
            swiftc -swift-version 6 -typecheck -I "$work/build" \
                "$work/generated/$kind-$fixture.swift" 2>&1 |
                awk -v name="$kind-$fixture.swift:" '
                    index($0, name) && /: error: / {
                        print substr($0, index($0, name) + length(name))
                        exit
                    }'
        )"
    done
done

printf '\nwork directory: %s\n' "$work"
