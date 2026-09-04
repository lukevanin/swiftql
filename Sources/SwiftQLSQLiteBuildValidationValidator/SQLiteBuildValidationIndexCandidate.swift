import Foundation


/// One column of a candidate index, with everything about it that affects
/// whether SQLite can use the index.
///
/// `direction` and `collation` are carried only where they were determined
/// from the statement. Both are `nil` for a column that came from an equality
/// or range predicate, where neither affects the seek.
public struct SQLiteBuildValidationIndexCandidateColumn:
    Codable,
    Equatable,
    Sendable
{
    public enum Direction: String, Codable, Equatable, Sendable {
        case ascending = "asc"
        case descending = "desc"
    }

    public let name: String
    public let direction: Direction?
    public let collation: String?

    public init(
        name: String,
        direction: Direction? = nil,
        collation: String? = nil
    ) {
        self.name = name
        self.direction = direction
        self.collation = collation
    }

    /// The column as it renders inside `CREATE INDEX (...)`.
    public var renderedDDL: String {
        var rendered = SQLiteBuildValidationIndexCandidate.quoted(name)
        if let collation {
            rendered += " COLLATE \(SQLiteBuildValidationIndexCandidate.quoted(collation))"
        }
        switch direction {
        case .ascending:
            rendered += " ASC"
        case .descending:
            rendered += " DESC"
        case nil:
            break
        }
        return rendered
    }

    /// A stable spelling used for deduplication and index naming.
    var canonicalKey: String {
        [name, direction?.rawValue ?? "", collation ?? ""].joined(separator: "\u{1}")
    }
}


