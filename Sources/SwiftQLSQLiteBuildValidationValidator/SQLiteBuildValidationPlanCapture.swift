import Foundation
import GRDB
import SwiftQLSQLiteBuildValidationManifest


/// Captures one normalised query plan per manifest entry, and diagnoses the
/// plan shapes that indicate avoidable work.
///
/// Runs on the same read-only/query-only connection that produced the run's
/// correctness evidence, after that evidence is complete. It adds data and
/// advice: nothing here reads, writes, or reinterprets a correctness verdict,
/// and no plan or diagnostic can fail a build.
public enum SQLiteBuildValidationPlanCapture {

    /// Captures plans, and diagnoses them, for every entry in `manifest`.
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
        settings: SQLiteBuildValidationPlanDiagnosticSettings = .init(),
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

        var rowCounts: [String: Int] = [:]
        var diagnostics: [SQLiteBuildValidationPlanDiagnostic] = []
        for (query, record) in zip(manifest.queries, records) {
            guard let roots = record.outcome.capturedRoots else {
                continue
            }
            for table in SQLiteBuildValidationPlanDiagnoser.tablesNeedingRowCounts(
                for: query,
                roots: roots
            ) where rowCounts[table] == nil {
                // A table this validator cannot count produces no scan
                // finding, rather than one resting on an assumed size.
                if let rowCount = rowCount(of: table, in: database) {
                    rowCounts[table] = rowCount
                }
            }
            diagnostics.append(contentsOf: SQLiteBuildValidationPlanDiagnoser.diagnostics(
                for: query,
                roots: roots,
                tableRowCounts: rowCounts,
                settings: settings
            ))
        }

        var planRoots: [String: [SQLiteBuildValidationPlanNode]] = [:]
        for record in records {
            planRoots[record.queryID] = record.outcome.capturedRoots
        }
        let candidates = SQLiteBuildValidationIndexCandidateGenerator.generate(
            queries: manifest.queries,
            planRoots: planRoots.compactMapValues { $0 },
            limits: settings.candidateLimits
        )

        let partitioned = SQLiteBuildValidationPlanDiagnoser.applying(
            suppressions: settings.suppressions,
            to: diagnostics
        )
        return SQLiteBuildValidationPlanReport(
            manifest: manifest,
            observedDatabaseByteCount: observedDatabaseByteCount,
            observedDatabaseSHA256: observedDatabaseSHA256,
            settings: settings,
            records: records,
            diagnostics: partitioned.reported,
            suppressedDiagnostics: partitioned.suppressed,
            unusedSuppressions: SQLiteBuildValidationPlanDiagnoser.unusedSuppressions(
                settings.suppressions,
                against: diagnostics
            ),
            indexCandidates: candidates
        )
    }

    /// Rows in `table`, or `nil` when the count cannot be taken.
    ///
    /// The identifier is quoted with SQLite's own doubling rule. Every name
    /// reaching this function came from the statement's own `FROM`/`JOIN`
    /// clauses, but the connection is the validator's and the quoting cost is
    /// nothing, so it is not left to the caller's provenance.
    private static func rowCount(of table: String, in database: Database) -> Int? {
        let quoted = "\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\""
        return try? Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(quoted)")
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
            // The type only. An arbitrary `Error`'s description can carry
            // localized or host-dependent text, and this artifact's bytes are
            // a determinism gate — a reason that differs between two hosts
            // running the same inputs would break it. Every failure this
            // probe raises itself is a `SQLiteExplainQueryPlanProbeError`,
            // caught above with its full stable message.
            return .unsupported(
                reason: "EXPLAIN QUERY PLAN failed with an error of type \(type(of: error))."
            )
        }
    }
}
