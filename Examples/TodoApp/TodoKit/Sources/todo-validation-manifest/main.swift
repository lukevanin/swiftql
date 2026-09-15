import Foundation

import GRDB
import SwiftQL
import SwiftQLSQLiteBuildValidationDeclaredQueries
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator
import TodoKit

// Regenerates the two files SwiftQL's build-time validation plugin reads out
// of the target it is attached to. That is TodoKitBuildValidation today, and
// the destination is an argument rather than a constant so that folding the
// validation target back into TodoKit (see BuildValidation.swift) needs no
// change here:
//
//   swiftql-build-validation-snapshot.sqlite — the demo's schema, as a
//       checked-in SQLite file the validator prepares statements against.
//   swiftql-build-validation-manifest.json  — one entry per declared query,
//       carrying the rendered SQL and its parameter and result metadata.
//
// This file lists no queries. SwiftQLDeclaredQueryRegistryPlugin scans
// TodoKit's sources on every build and generates `TodoKitDeclaredQueries`,
// which reads every @SQLQueries and @SQLQuery declaration from a database
// instance. A query added anywhere in TodoKit is in the next manifest without
// a change here. The hand-written list this
// generator used to carry is kept as a test fixture in
// TodoValidationManifestTests.swift.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data(
        "usage: todo-validation-manifest TARGET_DIRECTORY\n".utf8
    ))
    exit(64)
}

let targetDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let snapshotURL = targetDirectory
    .appendingPathComponent("swiftql-build-validation-snapshot.sqlite")
let manifestURL = targetDirectory
    .appendingPathComponent("swiftql-build-validation-manifest.json")

let encoder = XLiteEncoder(dialect: XLSQLiteDialect())

// MARK: - Snapshot

let schemaStatements: [any XLEncodable] = [
    sqlCreate(TodoList.self),
    sqlCreate(Todo.self),
    sqlCreate(Tag.self),
    sqlCreate(TodoTag.self),
]

try? FileManager.default.removeItem(at: snapshotURL)
for suffix in ["-journal", "-wal", "-shm"] {
    let sidecar = URL(fileURLWithPath: snapshotURL.path + suffix)
    try? FileManager.default.removeItem(at: sidecar)
}

// A `DatabaseQueue` leaves the snapshot in rollback-journal mode with no
// sidecar files, which is what the validator requires of an immutable
// checked-in artifact. A WAL-mode file would need its `-shm` companion to
// open read-only.
let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
try snapshotQueue.write { database in
    for statement in schemaStatements {
        try database.execute(sql: encoder.makeValidatedSQL(statement).sql)
    }
    // The same indices the app creates at launch. The snapshot has to carry
    // them, or the plan analysis the validator runs over this manifest would
    // describe a database the app never opens.
    for statement in TodoIndices.statements {
        try database.execute(sql: statement)
    }
}
try snapshotQueue.close()

// MARK: - Queries

// Read from a database opened the way the app opens one, so each query
// renders with the encoder the app's executors use.
let scratchDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("todo-validation-manifest-\(UUID().uuidString)", isDirectory: true)
defer {
    try? FileManager.default.removeItem(at: scratchDirectory)
}
let todoDatabase = try TodoDatabase(
    url: scratchDirectory.appendingPathComponent(TodoDatabase.fileName)
)
let queries = try TodoKitDeclaredQueries.queries(for: [todoDatabase.database])

// MARK: - Manifest

// Format version 2, with no fixture provenance: the demo's queries are its
// own, not authored against SwiftQL's #190/#191 test inventories.
let generated = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
    queries: queries,
    snapshotIdentifier: "todo-demo.schema",
    snapshotURL: snapshotURL
)
guard generated.skippedQueries.isEmpty else {
    for skipped in generated.skippedQueries {
        FileHandle.standardError.write(Data(
            "error: \(skipped.queryID) cannot be validated: \(skipped.reason)\n".utf8
        ))
    }
    exit(1)
}
try generated.manifest.canonicalJSONData().write(to: manifestURL, options: .atomic)

// MARK: - Validation

// A separate step from generation. Prove the artifacts this run just wrote
// actually pass, so a regeneration can never leave the repository in a state
// the plugin rejects.
let report = try SQLiteBuildValidator.validate(
    manifest: generated.manifest,
    againstDatabaseAt: snapshotURL
)
guard report.overallVerdict == .passed else {
    FileHandle.standardError.write(try report.canonicalJSONData())
    FileHandle.standardError.write(Data("\n".utf8))
    exit(1)
}

print("wrote \(snapshotURL.path)")
print("wrote \(manifestURL.path)")