/// A proposed index: a real table plus an ordered column list, ready to
/// render as `CREATE INDEX` DDL.
///
/// A candidate is a proposal, never a recommendation. Nothing here has been
/// tried against a database; verification is #397's, and only a verified
/// candidate may be reported as recommended.
public struct SQLiteBuildValidationIndexCandidate:
    Codable,
    Equatable,
    Sendable
{
    public let table: String
    public let columns: [SQLiteBuildValidationIndexCandidateColumn]
    /// Every manifest entry whose plan motivated this candidate, so a shared
    /// index is visibly shared.
    public let sourceQueryIDs: [String]
    /// The same statements by descriptor identity, which is the identity a
    /// developer's source declares.
    public let sourceDescriptorIdentities: [String]
    /// One concrete statement this candidate can be verified against.
    ///
    /// The lexicographically first source, not "whichever was found first":
    /// a representative chosen by discovery order would change with manifest
    /// ordering, and this artifact's bytes are a determinism gate.
    public let representativeQueryID: String
    /// The plan-node spelling of ``table`` in the representative statement.
    public let representativeAlias: String

    public init(
        table: String,
        columns: [SQLiteBuildValidationIndexCandidateColumn],
        sourceQueryIDs: [String],
        sourceDescriptorIdentities: [String],
        representativeQueryID: String,
        representativeAlias: String
    ) {
        self.table = table
        self.columns = columns
        self.sourceQueryIDs = Array(Set(sourceQueryIDs)).sorted()
        self.sourceDescriptorIdentities = Array(Set(sourceDescriptorIdentities)).sorted()
        self.representativeQueryID = representativeQueryID
        self.representativeAlias = representativeAlias
    }

    /// A stable, readable index name.
    ///
    /// Built from the lowercased table and column names with everything that
    /// is not a letter or digit folded to `_`. Folding can collide — a table
    /// with columns `a b` and `a_b` folds both to `a_b` — so when it is lossy
    /// the name carries a short digest of the exact identifiers, which
    /// restores uniqueness without making every ordinary name unreadable.
    public var indexName: String {
        let parts = [table] + columns.map(\.name)
        let folded = parts.map(Self.folded)
        let name = (["ix_advisor"] + folded).joined(separator: "_")
        guard folded != parts.map({ $0.lowercased() }) else {
            return name
        }
        return name + "_" + Self.shortDigest(of: canonicalKey)
    }

    public var ddl: String {
        let columnList = columns.map(\.renderedDDL).joined(separator: ", ")
        return "CREATE INDEX \(Self.quoted(indexName)) ON \(Self.quoted(table)) (\(columnList))"
    }

    /// The identity two candidates are deduplicated on.
    var canonicalKey: String {
        ([table] + columns.map(\.canonicalKey)).joined(separator: "\u{0}")
    }

    /// Quotes a SQL identifier, doubling any embedded `"` per SQLite's own
    /// rule. Identifiers reaching here were parsed out of the manifest's own
    /// SQL, but this DDL is handed to `Database.execute` during verification,
    /// so an unescaped quote could otherwise break out of the identifier.
    static func quoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func folded(_ identifier: String) -> String {
        String(identifier.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    private static func shortDigest(of value: String) -> String {
        String(SQLiteBuildValidationSHA256.hexDigest(of: Data(value.utf8)).prefix(8))
    }

    static func canonicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.table != rhs.table {
            return lhs.table < rhs.table
        }
        return lhs.columns.map(\.canonicalKey)
            .lexicographicallyPrecedes(rhs.columns.map(\.canonicalKey))
    }

    /// Encodes the derived ``indexName`` and ``ddl`` alongside the stored
    /// fields, and ignores them when decoding.
    ///
    /// They are redundant to a Swift reader, which can recompute both. They
    /// are not redundant to anything else: the plan sidecar is read by a build
    /// log, by the `swiftql-index-advisor` command, and by whoever opens the
    /// JSON, and a candidate that does not carry its own `CREATE INDEX`
    /// statement makes every one of those re-derive SQLite's quoting rules.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(table, forKey: .table)
        try container.encode(columns, forKey: .columns)
        try container.encode(sourceQueryIDs, forKey: .sourceQueryIDs)
        try container.encode(
            sourceDescriptorIdentities,
            forKey: .sourceDescriptorIdentities
        )
        try container.encode(representativeQueryID, forKey: .representativeQueryID)
        try container.encode(representativeAlias, forKey: .representativeAlias)
        try container.encode(indexName, forKey: .indexName)
        try container.encode(ddl, forKey: .ddl)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            table: try container.decode(String.self, forKey: .table),
            columns: try container.decode(
                [SQLiteBuildValidationIndexCandidateColumn].self,
                forKey: .columns
            ),
            sourceQueryIDs: try container.decode([String].self, forKey: .sourceQueryIDs),
            sourceDescriptorIdentities: try container.decode(
                [String].self,
                forKey: .sourceDescriptorIdentities
            ),
            representativeQueryID: try container.decode(
                String.self,
                forKey: .representativeQueryID
            ),
            representativeAlias: try container.decode(
                String.self,
                forKey: .representativeAlias
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case table
        case columns
        case sourceQueryIDs = "source_query_ids"
        case sourceDescriptorIdentities = "source_descriptor_identities"
        case representativeQueryID = "representative_query_id"
        case representativeAlias = "representative_alias"
        case indexName = "index_name"
        case ddl
    }
}


/// A bound the candidate generator hit, reported rather than applied
/// silently.
///
/// A truncated candidate set that says nothing about being truncated reads as
/// a complete answer, which is the one thing it is not.
public struct SQLiteBuildValidationIndexCandidateTruncation:
    Codable,
    Equatable,
    Sendable
{
    public enum Kind: String, Codable, Equatable, Sendable {
        case columns
        case candidatesPerStatement = "candidates_per_statement"
        case candidatesPerTable = "candidates_per_table"
    }

    public let kind: Kind
    public let queryID: String?
    public let table: String?
    public let limit: Int
    public let observed: Int

    public init(
        kind: Kind,
        queryID: String? = nil,
        table: String? = nil,
        limit: Int,
        observed: Int
    ) {
        self.kind = kind
        self.queryID = queryID
        self.table = table
        self.limit = limit
        self.observed = observed
    }

    static func canonicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        [lhs.kind.rawValue, lhs.queryID ?? "", lhs.table ?? "", String(lhs.observed)]
            .lexicographicallyPrecedes(
                [rhs.kind.rawValue, rhs.queryID ?? "", rhs.table ?? "", String(rhs.observed)]
            )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case queryID = "query_id"
        case table
        case limit
        case observed
    }
}


