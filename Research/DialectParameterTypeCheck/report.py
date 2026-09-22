#!/usr/bin/env python3
"""Print the median type-check time of each surface as one table."""

import collections
import statistics
import sys


def main():
    rows = collections.defaultdict(list)
    with open(sys.argv[1]) as handle:
        for line in handle:
            kind, clauses, milliseconds = line.split()
            rows[(int(clauses), kind)].append(
                float(milliseconds.replace("ms", ""))
            )

    print(
        f"{'clauses':>8} {'current':>10} {'existential':>12} "
        f"{'concrete':>10} {'existential':>12} {'concrete':>9}"
    )
    for clauses in sorted({clauses for clauses, _ in rows}):
        current = statistics.median(rows[(clauses, "current")])
        existential = statistics.median(rows[(clauses, "existential")])
        concrete = statistics.median(rows[(clauses, "concrete")])
        print(
            f"{clauses:>8} {current:>8.1f}ms {existential:>10.1f}ms "
            f"{concrete:>8.1f}ms {100 * (existential / current - 1):>+11.1f}% "
            f"{100 * (concrete / current - 1):>+8.1f}%"
        )


if __name__ == "__main__":
    main()
