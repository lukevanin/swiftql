#!/usr/bin/env python3
"""Write the refusal and diagnostic fixtures for each surface."""

import os

import sys

OUT = os.path.join(sys.argv[1], "generated")
os.makedirs(OUT, exist_ok=True)

MODULE = {
    "current": "GateCurrent",
    "existential": "GateExistential",
    "concrete": "GateConcrete",
    "wrapper": "GateWrapper",
}


def scope(kind, dialect):
    if kind == "current":
        return "XLGateScope()"
    return f"XLGateScope<{dialect}>()"


# Each entry is (name, dialect, body). A body is one statement.
REFUSAL = [
    ("collate-sqlite-column", "XLGateSQLite", "_ = scope.text0.collate(\"NOCASE\")"),
    (
        "collate-sqlite-composed",
        "XLGateSQLite",
        "_ = (scope.text0 + scope.text1).collate(\"NOCASE\")",
    ),
    (
        "collate-postgresql-column",
        "XLGatePostgreSQL",
        "_ = scope.text0.collate(\"NOCASE\")",
    ),
    (
        "collate-postgresql-composed",
        "XLGatePostgreSQL",
        "_ = (scope.text0 + scope.text1).collate(\"NOCASE\")",
    ),
    (
        "mixed-dialect-comparison",
        "XLGateSQLite",
        "_ = scope.text0 == XLGateScope<XLGatePostgreSQL>().text0",
    ),
]

# The current surface has no dialect. A PostgreSQL query and a mixed-dialect
# comparison therefore cannot be written against it at all. Writing one anyway
# would either repeat the SQLite fixture or make the compiler reject the scope
# type, and both would read as a result the surface did not produce.
SKIPPED = {
    ("current", "mixed-dialect-comparison"),
    ("current", "collate-postgresql-column"),
    ("current", "collate-postgresql-composed"),
}

# The three ordinary mistakes the accepted design measured.
DIAGNOSTIC = [
    ("mistake-type-mismatch", "scope.text0 == flag"),
    ("mistake-misspelled-column", "scope.nmae"),
    ("mistake-mismatched-columns", "scope.text0 == scope.count0"),
]


def main():
    for kind, module in MODULE.items():
        for name, dialect, body in REFUSAL:
            if (kind, name) in SKIPPED:
                continue
            path = os.path.join(OUT, f"{kind}-refusal-{name}.swift")
            with open(path, "w") as handle:
                handle.write(
                    f"import {module}\n\n"
                    "public func gateRefusal() {\n"
                    f"    let scope = {scope(kind, dialect)}\n"
                    f"    {body}\n"
                    "}\n"
                )
        for name, body in DIAGNOSTIC:
            path = os.path.join(OUT, f"{kind}-{name}.swift")
            with open(path, "w") as handle:
                handle.write(
                    f"import {module}\n\n"
                    "@XLGateQueryBuilder\n"
                    "public func gateQuery(flag: Bool) -> [any XLEncodable] {\n"
                    f"    let scope = {scope(kind, 'XLGateSQLite')}\n"
                    f"    {body}\n"
                    "}\n"
                )


if __name__ == "__main__":
    main()
