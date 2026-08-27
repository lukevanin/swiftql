import Foundation
import GRDB
import SwiftQLSQLiteBuildValidationManifest

//
//  Run-level evidence: that the connected database is the snapshot the
//  manifest was authored against, and what the connection's SQLite build
//  actually provides.
//
//  Split out of SQLiteBuildValidator.swift (#566).
//

extension SQLiteBuildValidator {

    /// Checks the connected database's identity against the manifest's schema
    /// snapshot and captures the connection's runtime evidence.
    ///
    /// A check that passes says nothing; a check that *could not run* says so
    /// rather than vanishing, because a check that silently did not happen is
    /// indistinguishable in the report from one that passed. So evidence the
    /// caller-owned seam did not supply, and the row-count and fingerprint
    /// checks when the runtime capture failed, each produce an `unsupported`
    /// diagnostic. The capture failure itself is a `failed` diagnostic -- that
    /// one is a fault, not an absence.
    ///
    /// - Parameter runtimeMetadata: Set to the captured evidence, or to `nil`
    ///   when capture failed. The caller needs it for per-query validation,
    ///   which is why it leaves through a parameter rather than the return
    ///   value.
    static func schemaAndRuntimeDiagnostics(
        manifest: SQLiteBuildValidationManifest,
        in database: Database,
        observedDatabaseByteCount: Int?,
        observedDatabaseSHA256: String?,
        environment: SQLiteBuildValidationEnvironment,
        runtimeMetadata: inout SQLiteBuildValidationRuntimeMetadata?
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if let observedDatabaseByteCount {
            if observedDatabaseByteCount != manifest.schemaSnapshot.databaseByteCount {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: .schemaByteCount,
                    message: "Observed database byte count is \(observedDatabaseByteCount); the manifest's schema snapshot declares \(manifest.schemaSnapshot.databaseByteCount)."
                ))
            }
        } else {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .schema,
                code: .schemaByteCount,
                message: "Schema snapshot byte count evidence was not supplied to the caller-owned validation seam."
            ))
        }
        if let observedDatabaseSHA256 {
            if observedDatabaseSHA256.lowercased() != manifest.schemaSnapshot.databaseSHA256 {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: .schemaSnapshotSHA,
                    message: "Observed database SHA-256 is \(observedDatabaseSHA256.lowercased()); the manifest's schema snapshot declares \(manifest.schemaSnapshot.databaseSHA256)."
                ))
            }
        } else {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .schema,
                code: .schemaSnapshotSHA,
                message: "Schema snapshot SHA-256 evidence was not supplied to the caller-owned validation seam."
            ))
        }

        do {
            runtimeMetadata = try SQLiteBuildValidationRuntime.capture(
                from: database,
                extensionNames: environment.extensionNames
            )
        } catch {
            runtimeMetadata = nil
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .runtime,
                code: .runtimeCapture,
                message: "SQLite runtime metadata capture failed with an unexpected \(String(reflecting: type(of: error)))."
            ))
        }

        if let runtimeMetadata {
            if runtimeMetadata.schemaRowCount != manifest.schemaSnapshot.schemaRowCount {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: .schemaRowCount,
                    message: "Observed sqlite_schema row count is \(runtimeMetadata.schemaRowCount); the manifest's schema snapshot declares \(manifest.schemaSnapshot.schemaRowCount)."
                ))
            }
            if runtimeMetadata.schemaFNV1A64 != manifest.schemaSnapshot.schemaFingerprint {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: .schemaFingerprint,
                    message: "Observed schema FNV-1a-64 is \(runtimeMetadata.schemaFNV1A64); the manifest's schema snapshot declares \(manifest.schemaSnapshot.schemaFingerprint)."
                ))
            }
        } else {
            // Capture failed above (`runtime.capture`), so these two checks
            // never ran — report them explicitly rather than letting them
            // vanish from the diagnostic set.
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .schema,
                code: .schemaRowCount,
                message: "Schema row count could not be checked because SQLite runtime metadata capture failed."
            ))
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .schema,
                code: .schemaFingerprint,
                message: "Schema fingerprint could not be checked because SQLite runtime metadata capture failed."
            ))
        }

        return diagnostics
    }
}
