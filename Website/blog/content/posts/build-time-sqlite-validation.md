---
title: "SwiftQL now validates your queries against your real database at build time"
date: 2026-07-31
description: "How to set up SwiftQL 1.5.2's build-time SQLite validation: a SwiftPM plugin that prepares every query against your real schema with sqlite3_prepare_v3, with the exact commands and output."
---

SwiftQL type-checks a query against the Swift types you declared. Until 1.5.2 it could not check that those types still matched the database on disk, so a renamed column stayed invisible until the query ran.

Version 1.5.2 adds a validator that opens your real SQLite schema read-only and prepares every query against it with `sqlite3_prepare_v3`, the same call SQLite uses to check a statement. It runs as a SwiftPM build-tool plugin, so `swift build` fails when a query no longer matches the database.

## What you need

Three things, all checked into your repository:

1. A SQLite file with your real schema in it. This is a snapshot for validation, not your production database.
2. A manifest describing each query: its SQL, parameters, and result columns.
3. The plugin, listed on the target you want validated.

## Step 1: add the plugin to your target

```swift
.target(
    name: "MyDatabase",
    plugins: [
        .plugin(name: "SwiftQLSQLiteBuildValidationPlugin", package: "SwiftQL"),
    ]
)
```

## Step 2: drop the snapshot and manifest into the target

Both files go directly in the target's own source directory, under these exact names:

```
Sources/MyDatabase/
├── swiftql-build-validation-manifest.json
└── swiftql-build-validation-snapshot.sqlite
```

If a target lists the plugin but is missing either file, the build fails with a plugin error rather than skipping validation.

The manifest describes one query per entry. `sql` is the statement to prepare, `parameters` describes each binding, and `results` describes each column you expect back:

```json
{
  "format_version": 1,
  "conformance_inventory_version": "190.1.0",
  "combinatorial_manifest_version": "c191-v2",
  "schema_snapshot": {
    "identifier": "northwind.issue-254",
    "kind": "checked-in-snapshot",
    "database_byte_count": 602112,
    "database_sha256": "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8",
    "schema_fingerprint": "e2c8fadbd38c2313",
    "schema_row_count": 37
  },
  "queries": [
    {
      "id": "app.customer-company-name",
      "definition_identity": "app/customer-company-name@1",
      "descriptor_identity": "swiftql-query-v1-app",
      "dialect_identifier": "sqlite",
      "dialect_capabilities_raw_value": 0,
      "cardinality": 2,
      "sql": "SELECT CompanyName AS company_name FROM Customers WHERE CustomerID = :customer_id",
      "parameters": [
        {
          "identity": "parameter/customer_id",
          "key_kind": "named",
          "key_name": "customer_id",
          "logical_index": 0,
          "physical_index": 1,
          "nullability": "required",
          "storage_identifier": "text",
          "value_type_identifier": "swift.string",
          "value_type_name": "Swift.String"
        }
      ],
      "results": [
        {
          "identity": "result/company_name",
          "declared_alias": "company_name",
          "index": 0,
          "nullability": "required",
          "storage_identifier": "text",
          "value_type_identifier": "swift.string",
          "value_type_name": "Swift.String"
        }
      ],
      "required_capabilities": [],
      "conformance_case_ids": [],
      "conformance_feature_ids": [],
      "northwind_anchor_case_ids": []
    }
  ]
}
```

The `schema_snapshot` block pins which database the manifest was written against. The validator records the snapshot it opened, so a manifest and a schema that drift apart show up in the report.

## Step 3: build

```bash
swift build
```

Validation appears as an ordinary build step:

```
[13/17] SwiftQL SQLite build validation (SecondValidatedLibrary)
[14/17] Copying swiftql-build-validation-report.json
[15/17] SwiftQL SQLite build validation (ValidatedLibrary)
[16/17] Copying swiftql-build-validation-report.json
Build complete! (26.47s)
```

The plugin declares the manifest and snapshot as build inputs and the report as an output, so SwiftPM's own incremental planner decides when to re-run it. An unchanged rebuild skips validation entirely; touching the manifest re-runs it.

## What a failure looks like

Rename `Customers` to `Customer` in the SQL and the build stops:

```
swiftql-build-validate: overall verdict failed
  app.customer-company-name: [failed] prepare.sqlite.prepare.failed: no such table: Customer
```

Typo a column and you get the column name back, not a generic parse error:

```
swiftql-build-validate: overall verdict failed
  app.customer-company-name: [failed] prepare.sqlite.prepare.failed: no such column: CompanyNam
```

Declare a result alias your SQL doesn't produce and the mismatch is named on both sides:

```
swiftql-build-validate: overall verdict failed
  app.customer-company-name: [failed] result.result.name: Result column 0 is named
  'company_name'; descriptor expects explicit alias 'companyName'.
```

Each query gets one of three verdicts: `passed`, `failed`, or `unsupported`. Only `passed` succeeds, so a query the validator cannot check fails the build instead of being waved through.

Alongside the console output the plugin writes a deterministic JSON report. Every diagnostic carries the query it came from, the stage it failed at, and SQLite's own result code:

```json
{
  "code": "sqlite.prepare.failed",
  "message": "no such table: totally_missing_table",
  "query_id": "plugin-fixture.missing-table",
  "stage": "prepare",
  "verdict": "failed",
  "sqlite_result_code": 1,
  "sqlite_extended_result_code": 1
}
```

The report also records the SQLite build it ran against: version, source ID, compile options, and registered collations. Same inputs always produce a byte-identical report.

## Running the validator on its own

The plugin wraps a standalone executable you can run directly, which is useful in CI or while writing a manifest by hand:

```bash
swiftql-build-validate \
  --database Sources/MyDatabase/swiftql-build-validation-snapshot.sqlite \
  --manifest Sources/MyDatabase/swiftql-build-validation-manifest.json \
  --output report.json
```

It exits 0 when every query passes and 1 otherwise. The full option list:

```
Usage: swiftql-build-validate [options]

  --database <path>      Checked-in SQLite snapshot to open read-only
  --manifest <path>      Codable build-validation manifest (#292)
  --output <path>        Deterministic JSON report destination
  --codec <identity>     Available codec identity (repeatable)
  --extension <name>     Registered extension name (repeatable)
  --capability <id>      Explicit caller-owned capability (repeatable)
  --help, -h             Show this help
```

## What it proves, and what it doesn't

It proves the SQL parses, that every referenced table, column, function, and collation resolves against your real schema, and that bind and result metadata match what the manifest declared.

It does not prove result values, row counts, or anything about runtime behavior. Each report lists its own `delegated_checks`, naming what it deliberately did not verify rather than implying coverage it doesn't have.

The prepared statement exists only while a query is inspected. It is always finalized, and never persisted or reused by runtime execution.

## Where it stands today

Two limits are worth knowing before you adopt this.

The manifest is hand-authored or generated by something outside the library. No macro in this release produces one from your query declarations, which is the obvious next step and the reason the manifest format is versioned and frozen.

Validation runs under `swift build`. Building the same package in Xcode currently fails before validation runs, with `Build input file cannot be found` naming the validator executable, so treat this as a command-line and CI tool for now.

Architecture and design rationale: [SQLiteBuildValidation.md](https://github.com/lukevanin/swiftql/blob/main/Documentation/Architecture/SQLiteBuildValidation.md)
The project: [github.com/lukevanin/swiftql](https://github.com/lukevanin/swiftql)
