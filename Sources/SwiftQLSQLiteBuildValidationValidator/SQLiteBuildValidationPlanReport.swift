import Foundation
import SwiftQLSQLiteBuildValidationManifest


/// The plan sidecar: one normalised `EXPLAIN QUERY PLAN` record per manifest
/// entry, written beside — never inside — the canonical correctness report.
///
/// Keeping plans out of ``SQLiteBuildValidationReport`` is the #393 spike's
/// decision, and it is what makes "plan capture never changes a correctness
/// verdict" checkable rather than merely intended: the correctness report's
/// schema, its verdict semantics, and its bytes are untouched by anything in
/// this file.
///
/// Like the correctness report, this artifact retains no timestamp, host
/// identity, process identity, or path, and every list is ordered, so two
/// runs over unchanged inputs produce byte-identical output.
public struct SQLiteBuildValidationPlanReport: Codable, Equatable, Sendable {
    /// What a reader must not conclude from these plans.
    ///
    /// A constant, not rebuilt per report: it is the same list every time,
    /// and the report's bytes are a determinism gate.
    static let caveats: [String] = [
        "A plan captured on the build host is not a promise about the SQLite the application will run against; #390 measured a materialization strategy changing between two ordinary point releases.",
        "Parameters are left unbound, so on a snapshot that is both built with SQLITE_ENABLE_STAT4 and analyzed, a plan specialized to a bound value is not represented here.",
        "Plans are advisory evidence only. No plan record affects a correctness verdict or this validator's exit status.",
    ].sorted()

    public let formatVersion: Int
    public let manifestFormatVersion: Int
    public let conformanceInventoryVersion: String
    public let combinatorialManifestVersion: String
    public let schemaSnapshot: SQLiteBuildValidationSchemaSnapshot
    public let observedDatabaseByteCount: Int?
    public let observedDatabaseSHA256: String?
    public let caveats: [String]
    /// The thresholds and suppression rules this run diagnosed under.
    public let settings: SQLiteBuildValidationPlanDiagnosticSettings
    public let records: [SQLiteBuildValidationPlanRecord]
    /// Advisory findings that survived the checked-in suppressions.
    public let diagnostics: [SQLiteBuildValidationPlanDiagnostic]
    /// Findings a suppression silenced, kept with the reason the repository
    /// gave, so silencing a diagnostic leaves a trace.
    public let suppressedDiagnostics: [SQLiteBuildValidationSuppressedPlanDiagnostic]
    /// Suppression rules that silenced nothing, so a stale one can be found
    /// and deleted rather than quietly outliving the finding it was written
    /// for.
    public let unusedSuppressions: [SQLiteBuildValidationPlanSuppression]
    /// Proposed indices derived from the captured plans (#396).
    ///
    /// Proposals, not recommendations: nothing here has been tried against a
    /// database. Verification is #397's, and only a verified candidate may be
    /// reported as recommended.
    public let indexCandidates: SQLiteBuildValidationIndexCandidateSet

    public init(
        manifest: SQLiteBuildValidationManifest,
        observedDatabaseByteCount: Int?,
        observedDatabaseSHA256: String?,
        settings: SQLiteBuildValidationPlanDiagnosticSettings = .init(),
        records: [SQLiteBuildValidationPlanRecord],
        diagnostics: [SQLiteBuildValidationPlanDiagnostic] = [],
        suppressedDiagnostics: [SQLiteBuildValidationSuppressedPlanDiagnostic] = [],
        unusedSuppressions: [SQLiteBuildValidationPlanSuppression] = [],
        indexCandidates: SQLiteBuildValidationIndexCandidateSet = .init()
    ) {
        self.formatVersion = 1
        self.manifestFormatVersion = manifest.formatVersion.rawValue
        self.conformanceInventoryVersion = manifest.conformanceInventoryVersion
        self.combinatorialManifestVersion = manifest.combinatorialManifestVersion
        self.schemaSnapshot = manifest.schemaSnapshot
        self.observedDatabaseByteCount = observedDatabaseByteCount
        self.observedDatabaseSHA256 = observedDatabaseSHA256?.lowercased()
        self.caveats = Self.caveats
        self.settings = settings
        self.records = records.sorted { $0.queryID < $1.queryID }
        self.diagnostics = diagnostics.sorted(
            by: SQLiteBuildValidationPlanDiagnostic.canonicalOrder
        )
        self.suppressedDiagnostics = suppressedDiagnostics.sorted {
            SQLiteBuildValidationPlanDiagnostic.canonicalOrder($0.diagnostic, $1.diagnostic)
        }
        self.unusedSuppressions = unusedSuppressions.sorted(
            by: SQLiteBuildValidationPlanSuppression.canonicalOrder
        )
        self.indexCandidates = indexCandidates
    }

    /// The records whose plan SQLite actually produced.
    public var capturedRecords: [SQLiteBuildValidationPlanRecord] {
        records.filter { $0.outcome.capturedRoots != nil }
    }

    /// The records that name why no plan is available.
    public var unsupportedRecords: [SQLiteBuildValidationPlanRecord] {
        records.filter { $0.outcome.unsupportedReason != nil }
    }

    /// A plain-text rendering of the advisory findings, one per line.
    ///
    /// The canonical JSON is the artifact of record; this is what a run
    /// prints so an author sees the advice without opening the sidecar.
    /// Empty when there is nothing to advise.
    public func humanReadableSummary() -> String {
        guard !diagnostics.isEmpty else {
            return ""
        }
        return diagnostics.map { diagnostic in
            "swiftql-build-validate: advisory \(diagnostic.code.rawValue) in \(diagnostic.queryID): \(diagnostic.message)"
        }.joined(separator: "\n")
    }

    public func canonicalJSONData() throws -> Data {
        try SQLiteBuildValidationCanonicalJSON.encode(self)
    }

    public static func decode(contentsOf url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: try Data(contentsOf: url))
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case manifestFormatVersion = "manifest_format_version"
        case conformanceInventoryVersion = "conformance_inventory_version"
        case combinatorialManifestVersion = "combinatorial_manifest_version"
        case schemaSnapshot = "schema_snapshot"
        case observedDatabaseByteCount = "observed_database_byte_count"
        case observedDatabaseSHA256 = "observed_database_sha256"
        case caveats
        case settings
        case records
        case diagnostics
        case suppressedDiagnostics = "suppressed_diagnostics"
        case unusedSuppressions = "unused_suppressions"
        case indexCandidates = "index_candidates"
    }
}
