---
title: "SwiftQL now validates your declared queries against your real database at build time"
date: 2026-09-15
description: "How to set up SwiftQL 1.9's build-time SQLite validation for a package that declares its queries with @SQLQuery: generate the manifest from the declarations, then let swift build prepare every query against your real schema, with the exact commands and output."
---

SwiftQL type-checks a query against the Swift types you declared. It cannot, on its own, check that those types still match the database on disk, so a column renamed in the database stays invisible until the query runs.

SwiftQL's build-time validation closes that gap. A validator opens a checked-in copy of your SQLite schema read-only and prepares every query against it with `sqlite3_prepare_v3`, the same call SQLite uses to check a statement. It runs as a SwiftPM build-tool plugin, so `swift build` fails when a query no longer matches the database.

The validator shipped in 1.5.2, but it needed a manifest describing every query, and in practice you had to write that manifest by hand. In 1.9 the manifest comes from the queries you already declare with `@SQLQuery` and `@SQLQueries`. Add a query, regenerate, and it is validated; there is no list of queries to keep in step.

Every command and every block of output below was captured from a fresh package that follows this post step by step.

## What you need

Three things, all checked into your repository:

1. A SQLite file with your real schema in it. This is a snapshot for validation, not your production database.
2. A manifest describing each query: its SQL, parameters, and result columns. You generate this.
3. Two plugins: one that finds your declared queries, and one that validates them.

## The package

The example is a small bookshop package with three targets:

```swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Bookshop",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/lukevanin/swiftql.git", from: "1.9.0"),
    ],
    targets: [
        // The schema and the declared queries.
        .target(
            name: "Bookshop",
            dependencies: [
                .product(name: "SwiftQL", package: "swiftql"),
            ],
            plugins: [
                .plugin(name: "SwiftQLDeclaredQueryRegistryPlugin", package: "swiftql"),
            ]
        ),
        // Writes the manifest from the declared queries.
        .executableTarget(
            name: "bookshop-manifest",
            dependencies: [
                "Bookshop",
                .product(name: "SwiftQL", package: "swiftql"),
                .product(name: "SwiftQLSQLiteBuildValidationDeclaredQueries", package: "swiftql"),
            ]
        ),
        // Holds the snapshot and manifest, and validates them on every build.
        .target(
            name: "BookshopValidation",
            plugins: [
                .plugin(name: "SwiftQLSQLiteBuildValidationPlugin", package: "swiftql"),
            ]
        ),
    ]
)
```

The validation plugin sits on a target of its own because the manifest is generated from the compiled `Bookshop` target. Keeping the two apart means the queries target never waits on a file that is written from it.

`BookshopValidation` needs one Swift file to be a target at all. It can be a single line:

```swift
// Holds the snapshot and manifest that SwiftQLSQLiteBuildValidationPlugin checks.
enum BookshopValidation {}
```

## Step 1: declare your queries

Nothing about declaring a query changes. Here is the schema:

```swift
import SwiftQL

@SQLTable
public struct Author {
    public var id: String
    public var name: String
}

@SQLTable
public struct Book {
    public var id: String
    public var authorID: String
    public var title: String
}
```

And two queries, one in each form:

```swift
import SwiftQL

@SQLQueries
extension GRDBDatabase {

    private struct Query {

        func booksByAuthor(authorID: String) -> [Book] {
            sqlResult { schema in
                let book = schema.table(Book.self)
                Select(book)
                From(book)
                Where(book.authorID == authorID)
            }
        }
    }
}

extension GRDBDatabase {

    @SQLQuery
    public func author(id: String) -> Author? {
        sqlResult { schema in
            let author = schema.table(Author.self)
            Select(author)
            From(author)
            Where(author.id == id)
        }
    }
}
```

In 1.9 both macros also describe each query as data, and `SwiftQLDeclaredQueryRegistryPlugin` scans the target's sources on every build and compiles a `BookshopDeclaredQueries` enum into it. Its `queries(for:)` method takes your database instances and returns every declared query it found, across every file in the target.

