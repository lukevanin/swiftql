import Foundation
import GRDB
import SwiftQLSQLiteBuildValidationManifest


/// Captures one normalised query plan per manifest entry.
///
/// Runs on the same read-only/query-only connection that produced the run's
/// correctness evidence, after that evidence is complete. It adds data and
/// makes no judgement: nothing here reads, writes, or reinterprets a
/// correctness verdict, and no plan can fail a build.
public enum SQLiteBuildValidationPlanCapture {

    /// Captures plans for every entry in `manifest`.
    ///
    /// `skippedReason`, when present, is the single explicit reason every
    /// entry is unsupported — the caller has already established that
    /// planning against this snapshot would be meaningless. The alternative,
    /// capturing plans against a snapshot whose schema does not match the
    /// manifest, would produce records that look like evidence and are not.
    public static func capture(
        manifest: SQLiteBuildValidationManifest,
        in database: Database,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?,
        observedDatabaseByteCount: Int?,
        observedDatabaseSHA256: String?,
        skippedReason: String? = nil
    ) -> SQLiteBuildValidationPlanReport {
        let provenance = runtimeMetadata.map(SQLiteBuildValidationPlanProvenance.init)
        let records = manifest.queries.map { query in
            record(
                for: query,
                in: database,
                provenance: provenance,
                skippedReason: skippedReason
            )
        }
        return SQLiteBuildValidationPlanReport(
            manifest: manifest,
            observedDatabaseByteCount: observedDatabaseByteCount,
            observedDatabaseSHA256: observedDatabaseSHA256,
            records: records
        )
    }

    private static func record(
        for query: SQLiteBuildValidationQueryEntry,
        in database: Database,
        provenance: SQLiteBuildValidationPlanProvenance?,
        skippedReason: String?
    ) -> SQLiteBuildValidationPlanRecord {
        SQLiteBuildValidationPlanRecord(
            queryID: query.id,
            definitionIdentity: query.definitionIdentity,
            descriptorIdentity: query.descriptorIdentity,
            provenance: provenance,
            outcome: outcome(
                for: query,
                in: database,
                hasProvenance: provenance != nil,
                skippedReason: skippedReason
            )
        )
    }

    private static func outcome(
        for query: SQLiteBuildValidationQueryEntry,
        in database: Database,
        hasProvenance: Bool,
        skippedReason: String?
    ) -> SQLiteBuildValidationPlanCaptureOutcome {
        if let skippedReason {
            return .unsupported(reason: skippedReason)
        }
        guard hasProvenance else {
            return .unsupported(
                reason: "The run could not read the connection's SQLite version, source ID, and compile options, so a captured plan could not name the build that produced it."
            )
        }
        do {
            let rows = try SQLiteExplainQueryPlanProbe.rows(
                forSQL: query.sql,
                in: database
            )
            return .captured(
                roots: SQLiteBuildValidationPlanShapeClassifier.classify(rows: rows)
            )
        } catch let error as SQLiteExplainQueryPlanProbeError {
            return .unsupported(reason: error.description)
        } catch {
            return .unsupported(
                reason: "EXPLAIN QUERY PLAN failed: \(String(describing: error))"
            )
        }
    }
}
