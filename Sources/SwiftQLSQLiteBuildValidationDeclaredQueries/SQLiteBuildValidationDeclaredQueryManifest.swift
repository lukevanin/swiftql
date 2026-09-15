//
//  SQLiteBuildValidationDeclaredQueryManifest.swift
//  SwiftQLSQLiteBuildValidationDeclaredQueries
//
//  Issue #659: projects the declared queries of a target into a format
//  version 2 build-validation manifest.
//

import Foundation

import GRDB
import SwiftQL
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator


///
/// Projects declared queries into a build-validation manifest.
///
/// `@SQLQueries` generates a `declaredQueries` member that lists every
/// specification in its container, so passing that member here produces a
/// manifest with no hand-written query list. A query added to the container
/// is in the next manifest.
///
/// Generation is not validation. The manifest this type returns has not been
/// checked against its snapshot; run ``SQLiteBuildValidator`` or the build
/// plugin for that.
///
public enum SQLiteBuildValidationDeclaredQueryManifest {

    ///
    /// One manifest entry per declared query, in the order given.
    ///
    /// Each entry is the `SQLiteBuildValidationQueryEntry(id:descriptor:declaredAliases:)`
    /// projection of the query's static descriptor, keyed by
    /// ``XLDeclaredQuery/id``. No entry carries a fixture reference.
    ///
    /// - Parameters:
    ///   - queries: The declared queries to project.
    ///   - dialect: The dialect the application's database renders with.
    ///
    public static func queryEntries(
        for queries: [XLDeclaredQuery],
        dialect: XLSQLiteDialect = XLSQLiteDialect()
    ) throws -> [SQLiteBuildValidationQueryEntry] {
        try queries.map { query in
            let lowered = try query.makeDescriptor(dialect: dialect)
            return try SQLiteBuildValidationQueryEntry(
                id: lowered.id,
                descriptor: lowered.descriptor,
                declaredAliases: lowered.resultAliases
            )
        }
    }

    ///
    /// A format version 2 manifest for `queries`, pinned to the snapshot at
    /// `snapshotURL`.
    ///
    /// The manifest omits both fixture provenance fields: the queries are the
    /// application's own. The snapshot's byte identity is read from the file,
    /// and its schema row count and fingerprint are captured by the
    /// validator's own runtime probe on a read-only connection, so they are
    /// the values the validator compares.
    ///
    /// - Parameters:
    ///   - queries: The declared queries to project.
    ///   - snapshotIdentifier: A stable name for the snapshot.
    ///   - snapshotURL: The checked-in SQLite snapshot the manifest describes.
    ///   - dialect: The dialect the application's database renders with.
    ///
    public static func makeManifest(
        queries: [XLDeclaredQuery],
        snapshotIdentifier: String,
        snapshotURL: URL,
        dialect: XLSQLiteDialect = XLSQLiteDialect()
    ) throws -> SQLiteBuildValidationManifest {
        let entries = try queryEntries(for: queries, dialect: dialect)
        let snapshotData = try Data(contentsOf: snapshotURL)

        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(
            path: snapshotURL.path,
            configuration: configuration
        )
        let runtime = try queue.read { database in
            try SQLiteBuildValidationRuntime.capture(from: database)
        }
        try queue.close()

        let manifest = SQLiteBuildValidationManifest(
            schemaSnapshot: SQLiteBuildValidationSchemaSnapshot(
                identifier: snapshotIdentifier,
                databaseSHA256: SQLiteBuildValidationSHA256.hexDigest(
                    of: snapshotData
                ),
                databaseByteCount: snapshotData.count,
                schemaRowCount: runtime.schemaRowCount,
                schemaFingerprint: runtime.schemaFNV1A64
            ),
            queries: entries
        )
        return try manifest.validating()
    }
}
