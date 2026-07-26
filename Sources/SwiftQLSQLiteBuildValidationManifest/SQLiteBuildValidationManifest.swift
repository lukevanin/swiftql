import Foundation


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
public struct SQLiteBuildValidationManifest: Codable, Equatable, Sendable {

    public let formatVersion: SQLiteBuildValidationManifestFormatVersion
    public let conformanceInventoryVersion: String
    public let combinatorialManifestVersion: String
    public let schemaSnapshot: SQLiteBuildValidationSchemaSnapshot
    public let queries: [SQLiteBuildValidationQueryEntry]

    public init(
        formatVersion: SQLiteBuildValidationManifestFormatVersion = .current,
        conformanceInventoryVersion: String,
        combinatorialManifestVersion: String,
        schemaSnapshot: SQLiteBuildValidationSchemaSnapshot,
        queries: [SQLiteBuildValidationQueryEntry]
    ) {
        self.formatVersion = formatVersion
        self.conformanceInventoryVersion = conformanceInventoryVersion
        self.combinatorialManifestVersion = combinatorialManifestVersion
        self.schemaSnapshot = schemaSnapshot
        self.queries = queries.map { $0.normalized() }.sorted { $0.id < $1.id }
    }

    /// Decodes and structurally validates a manifest. Reference resolution
    /// against #190/#191/#254 is a separate step; see
    /// ``validating(against:)``.
    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data).validating()
    }

    public static func decode(contentsOf url: URL) throws -> Self {
        try decode(Data(contentsOf: url))
    }

    /// Structural, registry-independent validation.
    ///
    /// Fails closed on an unsupported format version, empty inventory
    /// versions, an invalid schema snapshot, duplicate query ids, malformed
    /// physical parameter slots, and incomplete codec metadata. This alone
    /// cannot detect an unresolved #190/#191/#254 reference, since resolving
    /// one requires external registry data not present in the manifest bytes.
    public func validating() throws -> Self {
        guard formatVersion == .current else {
            throw SQLiteBuildValidationManifestError.unsupportedFormatVersion(
                formatVersion
            )
        }
        guard !conformanceInventoryVersion.isEmpty else {
            throw SQLiteBuildValidationManifestError.invalidManifest(
                "conformance_inventory_version must not be empty"
            )
        }
        guard !combinatorialManifestVersion.isEmpty else {
            throw SQLiteBuildValidationManifestError.invalidManifest(
                "combinatorial_manifest_version must not be empty"
            )
        }
        guard !queries.isEmpty else {
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

        // Dictionary iteration order is not stable across processes, so pick
        // the lexicographically smallest duplicated id rather than `.first`
        // over an unordered grouping — the reported id must not vary between
        // runs of the same input.
        let duplicateQueryID = Dictionary(grouping: queries, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
            .first
        if let duplicateQueryID {
            throw SQLiteBuildValidationManifestError.duplicateQueryID(duplicateQueryID)
        }
        for query in queries {
            try Self.validateStructure(query)
        }
        return Self(
            formatVersion: formatVersion,
            conformanceInventoryVersion: conformanceInventoryVersion,
            combinatorialManifestVersion: combinatorialManifestVersion,
            schemaSnapshot: schemaSnapshot,
            queries: queries
        )
    }

    /// Exhaustive reference resolution against the real #190/#191/#254
    /// registries, in addition to structural validation.
    ///
    /// Every `conformance_feature_id`, `conformance_case_id`, and
    /// `northwind_anchor_case_id` in every query must resolve; an unresolved
    /// reference fails closed rather than passing silently.
    public func validating(
        against registry: some SQLiteBuildValidationReferenceRegistry
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
    /// byte-identical output. No timestamp, hostname, process ID, local path,
    /// or elapsed-time field exists anywhere in this schema.
    public func canonicalJSONData() throws -> Data {
        try SQLiteBuildValidationManifestCanonicalJSON.encode(validating())
    }

    private static func validateStructure(
        _ query: SQLiteBuildValidationQueryEntry
    ) throws {
        guard !query.id.isEmpty,
              !query.definitionIdentity.isEmpty,
              !query.descriptorIdentity.isEmpty,
              !query.dialectIdentifier.isEmpty else {
            throw SQLiteBuildValidationManifestError.invalidQuery(
                query.id,
                "query and descriptor identities must not be empty"
            )
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
                  !parameter.valueTypeName.isEmpty,
                  !parameter.storageIdentifier.isEmpty else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "parameter metadata must be contiguous and complete"
                )
            }
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

        for (offset, result) in query.results.enumerated() {
            guard result.index == offset,
                  !result.identity.isEmpty,
                  !result.valueTypeIdentifier.isEmpty,
                  !result.valueTypeName.isEmpty,
                  !result.storageIdentifier.isEmpty,
                  result.declaredAlias?.isEmpty != true else {
                throw SQLiteBuildValidationManifestError.invalidQuery(
                    query.id,
                    "result metadata must be contiguous and complete"
                )
            }
            try validateCodec(result.codec, queryID: query.id)
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
            $0.isNumber || ("a" ... "f").contains($0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case conformanceInventoryVersion = "conformance_inventory_version"
        case combinatorialManifestVersion = "combinatorial_manifest_version"
        case schemaSnapshot = "schema_snapshot"
        case queries
    }
}


enum SQLiteBuildValidationManifestCanonicalJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        while data.last == 0x0A {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }
}
