import Foundation
import SwiftQLCore


/// A versioned, deterministic sidecar for static SwiftQL query descriptors.
///
/// The manifest fills reproducible-build fields that intentionally do not
/// belong in the frozen `XLQueryIdentity` v1 representation: physical
/// placeholder positions, declared result aliases, pinned schema-snapshot
/// identity, and cross-references into the #190 conformance inventory, #191
/// combinatorial cases, and #254 Northwind anchors. Descriptor fields remain
/// authoritative; this is a sidecar, not a second structural query model, and
/// it performs no SQLite database I/O — that is the standalone validator's
/// responsibility (#293).
///
/// See ``SQLiteBuildValidationManifestFormatVersion`` for what each format
/// version requires.
public struct SQLiteBuildValidationManifest: Codable, Equatable, Sendable {

    public let formatVersion: SQLiteBuildValidationManifestFormatVersion
    /// The #190 `inventory_version` the manifest was authored against, or
    /// `nil` when it was not authored against SwiftQL's fixtures. Required in
    /// format version 1.
    public let conformanceInventoryVersion: String?
    /// The #191 `generator_version` the manifest was authored against, or
    /// `nil` when it was not authored against SwiftQL's fixtures. Required in
    /// format version 1.
    public let combinatorialManifestVersion: String?
    public let schemaSnapshot: SQLiteBuildValidationSchemaSnapshot
    public let queries: [SQLiteBuildValidationQueryEntry]

    public init(
        formatVersion: SQLiteBuildValidationManifestFormatVersion = .current,
        conformanceInventoryVersion: String? = nil,
        combinatorialManifestVersion: String? = nil,
        schemaSnapshot: SQLiteBuildValidationSchemaSnapshot,
        queries: [SQLiteBuildValidationQueryEntry]
    ) {
        self.formatVersion = formatVersion
        self.conformanceInventoryVersion = conformanceInventoryVersion
        self.combinatorialManifestVersion = combinatorialManifestVersion
        self.schemaSnapshot = schemaSnapshot
        self.queries = queries.map { $0.normalized() }.sorted { $0.id < $1.id }
    }