A declaration the generated registry cannot reach from another file, such as a `private` or `fileprivate` one, is not dropped silently. The build warns about it, naming the query and the file and line it is on. To leave a declaration out on purpose, put `// swiftql-registry: ignore` directly above it, before its first attribute.

## Step 2: generate the snapshot and the manifest

Both files go directly in the validation target's source directory, under these exact names:

```
Sources/BookshopValidation/
├── BookshopValidation.swift
├── swiftql-build-validation-manifest.json
└── swiftql-build-validation-snapshot.sqlite
```

### The snapshot

The snapshot is your real schema, not one derived from the Swift types, because the point is to catch the two drifting apart. Here the schema lives in a `schema.sql` file, and the `sqlite3` command-line tool writes the snapshot:

```sql
CREATE TABLE Author (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE Book (
    id TEXT NOT NULL PRIMARY KEY,
    authorID TEXT NOT NULL REFERENCES Author(id),
    title TEXT NOT NULL
);
```

```bash
sqlite3 Sources/BookshopValidation/swiftql-build-validation-snapshot.sqlite < schema.sql
```

Use whatever produces your app's schema: a copy of a migrated database works as well. The validator wants a file in rollback-journal mode with no `-wal` or `-shm` companions beside it, which is what `sqlite3` writes by default.

### The generator

The generator opens a database the way your app does, asks the registry for every declared query, and writes the manifest. It names no query:

```swift
import Foundation
import Bookshop
import SwiftQL
import SwiftQLSQLiteBuildValidationDeclaredQueries

// usage: bookshop-manifest TARGET_DIRECTORY
let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let snapshotURL = target.appendingPathComponent("swiftql-build-validation-snapshot.sqlite")
let manifestURL = target.appendingPathComponent("swiftql-build-validation-manifest.json")

// Open a database the way the app does, so each query renders with the
// app's own encoder. Its contents don't matter; only its type does.
let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("bookshop-manifest-\(UUID().uuidString).sqlite")
let database = try GRDBDatabase(url: scratch, logger: nil)

let queries = try BookshopDeclaredQueries.queries(for: [database])
let generated = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
    queries: queries,
    snapshotIdentifier: "bookshop.schema",
    snapshotURL: snapshotURL
)
for skipped in generated.skippedQueries {
    print("skipped \(skipped.queryID): \(skipped.reason)")
}
try generated.manifest.canonicalJSONData().write(to: manifestURL, options: .atomic)
print("wrote \(generated.manifest.queries.count) queries to \(manifestURL.lastPathComponent)")
```

`queries(for:)` throws if you leave out an instance of a database type that declares queries, so a whole type cannot go missing from the manifest. `makeManifest` skips, by name and with a reason, any query whose rows it cannot describe statically rather than guessing; the generator prints those.

### Run it

One wrinkle on the very first run: SwiftPM plans every target's plugins before it builds anything, even for `swift run`, and the validation plugin refuses to plan without its manifest:

```
error: Target 'BookshopValidation' opts into SwiftQLSQLiteBuildValidationPlugin but is missing swiftql-build-validation-manifest.json in its target directory.
error: build planning stopped due to build-tool plugin failures
```

An empty placeholder is enough to get past planning, since `swift run bookshop-manifest` never builds the validation target:

```bash
touch Sources/BookshopValidation/swiftql-build-validation-manifest.json
swift run bookshop-manifest Sources/BookshopValidation
```

```
Build complete! (16,06 sec)
wrote 2 queries to swiftql-build-validation-manifest.json
```

Each entry in the manifest carries the SQL exactly as your app renders it, plus its parameters and result columns. Here is one, with the long `descriptor_identity` shortened:

