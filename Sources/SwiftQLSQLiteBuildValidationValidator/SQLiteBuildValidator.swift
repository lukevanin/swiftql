import Foundation
import GRDB
import SwiftQLCore
import SwiftQLSQLiteBuildValidationManifest


/// A standalone SQLite static-query build validator.
///
/// Consumes a deterministic ``SQLiteBuildValidationManifest`` (#292) and an
/// explicit checked-in SQLite snapshot, owns one dedicated read-only/
/// query-only connection for the run, prepares exactly one statement per
/// manifest entry with `sqlite3_prepare_v3`, and emits a deterministic
/// fail-closed report. Only `passed` is success; `failed` and `unsupported`
/// both fail the validation gate. No prepared statement escapes, persists,
/// or is reused at runtime — `SQLitePrepareV3Probe` returns copied Swift
/// values only, never a `sqlite3_stmt` pointer.
public enum SQLiteBuildValidator {
    /// Validates a manifest against a checked-in SQLite database file.
    ///
    /// This is the authoritative entry point: it owns a fresh read-only,
    /// query-only `DatabaseQueue` for the entire run, verifies the snapshot
    /// is byte-identical before and after validation, and refuses a
    /// snapshot with an adjacent `-journal`/`-shm`/`-wal` sidecar (evidence
    /// the file is not an immutable checked-in artifact).
    public static func validate(
        manifest: SQLiteBuildValidationManifest,
        againstDatabaseAt databaseURL: URL,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        let databaseURL = databaseURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        // Validation happens exactly once, inside the `in:` overload below —
        // this overload deliberately does not pre-validate `manifest` itself.
        let resourceValues = try databaseURL.resourceValues(
            forKeys: [.isRegularFileKey]
        )
        guard resourceValues.isRegularFile == true else {
            throw SQLiteBuildValidationValidatorError.databaseIsNotARegularFile(
                databaseURL.path
            )
        }
        try requireSidecarFreeSnapshot(at: databaseURL)
        let databaseData = try Data(
            contentsOf: databaseURL,
            options: .mappedIfSafe
        )
        let observedDatabaseSHA256 = SQLiteBuildValidationSHA256.hexDigest(
            of: databaseData
        )

        var configuration = Configuration()
        configuration.label = "SwiftQLSQLiteBuildValidationValidator"
        configuration.readonly = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA query_only = ON")
        }
        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: configuration
        )
        defer { try? queue.close() }

        let report = try queue.read { database in
            try validate(
                manifest: manifest,
                in: database,
                observedDatabaseByteCount: databaseData.count,
                observedDatabaseSHA256: observedDatabaseSHA256,
                environment: environment
            )
        }

        let finalDatabaseData = try Data(
            contentsOf: databaseURL,
            options: .mappedIfSafe
        )
        let finalDatabaseSHA256 = SQLiteBuildValidationSHA256.hexDigest(
            of: finalDatabaseData
        )
        try requireSidecarFreeSnapshot(at: databaseURL)
        guard finalDatabaseData.count == databaseData.count,
              finalDatabaseSHA256 == observedDatabaseSHA256 else {
            throw SQLiteBuildValidationValidatorError
                .databaseChangedDuringValidation(
                    initialByteCount: databaseData.count,
                    initialSHA256: observedDatabaseSHA256,
                    finalByteCount: finalDatabaseData.count,
                    finalSHA256: finalDatabaseSHA256
                )
        }
        return report
    }

    /// Validates on a caller-supplied connection. The URL overload is the
    /// authoritative path because it owns a read-only/query-only queue; this
    /// seam exists for callers that already own a validator-safe connection
    /// and must supply the database's byte count/SHA-256 evidence
    /// themselves — omitting either produces an `unsupported` schema
    /// diagnostic rather than a silent pass.
    public static func validate(
        manifest: SQLiteBuildValidationManifest,
        in database: Database,
        observedDatabaseByteCount: Int? = nil,
        observedDatabaseSHA256: String? = nil,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        let validatedManifest = try manifest.validating()

        // Before the runtime capture, so the capture sees these the way it sees
        // every other function on the connection. SQLite resolves a function
        // name at preparation, so a query using `REGEXP` cannot be prepared on
        // a connection that lacks the `regexp` SwiftQL supplies at runtime.
        SQLiteBuildValidationBundledFunctions.register(on: database)

        var runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
        let reportDiagnostics = schemaAndRuntimeDiagnostics(
            manifest: validatedManifest,
            in: database,
            observedDatabaseByteCount: observedDatabaseByteCount,
            observedDatabaseSHA256: observedDatabaseSHA256,
            environment: environment,
            runtimeMetadata: &runtimeMetadata
        )

        // A schema identity mismatch already fails the report outright
        // (`SQLiteBuildValidationReport.overallVerdict`), independent of
        // per-query outcomes. Once one is recorded, running every query
        // against a snapshot already known not to match the manifest is
        // pointless — skip preparation and emit one deterministic
        // `unsupported` outcome per manifest entry instead, so callers can
        // still see which queries were skipped.
        //
        // Matched by code, not just `stage == .schema && verdict == .failed`:
        // a future schema-stage check unrelated to snapshot identity would
        // otherwise silently trigger this short-circuit too.
        let hasSchemaIdentityMismatch = reportDiagnostics.contains { diagnostic in
            guard
                diagnostic.stage == .schema,
                diagnostic.verdict == .failed,
                let code = diagnostic.diagnosticCode
            else {
                return false
            }
            return SQLiteBuildValidationDiagnosticCode
                .schemaIdentityMismatch.contains(code)
        }
        let outcomes: [SQLiteBuildValidationQueryOutcome]
        if hasSchemaIdentityMismatch {
            outcomes = validatedManifest.queries.map { query in
                SQLiteBuildValidationQueryOutcome(
                    query: query,
                    placeholderAnalysis: SQLiteBuildValidationValidatorPlaceholderScanner.scan(query.sql),
                    preparedShape: nil,
                    diagnostics: [
                        SQLiteBuildValidationDiagnostic(
                            verdict: .unsupported,
                            stage: .schema,
                            code: .schemaMismatchSkipped,
                            message: "Query validation was skipped because the database snapshot's schema identity does not match the manifest.",
                            query: query
                        ),
                    ]
                )
            }
        } else {
            outcomes = validatedManifest.queries.map { query in
                validate(
                    query: query,
                    in: database,
                    runtimeMetadata: runtimeMetadata,
                    environment: environment
                )
            }
        }
        return SQLiteBuildValidationReport(
            manifest: validatedManifest,
            observedDatabaseByteCount: observedDatabaseByteCount,
            observedDatabaseSHA256: observedDatabaseSHA256,
            runtimeMetadata: runtimeMetadata,
            environmentEvidence: environment,
            diagnostics: reportDiagnostics,
            outcomes: outcomes
        )
    }
}
