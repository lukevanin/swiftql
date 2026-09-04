---
title: "What's new in v1.5.2"
date: 2026-07-27
description: "SwiftQL v1.5.2 adds a manifest format, a standalone validator, and a SwiftPM build-tool plugin that check every static query against a real SQLite engine as part of swift build."
---

SwiftQL v1.5.2 adds a way to catch a broken static query before it ships, by checking it against a real SQLite engine during `swift build` instead of the first time it runs. Three new pieces work together: a manifest format that describes a query in JSON, a standalone command-line validator that checks a manifest against a database snapshot, and a SwiftPM plugin that wires the validator into an ordinary build. All three are additive; nothing in an existing project changes by installing this release.

## The manifest: a deterministic sidecar for static queries

`SwiftQLSQLiteBuildValidationManifest` projects an `XLStaticQueryDescriptor` into a canonical JSON sidecar: the SQL text, its parameters and result columns, the SQLite capabilities it needs, and the identity, hash, and fingerprint of a checked-in schema snapshot to validate against. A manifest is built from an existing descriptor with one call:

```swift
let entry = try SQLiteBuildValidationQueryEntry(
    id: "plugin-fixture.customer-company-name",
    descriptor: customerCompanyNameDescriptor,
    declaredAliases: ["company_name"]
)
```

The physical placeholder index for each parameter is recovered by scanning the rendered SQL, and the manifest cross-checks its own declared parameters against that SQL before any consumer runs it. The JSON it produces is deterministic: sorted keys, no escaped slashes, and every array sorted and deduplicated, so the same input always serializes to the same bytes. A trimmed manifest entry looks like this:

```json
{
  "id": "plugin-fixture.customer-company-name",
  "sql": "SELECT CompanyName AS company_name FROM Customers WHERE CustomerID = :customer_id",
  "parameters": [
    { "key_name": "customer_id", "logical_index": 0, "physical_index": 1, "storage_identifier": "text" }
  ],
  "results": [
    { "declared_alias": "company_name", "index": 0, "storage_identifier": "text" }
  ],
  "schema_snapshot": {
    "identifier": "northwind.issue-254",
    "database_sha256": "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8"
  }
}
```

References into the existing conformance inventory, the combinatorial test cases, and the Northwind fixture resolve through an injected `SQLiteBuildValidationReferenceRegistry`, so the manifest module itself has no dependency on those test-only targets.

## The standalone validator

`SwiftQLSQLiteBuildValidationValidator` and its `swiftql-build-validate` executable take a manifest and its snapshot, open one dedicated read-only connection, and prepare every entry with `sqlite3_prepare_v3`. That proves the SQL parses, every table, column, function, and collation it references resolves, and the bind and result metadata SQLite reports back matches what the manifest declared:

```
swiftql-build-validate \
    --database swiftql-build-validation-snapshot.sqlite \
    --manifest swiftql-build-validation-manifest.json \
    --output swiftql-build-validation-report.json
```

Every verdict is fail-closed: only `passed` counts as success, and `failed` or `unsupported` both stop the build. The report is deterministic across repeated runs against the same inputs. It does not check result values or row counts, and every report names that boundary explicitly under `delegated_checks`, so a passing report is not read as more than it is.

## The SwiftPM plugin

`SwiftQLSQLiteBuildValidationPlugin` wraps the validator in an ordinary `.buildTool()` plugin. A target opts in by listing the plugin and placing a manifest and its snapshot directly in its own source directory:

```swift
.target(
    name: "MyTarget",
    plugins: [
        .plugin(name: "SwiftQLSQLiteBuildValidationPlugin", package: "SwiftQL"),
    ]
)
```

The plugin declares the manifest and snapshot as explicit build-command inputs and the report as an explicit output, never as a `.prebuildCommand`, so SwiftPM's own incremental planner decides when to rerun it: an unchanged rebuild skips validation entirely, and touching either file reruns it. A `failed` or `unsupported` verdict fails the build and forwards the validator's diagnostic straight into `swift build`'s output, so there's no separate report to go read.

## What this doesn't check yet

The validator proves schema, parameter, and capability agreement with the real SQLite parser, not result values, row counts, or application behavior. No macro in this release emits a manifest from a `@SQLQuery` declaration: the v1.5.1 declaration macro still builds on the transitional `sql { }` statement path rather than lowering to a descriptor, so that route stays a future boundary gated on the v2 catalog work. A target's snapshot still has to be supplied by hand.

The plugin is verified under `swift build`. Building a plugin-adopting package in Xcode 26.5 fails before validation even runs, reporting `Build input file cannot be found` for the validator executable, regardless of whether the manifest is valid.

## Migration

No migration is required for v1.5.2. The manifest, validator, and plugin are new, additive surfaces with no changes to any existing public API.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.5.2 release](https://github.com/lukevanin/swiftql/releases/tag/v1.5.2)
