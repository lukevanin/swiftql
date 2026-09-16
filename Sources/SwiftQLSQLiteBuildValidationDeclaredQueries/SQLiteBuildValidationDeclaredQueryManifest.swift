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
/// The `SwiftQLDeclaredQueryRegistryPlugin` build-tool plugin generates a
/// `<Target>DeclaredQueries` registry that lists every `@SQLQuery` and
/// `@SQLQueries` declaration in a target. Passing its queries here produces a
/// manifest with no hand-written query list, and a query added to the target
/// is in the next manifest.
///
/// Each query renders with the encoder of the database instance it was read
/// from, so the manifest carries the SQL that database runs.
///
/// Generation is not validation. The manifest this type returns has not been
/// checked against its snapshot; run ``SQLiteBuildValidator`` or the build
/// plugin for that.
///
public enum SQLiteBuildValidationDeclaredQueryManifest {

    /// A declared query that could not be lowered to a manifest entry.
    public struct SkippedQuery: Equatable, Sendable {

        /// The query's ``XLDeclaredQuery/id``.
        public let queryID: String

        /// Why the query was left out.
        public let reason: String
    }

    /// Manifest entries, and the queries that could not become one.
    public struct Projection {
        public let entries: [SQLiteBuildValidationQueryEntry]
        public let skippedQueries: [SkippedQuery]
    }

    /// A generated manifest, and the queries it leaves out.
    public struct GeneratedManifest {
        public let manifest: SQLiteBuildValidationManifest
        public let skippedQueries: [SkippedQuery]
    }

    ///
    /// One manifest entry per declared query, in the order given.
    ///
    /// Each entry is the `SQLiteBuildValidationQueryEntry(id:descriptor:declaredAliases:)`
    /// projection of the query's static descriptor, keyed by
    /// ``XLDeclaredQuery/id``. No entry carries a fixture reference.
    ///
    /// A query whose rows cannot be described statically -- its row reader
    /// reads raw dialect values the lowering reader cannot supply, or a
    /// result type's placeholder binds `NULL` -- is not guessed at. It is
    /// listed in ``Projection/skippedQueries`` with the reason, and the
    /// caller decides whether that fails its generation. Any other error,
    /// such as a declaration that disagrees with its rendered statement, is
    /// thrown.
    ///
    public static func queryEntries(
        for queries: [XLDeclaredQuery]
    ) throws -> Projection {
        var entries: [SQLiteBuildValidationQueryEntry] = []
        var skipped: [SkippedQuery] = []
        for query in queries {
            let lowered: XLLoweredDeclaredQuery
            do {
                lowered = try query.makeDescriptor()
            }
            catch let error as XLStaticRowReadError {
                skipped.append(SkippedQuery(
                    queryID: query.id,
                    reason: error.localizedDescription
                ))
                continue
            }
            catch let error as XLDeclaredQueryError {
                guard case .unknownStorageClass = error else {
                    throw error
                }
                skipped.append(SkippedQuery(
                    queryID: query.id,
                    reason: error.localizedDescription
                ))
                continue
            }
            entries.append(try SQLiteBuildValidationQueryEntry(
                id: lowered.id,
                descriptor: lowered.descriptor,
                declaredAliases: lowered.resultAliases
            ))
        }
        return Projection(entries: entries, skippedQueries: skipped)
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
    ///
    public static func makeManifest(
        queries: [XLDeclaredQuery],
        snapshotIdentifier: String,
        snapshotURL: URL
    ) throws -> GeneratedManifest {
        let projection = try queryEntries(for: queries)
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
            queries: projection.entries
        )
        return GeneratedManifest(
            manifest: try manifest.validating(),
            skippedQueries: projection.skippedQueries
        )
    }
}