/// A remediable plan node this generator declined to propose a candidate for,
/// and why.
///
/// Declining is the correct answer whenever the statement cannot be read with
/// confidence. Recording it keeps "no candidate" distinguishable from "no
/// problem".
public struct SQLiteBuildValidationIndexCandidateDecline:
    Codable,
    Equatable,
    Sendable
{
    public let queryID: String
    public let alias: String
    public let table: String?
    public let reason: String

    public init(queryID: String, alias: String, table: String?, reason: String) {
        self.queryID = queryID
        self.alias = alias
        self.table = table
        self.reason = reason
    }

    static func canonicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        [lhs.queryID, lhs.alias, lhs.table ?? "", lhs.reason]
            .lexicographicallyPrecedes(
                [rhs.queryID, rhs.alias, rhs.table ?? "", rhs.reason]
            )
    }

    private enum CodingKeys: String, CodingKey {
        case queryID = "query_id"
        case alias
        case table
        case reason
    }
}


/// The stated bounds on how much advice one run will produce.
public struct SQLiteBuildValidationIndexCandidateLimits:
    Codable,
    Equatable,
    Sendable
{
    /// Past a handful of columns an index stops paying for itself: it is
    /// wider on disk, slower to maintain, and SQLite stops narrowing at the
    /// first range column anyway.
    public static let defaultMaximumColumns = 6
    public static let defaultMaximumCandidatesPerStatement = 4
    public static let defaultMaximumCandidatesPerTable = 4

    public let maximumColumns: Int
    public let maximumCandidatesPerStatement: Int
    public let maximumCandidatesPerTable: Int

    public init(
        maximumColumns: Int = SQLiteBuildValidationIndexCandidateLimits.defaultMaximumColumns,
        maximumCandidatesPerStatement: Int = SQLiteBuildValidationIndexCandidateLimits
            .defaultMaximumCandidatesPerStatement,
        maximumCandidatesPerTable: Int = SQLiteBuildValidationIndexCandidateLimits
            .defaultMaximumCandidatesPerTable
    ) {
        self.maximumColumns = maximumColumns
        self.maximumCandidatesPerStatement = maximumCandidatesPerStatement
        self.maximumCandidatesPerTable = maximumCandidatesPerTable
    }

    private enum CodingKeys: String, CodingKey {
        case maximumColumns = "maximum_columns"
        case maximumCandidatesPerStatement = "maximum_candidates_per_statement"
        case maximumCandidatesPerTable = "maximum_candidates_per_table"
    }
}


/// Everything one run's candidate generation produced.
public struct SQLiteBuildValidationIndexCandidateSet:
    Codable,
    Equatable,
    Sendable
{
    public let limits: SQLiteBuildValidationIndexCandidateLimits
    public let candidates: [SQLiteBuildValidationIndexCandidate]
    public let truncations: [SQLiteBuildValidationIndexCandidateTruncation]
    public let declines: [SQLiteBuildValidationIndexCandidateDecline]

    public init(
        limits: SQLiteBuildValidationIndexCandidateLimits = .init(),
        candidates: [SQLiteBuildValidationIndexCandidate] = [],
        truncations: [SQLiteBuildValidationIndexCandidateTruncation] = [],
        declines: [SQLiteBuildValidationIndexCandidateDecline] = []
    ) {
        self.limits = limits
        self.candidates = candidates.sorted(
            by: SQLiteBuildValidationIndexCandidate.canonicalOrder
        )
        self.truncations = truncations.sorted(
            by: SQLiteBuildValidationIndexCandidateTruncation.canonicalOrder
        )
        self.declines = declines.sorted(
            by: SQLiteBuildValidationIndexCandidateDecline.canonicalOrder
        )
    }
}
