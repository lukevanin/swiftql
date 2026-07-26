#!/usr/bin/env python3
"""Second-build EQP capture for issue #390 (milestone 29 spike).

The Swift CLI (`swiftql-eqp-variance capture`) only ever links whatever
SQLite the Swift toolchain resolves at build time (this repo's system
libsqlite3, unpinned). To get a second, genuinely distinct SQLite build's
worth of evidence without vendoring a custom SQLite into the shipping
package, this script drives Python's own `sqlite3` module (linked against
a different libsqlite3, e.g. Homebrew's) against the *same* corpus JSON
exported by `swiftql-eqp-variance export-corpus`, and writes an
EQPCaptureRun-shaped JSON evidence file in the same schema the Swift side
uses (see EQPVarianceModels.swift), so both are comparable by the same
classifier without a schema translation step.

Research/measurement only. Never mutates the database it reads from: opens
the given path read-only via the "file:...?mode=ro" URI form.

Usage:
    python3 capture_eqp.py --corpus corpus.json --database northwind_copy.db \
        --label homebrew-3.53.2 --output capture_homebrew.json
"""
import argparse
import json
import sqlite3
import sys


FNV_OFFSET_BASIS = 14_695_981_039_346_656_037
FNV_PRIME = 1_099_511_628_211
FNV_MASK = (1 << 64) - 1


def fnv1a64_update(h, data):
    for byte in data:
        h ^= byte
        h = (h * FNV_PRIME) & FNV_MASK
    return h


def fnv1a64_update_length_prefixed(h, field):
    field_bytes = field.encode("utf-8")
    h = fnv1a64_update(h, str(len(field_bytes)).encode("ascii"))
    h = fnv1a64_update(h, b":")
    h = fnv1a64_update(h, field_bytes)
    h = fnv1a64_update(h, b"\n")
    return h


def schema_fingerprint(connection):
    """Mirrors SQLiteBuildValidationRuntime.schemaFingerprint(rows:) exactly
    (same field order, same length-prefixed FNV-1a-64), so a capture against
    an unmodified copy of the pinned Northwind snapshot produces the same
    digest as the Swift-side capture against another copy of the same file.
    """
    rows = connection.execute(
        """
        SELECT type, name, tbl_name, rootpage, COALESCE(sql, '') AS sql
        FROM sqlite_schema
        ORDER BY
            type COLLATE BINARY,
            name COLLATE BINARY,
            tbl_name COLLATE BINARY,
            rootpage,
            sql COLLATE BINARY
        """
    ).fetchall()
    h = FNV_OFFSET_BASIS
    for row in rows:
        type_, name, tbl_name, rootpage, sql = row
        for field in (type_, name, tbl_name, str(rootpage), sql):
            h = fnv1a64_update_length_prefixed(h, field)
    return format(h, "016x")


def capture_runtime_metadata(connection):
    sqlite_version, sqlite_source_id = connection.execute(
        "SELECT sqlite_version(), sqlite_source_id()"
    ).fetchone()

    compile_options = sorted({
        row[0] for row in connection.execute("PRAGMA compile_options")
    })

    functions = []
    for row in connection.execute("PRAGMA function_list"):
        name, builtin, type_, enc, narg, flags = row
        functions.append({
            "name": name,
            "is_built_in": bool(builtin),
            "kind": type_,
            "encoding": enc,
            "argument_count": narg,
            "flags": flags,
        })
    functions.sort(key=lambda f: (
        f["name"], f["is_built_in"], f["kind"], f["encoding"],
        f["argument_count"], f["flags"],
    ))

    collations = sorted({
        row[1] for row in connection.execute("PRAGMA collation_list")
    })
    module_names = sorted({
        row[0] for row in connection.execute("PRAGMA module_list")
    })

    schema_row_count = connection.execute(
        "SELECT COUNT(*) FROM sqlite_schema"
    ).fetchone()[0]

    return {
        "sqlite_version": sqlite_version,
        "sqlite_source_id": sqlite_source_id,
        "compile_options": compile_options,
        "functions": functions,
        "collations": collations,
        "module_names": module_names,
        "extension_names": [],
        "schema_row_count": schema_row_count,
        "schema_fnv1a_64": schema_fingerprint(connection),
    }


def resolve_tagged_value(tagged):
    tag = tagged["tag"]
    if tag == "null":
        return None
    if tag == "integer":
        return int(tagged["value"])
    if tag == "real":
        raw = tagged["value"]
        return {"nan": float("nan"), "infinity": float("inf"), "-infinity": float("-inf")}.get(
            raw, float(raw)
        )
    if tag == "text":
        return tagged["value"]
    if tag == "blob":
        return bytes.fromhex(tagged["value"])
    raise ValueError(f"unknown tagged_value tag: {tag}")


def statement_arguments(bindings):
    """Mirrors EQPVarianceCapture.arguments(for:): all-named bindings bind by
    name, otherwise all-indexed bindings bind positionally by logical_index.
    """
    if not bindings:
        return {}
    if all(binding["key_kind"] == "named" for binding in bindings):
        return {
            binding["key_name"]: resolve_tagged_value(binding["tagged_value"])
            for binding in bindings
        }
    ordered = sorted(bindings, key=lambda binding: binding["logical_index"])
    return [resolve_tagged_value(binding["tagged_value"]) for binding in ordered]


def capture_statement(connection, statement):
    arguments = statement_arguments(statement["bindings"])
    sql = f"EXPLAIN QUERY PLAN {statement['rendered_sql']}"
    if isinstance(arguments, dict):
        rows = connection.execute(sql, arguments).fetchall()
    else:
        rows = connection.execute(sql, arguments).fetchall()
    return {
        "statement_id": statement["id"],
        "rows": [
            {"id": row[0], "parent": row[1], "notused": row[2], "detail": row[3]}
            for row in rows
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--capture-method",
        default="python3-sqlite3-module",
        help="recorded verbatim in the evidence file's capture_method field",
    )
    args = parser.parse_args()

    with open(args.corpus, "r", encoding="utf-8") as handle:
        corpus = json.load(handle)

    connection = sqlite3.connect(f"file:{args.database}?mode=ro", uri=True)
    try:
        connection.execute("PRAGMA query_only = ON")
        runtime_metadata = capture_runtime_metadata(connection)
        statements = sorted(
            (capture_statement(connection, statement) for statement in corpus),
            key=lambda entry: entry["statement_id"],
        )
    finally:
        connection.close()

    run = {
        "label": args.label,
        "capture_method": args.capture_method,
        "runtime_metadata": runtime_metadata,
        "statements": statements,
    }

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(run, handle, indent=2, sort_keys=True, ensure_ascii=False)
        handle.write("\n")

    print(
        f"Captured {len(statements)} statements (label: {args.label}) to {args.output}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
