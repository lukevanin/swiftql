import Foundation

import FixtureQueries
import GRDB
import SwiftQL
import SwiftQLSQLiteBuildValidationDeclaredQueries
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator

// Writes a snapshot and a manifest for every declared query in
// FixtureQueries, then validates them. It names no query: the list comes
// from the registry SwiftQLDeclaredQueryRegistryPlugin generates.
//
// usage: fixture-manifest OUTPUT_DIRECTORY

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: fixture-manifest OUTPUT_DIRECTORY\n".utf8))
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let snapshotURL = outputDirectory.appendingPathComponent("snapshot.sqlite")
let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
try? FileManager.default.removeItem(at: snapshotURL)

let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
try snapshotQueue.write { database in
    let encoder = XLiteEncoder(dialect: XLSQLiteDialect())
    try database.execute(sql: encoder.makeValidatedSQL(sqlCreate(FixtureAuthor.self)).sql)
}
try snapshotQueue.close()

let databaseURL = outputDirectory.appendingPathComponent("scratch.sqlite")
try? FileManager.default.removeItem(at: databaseURL)
let database = try GRDBDatabase(url: databaseURL, logger: nil)

let queries = try FixtureQueriesDeclaredQueries.queries(for: [database])
let generated = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
    queries: queries,
    snapshotIdentifier: "fixture.schema",
    snapshotURL: snapshotURL
)
for skipped in generated.skippedQueries {
    print("skipped: \(skipped.queryID): \(skipped.reason)")
}
try generated.manifest.canonicalJSONData().write(to: manifestURL, options: .atomic)
for entry in generated.manifest.queries {
    print("query: \(entry.id)")
}

let report = try SQLiteBuildValidator.validate(
    manifest: generated.manifest,
    againstDatabaseAt: snapshotURL
)
print("verdict: \(report.overallVerdict.rawValue)")
for diagnostic in report.outcomes.flatMap(\.diagnostics) {
    print("diagnostic: \(diagnostic.queryID ?? "-"): \(diagnostic.message)")
}
exit(report.overallVerdict == .passed ? 0 : 1)
