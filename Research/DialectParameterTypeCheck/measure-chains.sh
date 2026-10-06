#!/bin/bash

# Times one && chain of 4, 8, 12, and 16 comparisons against each stand-in
# operator shape that chain_scaling.py writes (issue #789). A shape whose time
# grows exponentially with the chain is the shape to avoid.
#
# Usage: Research/DialectParameterTypeCheck/measure-chains.sh [work-directory]
#
# A body that takes longer than TIMEOUT seconds (default 60) is reported as
# a timeout rather than waited for.

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
work="${1:-$(mktemp -d "${TMPDIR:-/tmp}/swiftql-chain-gate.XXXXXX")}"
timeout_seconds="${TIMEOUT:-60}"

python3 "$script_directory/chain_scaling.py" "$work"

printf '| shape | 4 | 8 | 12 | 16 |\n| --- | ---: | ---: | ---: | ---: |\n'
for shape in base generic mixed operands operands-ret concrete; do
    directory="$work/$shape"
    swiftc -swift-version 6 -emit-module \
        -emit-module-path "$directory/Lib.swiftmodule" -module-name Lib \
        "$directory/Lib.swift"
    row="| $shape |"
    for count in 4 8 12 16; do
        result="$(
            perl -e 'alarm shift; exec @ARGV' "$timeout_seconds" \
                swiftc -swift-version 6 -typecheck -I "$directory" \
                -Xfrontend -debug-time-function-bodies \
                "$directory/chain-$count.swift" 2>&1 |
                awk '/gateQuery/ { print $1; exit } /error:/ { print "error"; exit }' || true
        )"
        row+=" ${result:-timeout} |"
    done
    printf '%s\n' "$row"
done

printf '\nwork directory: %s\n' "$work"
