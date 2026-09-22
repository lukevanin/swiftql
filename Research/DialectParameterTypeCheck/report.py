#!/usr/bin/env python3
"""Print the median type-check time of each surface as one table.

The first surface named in the raw file is the baseline. Every other surface
is also reported as a percentage of it.
"""

import collections
import statistics
import sys


def main():
    rows = collections.defaultdict(list)
    kinds = []
    with open(sys.argv[1]) as handle:
        for line in handle:
            kind, clauses, milliseconds = line.split()
            if kind not in kinds:
                kinds.append(kind)
            rows[(int(clauses), kind)].append(
                float(milliseconds.replace("ms", ""))
            )

    baseline = kinds[0]
    width = 14
    header = f"{'clauses':>8}"
    header += "".join(f"{kind:>{width}}" for kind in kinds)
    header += "".join(f"{kind + ' %':>{width}}" for kind in kinds[1:])
    print(header)
    for clauses in sorted({clauses for clauses, _ in rows}):
        medians = {
            kind: statistics.median(rows[(clauses, kind)]) for kind in kinds
        }
        line = f"{clauses:>8}"
        for kind in kinds:
            line += f"{f'{medians[kind]:.1f}ms':>{width}}"
        for kind in kinds[1:]:
            share = 100 * (medians[kind] / medians[baseline] - 1)
            line += f"{f'{share:+.1f}%':>{width}}"
        print(line)


if __name__ == "__main__":
    main()