```json
{
  "cardinality" : 2,
  "conformance_case_ids" : [

  ],
  "conformance_feature_ids" : [

  ],
  "definition_identity" : "GRDBDatabase/author@1",
  "descriptor_identity" : "swiftql-query-v1-5377696674514c2e…",
  "dialect_capabilities_raw_value" : 1,
  "dialect_identifier" : "sqlite",
  "id" : "GRDBDatabase.author",
  "northwind_anchor_case_ids" : [

  ],
  "parameters" : [
    {
      "identity" : "parameter/id",
      "key_kind" : "named",
      "key_name" : "id",
      "logical_index" : 0,
      "nullability" : "required",
      "physical_index" : 1,
      "storage_identifier" : "text",
      "value_type_identifier" : "swift.string",
      "value_type_name" : "Swift.String"
    }
  ],
  "required_capabilities" : [

  ],
  "results" : [
    {
      "declared_alias" : "id",
      "identity" : "result/id",
      "index" : 0,
      "nullability" : "required",
      "storage_identifier" : "text",
      "value_type_identifier" : "swift.string",
      "value_type_name" : "Swift.String"
    },
    {
      "declared_alias" : "name",
      "identity" : "result/name",
      "index" : 1,
      "nullability" : "required",
      "storage_identifier" : "text",
      "value_type_identifier" : "swift.string",
      "value_type_name" : "Swift.String"
    }
  ],
  "sql" : "SELECT \"t0\".\"id\" AS \"id\", \"t0\".\"name\" AS \"name\" FROM \"Author\" AS \"t0\" WHERE (\"t0\".\"id\" == :id)"
}
```

The file ends with a `schema_snapshot` block that pins the database the manifest was written against:

```json
"schema_snapshot" : {
  "database_byte_count" : 20480,
  "database_sha256" : "681956f7834dd45d0fc9b0350589662580754908a3fab8542bda3e1a20801d70",
  "identifier" : "bookshop.schema",
  "kind" : "checked-in-snapshot",
  "schema_fingerprint" : "a357a73ae573380a",
  "schema_row_count" : 4
}
```

This is manifest format version 2. It leaves out the conformance-inventory fields that version 1 required, which only ever made sense for SwiftQL's own test fixtures, and it rejects any key it does not define, so a typo in a hand-edited manifest fails instead of being ignored. `canonicalJSONData()` sorts keys and entries, so regenerating an unchanged package produces a byte-identical file and no diff.

Check both files in. Rerun the generator whenever you change the schema or a declared query.

### When you can't generate it: writing entries by hand

The generator covers queries declared with `@SQLQuery` and `@SQLQueries` on a database it can open. For anything else, such as a statement you build outside a declaration, you can still write a manifest yourself. A hand-written version 2 entry needs only the required keys; this one passes against the same snapshot:

