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
    public let records: [SQLiteBuildValidationPlanRecord]

    public init(
        manifest: SQLiteBuildValidationManifest,
        observedDatabaseByteCount: Int?,
        observedDatabaseSHA256: String?,
        records: [SQLiteBuildValidationPlanRecord]
    ) {
        self.formatVersion = 1
        self.manifestFormatVersion = manifest.formatVersion.rawValue
        self.conformanceInventoryVersion = manifest.conformanceInventoryVersion
        self.combinatorialManifestVersion = manifest.combinatorialManifestVersion
        self.schemaSnapshot = manifest.schemaSnapshot
        self.observedDatabaseByteCount = observedDatabaseByteCount
        self.observedDatabaseSHA256 = observedDatabaseSHA256?.lowercased()
        self.caveats = Self.caveats
        self.records = records.sorted { $0.queryID < $1.queryID }
    }

    /// The records whose plan SQLite actually produced.
    public var capturedRecords: [SQLiteBuildValidationPlanRecord] {
        records.filter { $0.outcome.capturedRoots != nil }
    }

    /// The records that name why no plan is available.
    public var unsupportedRecords: [SQLiteBuildValidationPlanRecord] {
        records.filter { $0.outcome.unsupportedReason != nil }
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
        case records
    }
}