    /// Decodes a manifest's JSON object.
    ///
    /// Reads `format_version` before anything else and fails with
    /// ``SQLiteBuildValidationManifestError/unsupportedFormatVersion(_:)``
    /// when this reader does not know it, whatever the rest of the document
    /// contains. An unknown key at any level fails with
    /// ``SQLiteBuildValidationManifestError/unknownKey(path:)``. Stored values
    /// are kept as written; ``validating()`` canonicalizes and checks them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let formatVersion = try container.decode(
            SQLiteBuildValidationManifestFormatVersion.self,
            forKey: .formatVersion
        )
        guard formatVersion.isSupported else {
            throw SQLiteBuildValidationManifestError.unsupportedFormatVersion(formatVersion)
        }
        try sqliteBuildValidationManifestRejectUnknownKeys(
            in: decoder,
            allowedKeys: CodingKeys.self
        )
        self.formatVersion = formatVersion
        self.conformanceInventoryVersion = try container.decodeIfPresent(
            String.self,
            forKey: .conformanceInventoryVersion
        )
        self.combinatorialManifestVersion = try container.decodeIfPresent(
            String.self,
            forKey: .combinatorialManifestVersion
        )
        self.schemaSnapshot = try container.decode(
            SQLiteBuildValidationSchemaSnapshot.self,
            forKey: .schemaSnapshot
        )
        self.queries = try container.decode(
            [SQLiteBuildValidationQueryEntry].self,
            forKey: .queries
        )
    }

    /// Decodes and structurally validates a manifest. Reference resolution
    /// against #190/#191/#254 is a separate step; see
    /// ``validating(against:)``.
    ///
    /// `format_version` is decoded alone first, so a document in an unknown
    /// version reports that version rather than a decoding error from a body
    /// shape this reader does not know.
    public static func decode(_ data: Data) throws -> Self {
        let formatVersion = SQLiteBuildValidationManifestFormatVersion(
            rawValue: try SQLiteBuildValidationFormatVersionProbe.decode(data)
        )
        guard formatVersion.isSupported else {
            throw SQLiteBuildValidationManifestError.unsupportedFormatVersion(formatVersion)
        }
        return try JSONDecoder().decode(Self.self, from: data).validating()
    }

    public static func decode(contentsOf url: URL) throws -> Self {
        try decode(Data(contentsOf: url))
    }

    /// Structural, registry-independent validation.
    ///
    /// Fails closed on an unsupported format version, an invalid schema
    /// snapshot, duplicate query ids, malformed physical parameter slots, and
    /// incomplete codec metadata. Format version 1 also requires both
    /// inventory versions, at least one query, and `value_type_name` on every
    /// slot. Format version 2 accepts their absence, but still rejects an
    /// empty string where one is present, and rejects a #190 feature or #191
    /// case reference when the matching inventory version is absent. This
    /// alone cannot detect an unresolved #190/#191/#254 reference, since
    /// resolving one requires external registry data not present in the
    /// manifest bytes.
    public func validating() throws -> Self {
        guard formatVersion.isSupported else {
            throw SQLiteBuildValidationManifestError.unsupportedFormatVersion(
                formatVersion
            )
        }
        let requiresFixtureProvenance = formatVersion == .v1
        try Self.validateProvenance(
            conformanceInventoryVersion,
            key: "conformance_inventory_version",
            required: requiresFixtureProvenance
        )
        try Self.validateProvenance(
            combinatorialManifestVersion,
            key: "combinatorial_manifest_version",
            required: requiresFixtureProvenance
        )
        guard !requiresFixtureProvenance || !queries.isEmpty else {
            throw SQLiteBuildValidationManifestError.invalidManifest(
                "queries must not be empty"
            )
        }
        guard !schemaSnapshot.identifier.isEmpty,
              schemaSnapshot.databaseByteCount > 0,
              schemaSnapshot.schemaRowCount > 0,
              Self.isLowercaseHex(schemaSnapshot.databaseSHA256, count: 64),
              Self.isLowercaseHex(schemaSnapshot.schemaFingerprint, count: 16) else {
            throw SQLiteBuildValidationManifestError.invalidManifest(
                "schema snapshot identifier, byte count, row count, SHA-256, and fingerprint are required"
            )
        }

        // A decoded manifest keeps its stored values exactly as written and
        // never calls the canonicalizing memberwise initializer below, so it
        // may still have unsorted/undeduplicated queries, parameters,
        // results, or id-set fields even though it is otherwise semantically
        // valid. Re-normalize before running structural checks against it so
        // a reordered-but-valid manifest doesn't spuriously fail contiguity
        // checks that assume canonical ordering.
        let normalizedQueries = Self(
            formatVersion: formatVersion,
            conformanceInventoryVersion: conformanceInventoryVersion,
            combinatorialManifestVersion: combinatorialManifestVersion,
            schemaSnapshot: schemaSnapshot,
            queries: queries
        ).queries

        // Dictionary iteration order is not stable across processes, so pick
        // the lexicographically smallest duplicated id rather than `.first`
        // over an unordered grouping — the reported id must not vary between
        // runs of the same input.
        let duplicateQueryID = Dictionary(grouping: normalizedQueries, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
            .first
        if let duplicateQueryID {
            throw SQLiteBuildValidationManifestError.duplicateQueryID(duplicateQueryID)
        }
        for query in normalizedQueries {
            try Self.validateStructure(
                query,
                requiresValueTypeName: requiresFixtureProvenance
            )
            // A fixture reference with no recorded fixture version cannot be
            // traced to the inventory it was authored against.
            if conformanceInventoryVersion == nil, !query.conformanceFeatureIDs.isEmpty {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "conformance_feature_ids require conformance_inventory_version"
                )
            }
            if combinatorialManifestVersion == nil, !query.conformanceCaseIDs.isEmpty {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "conformance_case_ids require combinatorial_manifest_version"
                )
            }
        }
        return Self(
            formatVersion: formatVersion,
            conformanceInventoryVersion: conformanceInventoryVersion,
            combinatorialManifestVersion: combinatorialManifestVersion,
            schemaSnapshot: schemaSnapshot,
            queries: normalizedQueries
        )
    }

    /// Exhaustive reference resolution against the real #190/#191/#254
    /// registries, in addition to structural validation.
    ///
    /// Every `conformance_feature_id`, `conformance_case_id`, and
    /// `northwind_anchor_case_id` in every query must resolve; an unresolved
    /// reference fails closed rather than passing silently.
    public func validating(
        against registry: any SQLiteBuildValidationReferenceRegistry
    ) throws -> Self {
        let validated = try validating()
        for query in validated.queries {
            for featureID in query.conformanceFeatureIDs
            where !registry.resolvesConformanceFeatureID(featureID) {
                throw SQLiteBuildValidationManifestError.unresolvedReference(
                    queryID: query.id,
                    kind: .conformanceFeature,
                    id: featureID
                )
            }
            for caseID in query.conformanceCaseIDs
            where !registry.resolvesConformanceCaseID(caseID) {
                throw SQLiteBuildValidationManifestError.unresolvedReference(
                    queryID: query.id,
                    kind: .conformanceCase,
                    id: caseID
                )
            }
            for anchorID in query.northwindAnchorCaseIDs
            where !registry.resolvesNorthwindAnchorCaseID(anchorID) {
                throw SQLiteBuildValidationManifestError.unresolvedReference(
                    queryID: query.id,
                    kind: .northwindAnchor,
                    id: anchorID
                )
            }
        }
        return validated
    }

    /// Canonical JSON: pretty-printed, sorted keys, exactly one trailing
    /// newline. Set-like fields and the query list are sorted at construction
    /// time, so two manifests with the same reordered content encode to
    /// byte-identical output. An absent optional field is omitted rather than
    /// written as `null`, so a version 1 manifest encodes exactly as it did
    /// before version 2 existed. No timestamp, hostname, process ID, local
    /// path, or elapsed-time field exists anywhere in this schema.
    public func canonicalJSONData() throws -> Data {
        try SQLiteBuildValidationCanonicalJSON.encode(validating())
    }

    private static func validateProvenance(
        _ value: String?,
        key: String,
        required: Bool
    ) throws {
        switch value {
        case .none where required:
            throw SQLiteBuildValidationManifestError.invalidManifest(
                "\(key) must not be empty"
            )
        case .some(let version) where version.isEmpty:
            throw SQLiteBuildValidationManifestError.invalidManifest(
                required
                    ? "\(key) must not be empty"
                    : "\(key) must be omitted or nonempty"
            )
        default:
            return
        }
    }

    private static func validateStructure(
        _ query: SQLiteBuildValidationQueryEntry,
        requiresValueTypeName: Bool
    ) throws {
        guard !query.id.isEmpty,
              !query.definitionIdentity.isEmpty,
              !query.descriptorIdentity.isEmpty,
              !query.dialectIdentifier.isEmpty,
              !query.sql.isEmpty else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                query.id,
                "query identities and SQL must not be empty"
            )
        }
        guard let cardinality = XLQueryCardinality(rawValue: query.cardinality) else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                query.id,
                "cardinality \(query.cardinality) is not a recognized XLQueryCardinality raw value"
            )
        }
        switch cardinality {
        case .command:
            guard query.results.isEmpty else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "command cardinality must not declare result slots"
                )
            }
        case .exactlyOne, .zeroOrOne, .many:
            guard !query.results.isEmpty else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "row cardinality requires at least one result slot"
                )
            }
        }
        guard !query.conformanceFeatureIDs.contains(where: \.isEmpty),
              !query.conformanceCaseIDs.contains(where: \.isEmpty),
              !query.northwindAnchorCaseIDs.contains(where: \.isEmpty),
              !query.requiredCapabilities.contains(where: { $0.id.isEmpty }) else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                query.id,
                "reference and capability identifiers must not be empty"
            )
        }

        for (offset, parameter) in query.parameters.enumerated() {
            guard parameter.logicalIndex == offset,
                  parameter.physicalIndex > 0,
                  !parameter.identity.isEmpty,
                  !parameter.valueTypeIdentifier.isEmpty,
                  isValidValueTypeName(
                      parameter.valueTypeName,
                      required: requiresValueTypeName
                  ),
                  !parameter.storageIdentifier.isEmpty else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "parameter metadata must be contiguous and complete"
                )
            }
            try validateNullability(parameter.nullability, queryID: query.id)
            switch parameter.keyKind {
            case .named:
                guard let name = parameter.keyName, !name.isEmpty,
                      parameter.keyIndex == nil else {
                    throw SQLiteBuildValidationManifestError.invalidQuery(
                        query.id,
                        "named parameters require key_name and no key_index"
                    )
                }
            case .indexed:
                guard parameter.keyName == nil,
                      let index = parameter.keyIndex,
                      index >= 0,
                      parameter.physicalIndex == index + 1 else {
                    throw SQLiteBuildValidationManifestError.invalidQuery(
                        query.id,
                        "indexed parameters require a nonnegative key_index matching physical_index"
                    )
                }
            }
            try validateCodec(parameter.codec, queryID: query.id)
        }
        guard Set(query.parameters.map(\.physicalIndex)).count
                == query.parameters.count else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                query.id,
                "logical parameters must not share a physical SQLite slot"
            )
        }
        try validatePlaceholders(for: query)

        for (offset, result) in query.results.enumerated() {
            guard result.index == offset,
                  !result.identity.isEmpty,
                  !result.valueTypeIdentifier.isEmpty,
                  isValidValueTypeName(
                      result.valueTypeName,
                      required: requiresValueTypeName
                  ),
                  !result.storageIdentifier.isEmpty,
                  result.declaredAlias?.isEmpty != true else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "result metadata must be contiguous and complete"
                )
            }
            try validateNullability(result.nullability, queryID: query.id)
            try validateCodec(result.codec, queryID: query.id)
        }
    }

    /// Format version 1 requires a nonempty `value_type_name`. Version 2
    /// accepts its absence, but an empty string is never a type name.
    private static func isValidValueTypeName(
        _ valueTypeName: String?,
        required: Bool
    ) -> Bool {
        guard let valueTypeName else {
            return !required
        }
        return !valueTypeName.isEmpty
    }

    /// Cross-checks declared parameter metadata against the placeholders
    /// actually present in `query.sql`. This is the check the `init(id:
    /// descriptor:...)` projection satisfies by construction (it derives
    /// physical indices from the same scanner) but that an externally
    /// authored or hand-edited manifest — decoded straight from JSON — is
    /// not otherwise forced to satisfy. Without it, a manifest could declare
    /// a parameter absent from its own SQL, omit one the SQL actually uses,
    /// or assign it a physical index SQLite's first-encounter placeholder
    /// ordering would not produce, and still pass structural validation.
    private static func validatePlaceholders(
        for query: SQLiteBuildValidationQueryEntry
    ) throws {
        let placeholders = SQLiteBuildValidationManifestPlaceholderScanner.scan(
            query.sql
        )
        let scannedPhysicalIndices = Set(placeholders.occurrences.map(\.physicalIndex))
        let declaredPhysicalIndices = Set(query.parameters.map(\.physicalIndex))
        guard scannedPhysicalIndices == declaredPhysicalIndices else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                query.id,
                "declared parameter physical indices \(declaredPhysicalIndices.sorted()) do not match the placeholders found in SQL \(scannedPhysicalIndices.sorted())"
            )
        }
        for parameter in query.parameters {
            guard let occurrence = placeholders.occurrences.first(where: {
                $0.physicalIndex == parameter.physicalIndex
            }), occurrence.spelling == parameter.expectedSQLiteSpelling else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "parameter at physical index \(parameter.physicalIndex) declares spelling '\(parameter.expectedSQLiteSpelling)', which does not match its placeholder occurrence in SQL"
                )
            }
        }
    }

    private static func validateNullability(
        _ nullability: String,
        queryID: String
    ) throws {
        guard XLParameterNullability(rawValue: nullability) != nil else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                queryID,
                "nullability '\(nullability)' is not a recognized XLParameterNullability raw value"
            )
        }
    }

    private static func validateCodec(
        _ codec: SQLiteBuildValidationCodecReference?,
        queryID: String
    ) throws {
        guard let codec else {
            return
        }
        guard !codec.keyID.isEmpty,
              !codec.valueTypeIdentifier.isEmpty,
              !codec.dialectIdentifier.isEmpty,
              !codec.storageIdentifier.isEmpty else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                queryID,
                "codec metadata must be complete"
            )
        }
    }

    private static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.allSatisfy {
            ("0" ... "9").contains($0) || ("a" ... "f").contains($0)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case formatVersion = "format_version"
        case conformanceInventoryVersion = "conformance_inventory_version"
        case combinatorialManifestVersion = "combinatorial_manifest_version"
        case schemaSnapshot = "schema_snapshot"
        case queries
    }
}
