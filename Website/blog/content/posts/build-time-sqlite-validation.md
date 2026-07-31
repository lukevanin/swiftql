---
title: "Your build now fails if a query does not match your database"
date: 2026-07-31
description: "SwiftQL 1.5.2 adds a real build step that prepares every query against your actual SQLite schema with sqlite3_prepare_v3, and fails the build if anything doesn't match."
---

SwiftQL type-checks the shape of a query against the Swift types you declared, but until recently it could not check that those types still matched the database sitting on disk. A migration that renamed a column, or a manifest that drifted from the schema, only showed up the moment the query ran.

Version 1.5.2 closes that gap with a real build step. `swift build` now opens a dedicated, read-only connection to your actual SQLite schema and prepares every query in your project against it with `sqlite3_prepare_v3`, the same call SQLite itself uses to check a statement. If the SQL does not parse, a table or column does not exist, a bound parameter count is wrong, or the result columns do not match what your Swift types expect, the build fails and prints the exact reason.

The pipeline has three pieces. A manifest projects each query's SQL, parameters, result columns, and required capabilities into a deterministic JSON file, checked in next to a snapshot of the real schema. A standalone validator, `swiftql-build-validate`, consumes that manifest and prepares every entry against the snapshot, producing one of three verdicts per query: passed, failed, or unsupported, where only "passed" is success. A SwiftPM build-tool plugin wraps the validator into an ordinary `swift build`, so nothing extra needs to be run or remembered.

The plugin declares the manifest and the report as explicit build inputs and outputs, so SwiftPM's own incremental build planner decides when validation needs to rerun, not the plugin itself.

The validator proves the SQL parses, that referenced tables, columns, functions, and collations resolve, and that bind and result metadata match the manifest. It does not prove result values, row counts, or anything about runtime behavior, and the report says so explicitly rather than implying coverage it does not have.

Today the manifest is hand-authored or generated outside the library. A macro that generates it directly from your query declarations is a planned next step.

Architecture and design rationale: [SQLiteBuildValidation.md](https://github.com/lukevanin/swiftql/blob/main/Documentation/Architecture/SQLiteBuildValidation.md)
The project: [github.com/lukevanin/swiftql](https://github.com/lukevanin/swiftql)