```json
{
  "format_version": 2,
  "schema_snapshot": {
    "database_byte_count": 20480,
    "database_sha256": "681956f7834dd45d0fc9b0350589662580754908a3fab8542bda3e1a20801d70",
    "identifier": "bookshop.schema",
    "kind": "checked-in-snapshot",
    "schema_fingerprint": "a357a73ae573380a",
    "schema_row_count": 4
  },
  "queries": [
    {
      "id": "bookshop.book-titles",
      "definition_identity": "bookshop/book-titles@1",
      "descriptor_identity": "bookshop.book-titles.v1",
      "dialect_identifier": "sqlite",
      "dialect_capabilities_raw_value": 0,
      "cardinality": 3,
      "sql": "SELECT title AS title FROM Book WHERE authorID = :author_id",
      "parameters": [
        {
          "identity": "parameter/author_id",
          "key_kind": "named",
          "key_name": "author_id",
          "logical_index": 0,
          "physical_index": 1,
          "nullability": "required",
          "storage_identifier": "text",
          "value_type_identifier": "swift.string"
        }
      ],
      "results": [
        {
          "identity": "result/title",
          "declared_alias": "title",
          "index": 0,
          "nullability": "required",
          "storage_identifier": "text",
          "value_type_identifier": "swift.string"
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

The awkward part is `schema_snapshot`: the fingerprint and row count come from SQLite, not from anything you can type. The simplest way to get a correct block is to call `makeManifest` with an empty `queries` array, which version 2 allows, and copy the block from its output.

## Step 3: build

```bash
swift build
```

```
Building for debugging...
[Computing dependencies]
[Provisioning 3 / 41]
[Pre-planning 1 / 858]
[Planning deferred tasks]
[19 / 97] BookshopValidation
[22 / 43] swiftql-build-validate-product
[26 / 45] swiftql-build-validate-product
[27 / 45] swiftql-build-validate-product
[34 / 46] BookshopValidation
[44 / 49] Bookshop_BookshopValidation
Build complete! (1,99 sec)
```

A passing validation is quiet. It leaves a report behind at:

```
.build/plugins/outputs/bookshop/BookshopValidation/destination/SwiftQLSQLiteBuildValidationPlugin/BookshopValidation/swiftql-build-validation-report.json
```

and that report says `"overall_verdict" : "passed"`.

The plugin declares the manifest and snapshot as build inputs and the report as an output, so SwiftPM's own incremental planner decides when to run it. An unchanged rebuild leaves the report untouched; touching the manifest runs validation again.

## What a failure looks like

Rename `title` to `bookTitle` in `schema.sql` and rewrite the snapshot, but forget to regenerate the manifest. The build stops, because the snapshot is no longer the one the manifest was written against:

```
swiftql-build-validate: overall verdict failed
  [failed] schema.schema.fingerprint: Observed schema FNV-1a-64 is 2132d8a01955e0c6; the manifest's schema snapshot declares a357a73ae573380a.
  [failed] schema.schema.snapshot-sha: Observed database SHA-256 is 0b50fabc3fcee6e44db59406c0ed9018f44e7e01de35c8569130b55d1a672205; the manifest's schema snapshot declares 681956f7834dd45d0fc9b0350589662580754908a3fab8542bda3e1a20801d70.
  GRDBDatabase.author: [unsupported] schema.schema.mismatch-skipped: Query validation was skipped because the database snapshot's schema identity does not match the manifest.
  GRDBDatabase.booksByAuthor: [unsupported] schema.schema.mismatch-skipped: Query validation was skipped because the database snapshot's schema identity does not match the manifest.
error: Build failed
```

Regenerate the manifest, build again, and the real problem surfaces. `Book` still selects `title`, and the database no longer has it:

```bash
swift run bookshop-manifest Sources/BookshopValidation
swift build
```

```
swiftql-build-validate: overall verdict failed
  GRDBDatabase.booksByAuthor: [failed] prepare.sqlite.prepare.failed: no such column: t0.title
error: Build failed
```

That is the failure this whole setup exists to catch: Swift and the database disagree, and you find out at build time instead of when a user opens the book list. (SwiftPM also prints the sandboxed command line it ran between those two lines; it is left out here.)

Each query gets one of three verdicts: `passed`, `failed`, or `unsupported`. Only `passed` succeeds, so a query the validator cannot check fails the build instead of being waved through.

Alongside the console output, the plugin writes a deterministic JSON report. Every diagnostic carries the query it came from, the stage it failed at, and SQLite's own result code:

```json
{
  "code": "sqlite.prepare.failed",
  "conformance_case_ids": [],
  "conformance_feature_ids": [],
  "definition_identity": "GRDBDatabase/booksByAuthor@1",
  "message": "no such column: t0.title",
  "northwind_anchor_case_ids": [],
  "query_id": "GRDBDatabase.booksByAuthor",
  "sqlite_extended_result_code": 1,
  "sqlite_result_code": 1,
  "stage": "prepare",
  "verdict": "failed"
}
```

The report also records the SQLite it ran against: version, source ID, compile options, collations, functions, and modules.

## Adding a query

Add a third query in a new file, and touch nothing else:

```swift
import SwiftQL

extension GRDBDatabase {

    @SQLQuery
    public func authorsNamed(name: String) -> [Author] {
        sqlResult { schema in
            let author = schema.table(Author.self)
            Select(author)
            From(author)
            Where(author.name == name)
        }
    }
}
```

```bash
swift run bookshop-manifest Sources/BookshopValidation
```

```
wrote 3 queries to swiftql-build-validation-manifest.json
```

The generator and `Package.swift` are unchanged, and the next `swift build` validates all three.

## Running the validator on its own

The plugin wraps a standalone executable you can run directly, which is useful in CI or while debugging a manifest:

```bash
swift run swiftql-build-validate \
  --database Sources/BookshopValidation/swiftql-build-validation-snapshot.sqlite \
  --manifest Sources/BookshopValidation/swiftql-build-validation-manifest.json \
  --output report.json
```

It exits 0 when every query passes and 1 otherwise. The full option list:

```
Usage: swiftql-build-validate [options]

  --database <path>      Checked-in SQLite snapshot to open read-only
  --manifest <path>      Codable build-validation manifest (#292)
  --output <path>        Deterministic JSON report destination
  --plan-output <path>   Advisory query-plan sidecar destination
                         (omit to skip plan capture entirely)
  --plan-suppressions <path>
                         Checked-in advisory suppression rules
  --plan-scan-row-threshold <rows>
                         Diagnose a full table scan only above this
                         many rows (default 500)
  --verify-index-candidates
                         Verify each index candidate by re-planning on
                         a disposable copy of the snapshot
  --codec <identity>     Available codec identity (repeatable)
  --extension <name>     Registered extension name (repeatable)
  --capability <id>      Explicit caller-owned capability (repeatable)
  --help, -h              Show this help
```

The `--plan-*` options belong to the query-plan analysis that 1.8 added on top of validation; they are off unless you ask for them.

## What it proves, and what it doesn't

It proves the SQL parses, that every referenced table, column, function, and collation resolves against your real schema, and that bind and result metadata match what the manifest declared.

It does not prove result values, row counts, or anything about runtime behavior. Each report lists its own `delegated_checks`, naming what it deliberately did not verify rather than implying coverage it doesn't have.

The prepared statement exists only while a query is inspected. It is always finalized, and never persisted or reused by runtime execution.

## Where it stands today

A few limits are worth knowing before you adopt this.

**Query discovery runs in SwiftPM targets.** `SwiftQLDeclaredQueryRegistryPlugin` is a SwiftPM build-tool plugin, so the target that declares your queries has to be a package target. An Xcode app can depend on that package as usual, but you cannot attach the registry plugin to the app target itself yet ([#766](https://github.com/lukevanin/swiftql/issues/766)).

**Validation also runs in Xcode app targets.** As of 1.9, `SwiftQLSQLiteBuildValidationPlugin` conforms to `XcodeBuildToolPlugin` as well, so you can add it under an app target's **Run Build Tool Plug-ins** build phase and add the manifest and snapshot to the target ([#666](https://github.com/lukevanin/swiftql/issues/666)). That path is checked by a script run by hand rather than in CI for now ([#757](https://github.com/lukevanin/swiftql/issues/757)). If you go that way, check what the built app bundle contains before shipping it: Xcode can copy the manifest, the snapshot, and the report into the bundle.

**The generator needs a `GRDBDatabase`.** Lowering a declared query needs the database's SQL encoder, and `GRDBDatabase` is the adapter that supplies it.

**Declared queries are read-only.** Only `SELECT`-shaped declarations exist, so only those are in the generated manifest. Anything else goes in by hand.

Declared queries and the registry: [DeclaredQueries](https://github.com/lukevanin/swiftql/blob/main/Sources/SwiftQL/SwiftQL.docc/DeclaredQueries.md)
Architecture and design rationale: [SQLiteBuildValidation.md](https://github.com/lukevanin/swiftql/blob/main/Documentation/Architecture/SQLiteBuildValidation.md)
The project: [github.com/lukevanin/swiftql](https://github.com/lukevanin/swiftql)
