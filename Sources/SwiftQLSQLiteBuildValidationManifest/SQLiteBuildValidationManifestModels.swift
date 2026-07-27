import Foundation
import SwiftQLCore


/// The pinned, checked-in SQLite database a manifest's queries validate against.
///
/// Byte identity (`databaseSHA256`) is authoritative. `schemaFingerprint` is
/// exact runtime provenance evidence (it includes root pages and raw schema
/// SQL) and must not be treated as a semantic migration or catalog fingerprint.
public struct SQLiteBuildValidationSchemaSnapshot: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case checkedInSnapshot = "checked-in-snapshot"
    }

    public let kind: Kind
    public let identifier: String
    public let databaseSHA256: String
    public let databaseByteCount: Int
    public let schemaRowCount: Int
    public let schemaFingerprint: String

    public init(
        kind: Kind = .checkedInSnapshot,
        identifier: String,
        databaseSHA256: String,
        databaseByteCount: Int,
        schemaRowCount: Int,
        schemaFingerprint: String
    ) {
        self.kind = kind
        self.identifier = identifier
        self.databaseSHA256 = databaseSHA256.lowercased()
        self.databaseByteCount = databaseByteCount
        self.schemaRowCount = schemaRowCount
        self.schemaFingerprint = schemaFingerprint.lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case identifier
        case databaseSHA256 = "database_sha256"
        case databaseByteCount = "database_byte_count"
        case schemaRowCount = "schema_row_count"
        case schemaFingerprint = "schema_fingerprint"
    }
}


/// A JSON-friendly projection of ``XLValueCodecIdentity``.
public struct SQLiteBuildValidationCodecReference:
    Codable,
    Equatable,
    Hashable,
    Sendable
{

    public let keyID: String
    public let keyVersion: UInt
    public let valueTypeIdentifier: String
    public let dialectIdentifier: String
    public let storageIdentifier: String

    public init(
        keyID: String,
        keyVersion: UInt,
        valueTypeIdentifier: String,
        dialectIdentifier: String,
        storageIdentifier: String
    ) {
        self.keyID = keyID
        self.keyVersion = keyVersion
        self.valueTypeIdentifier = valueTypeIdentifier
        self.dialectIdentifier = dialectIdentifier
        self.storageIdentifier = storageIdentifier
    }

    public init(_ identity: XLValueCodecIdentity) {
        self.init(
            keyID: identity.key.id,
            keyVersion: identity.key.version,
            valueTypeIdentifier: identity.valueTypeIdentifier.rawValue,
            dialectIdentifier: identity.dialectIdentifier.rawValue,
            storageIdentifier: identity.storageIdentifier.rawValue
        )
    }

    /// Stable spelling for diagnostics and required-codec summaries. The
    /// sidecar retains the structured fields; this is only a convenience.
    public var stableIdentifier: String {
        "\(keyID)@\(keyVersion)|\(valueTypeIdentifier)|\(dialectIdentifier)|\(storageIdentifier)"
    }

    private enum CodingKeys: String, CodingKey {
        case keyID = "key_id"
        case keyVersion = "key_version"
        case valueTypeIdentifier = "value_type_identifier"
        case dialectIdentifier = "dialect_identifier"
        case storageIdentifier = "storage_identifier"
    }
}


/// A required engine capability referenced by stable identifier (for example
/// `function:FLOOR`). Capability evidence itself belongs to the validator (#293).
public struct SQLiteBuildValidationCapabilityReference:
    Codable,
    Equatable,
    Hashable,
    Sendable
{

    public let id: String

    public init(id: String) {
        self.id = id
    }
}


/// Sidecar metadata for one logical query parameter.
///
/// `logicalIndex` mirrors ``XLLogicalParameterIndex``. `physicalIndex` is the
/// one-based SQLite bind position, which the frozen `XLQueryIdentity` v1
/// representation deliberately excludes.
public struct SQLiteBuildValidationParameterEntry: Codable, Equatable, Sendable {

    public enum KeyKind: String, Codable, Sendable {
        case named
        case indexed
    }

    public let logicalIndex: Int
    public let physicalIndex: Int
    public let identity: String
    public let keyKind: KeyKind
    public let keyName: String?
    public let keyIndex: Int?
    public let valueTypeIdentifier: String
    public let valueTypeName: String
    public let nullability: String
    public let codec: SQLiteBuildValidationCodecReference?
    public let storageIdentifier: String

    public init(
        logicalIndex: Int,
        physicalIndex: Int,
        identity: String,
        keyKind: KeyKind,
        keyName: String?,
        keyIndex: Int?,
        valueTypeIdentifier: String,
        valueTypeName: String,
        nullability: String,
        codec: SQLiteBuildValidationCodecReference?,
        storageIdentifier: String
    ) {
        self.logicalIndex = logicalIndex
        self.physicalIndex = physicalIndex
        self.identity = identity
        self.keyKind = keyKind
        self.keyName = keyName
        self.keyIndex = keyIndex
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.codec = codec
        self.storageIdentifier = storageIdentifier
    }

    /// The SQLite placeholder spelling a validator should observe at prepare time.
    public var expectedSQLiteSpelling: String {
        switch keyKind {
        case .named:
            return ":\(keyName ?? "")"
        case .indexed:
            return "?\((keyIndex ?? -1) + 1)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case logicalIndex = "logical_index"
        case physicalIndex = "physical_index"
        case identity
        case keyKind = "key_kind"
        case keyName = "key_name"
        case keyIndex = "key_index"
        case valueTypeIdentifier = "value_type_identifier"
        case valueTypeName = "value_type_name"
        case nullability
        case codec
        case storageIdentifier = "storage_identifier"
    }
}


/// Sidecar metadata for one value in a returned row.
///
/// `declaredAlias` is the stable `AS` alias the query renders, when known.
/// SQLite does not promise stable names for unaliased expressions, so this is
/// `nil` for positional-only results.
public struct SQLiteBuildValidationResultEntry: Codable, Equatable, Sendable {

    public let index: Int
    public let identity: String
    public let declaredAlias: String?
    public let valueTypeIdentifier: String
    public let valueTypeName: String
    public let nullability: String
    public let codec: SQLiteBuildValidationCodecReference?
    public let storageIdentifier: String

    public init(
        index: Int,
        identity: String,
        declaredAlias: String?,
        valueTypeIdentifier: String,
        valueTypeName: String,
        nullability: String,
        codec: SQLiteBuildValidationCodecReference?,
        storageIdentifier: String
    ) {
        self.index = index
        self.identity = identity
        self.declaredAlias = declaredAlias
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.codec = codec
        self.storageIdentifier = storageIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case identity
        case declaredAlias = "declared_alias"
        case valueTypeIdentifier = "value_type_identifier"
        case valueTypeName = "value_type_name"
        case nullability
        case codec
        case storageIdentifier = "storage_identifier"
    }
}


/// One static query's complete sidecar entry.
///
/// Descriptor fields remain authoritative where they overlap; this only adds
/// the reproducible-build fields the frozen `XLQueryIdentity` v1
/// representation excludes: physical placeholder positions, declared result
/// aliases, and cross-references into the #190 conformance inventory, #191
/// combinatorial cases, and #254 Northwind anchors.
public struct SQLiteBuildValidationQueryEntry: Codable, Equatable, Sendable {

    public let id: String
    public let definitionIdentity: String
    public let descriptorIdentity: String
    public let conformanceFeatureIDs: [String]
    public let conformanceCaseIDs: [String]
    public let northwindAnchorCaseIDs: [String]
    public let sql: String
    public let dialectIdentifier: String
    public let minimumDialectVersion: String?
    public let dialectCapabilitiesRawValue: UInt64
    public let cardinality: UInt8
    public let parameters: [SQLiteBuildValidationParameterEntry]
    public let results: [SQLiteBuildValidationResultEntry]
    public let requiredCapabilities: [SQLiteBuildValidationCapabilityReference]

    public init(
        id: String,
        definitionIdentity: String,
        descriptorIdentity: String,
        conformanceFeatureIDs: [String] = [],
        conformanceCaseIDs: [String] = [],
        northwindAnchorCaseIDs: [String] = [],
        sql: String,
        dialectIdentifier: String,
        minimumDialectVersion: String? = nil,
        dialectCapabilitiesRawValue: UInt64 = 0,
        cardinality: UInt8,
        parameters: [SQLiteBuildValidationParameterEntry] = [],
        results: [SQLiteBuildValidationResultEntry] = [],
        requiredCapabilities: [String] = []
    ) {
        self.id = id
        self.definitionIdentity = definitionIdentity
        self.descriptorIdentity = descriptorIdentity
        self.conformanceFeatureIDs = Self.sortedUnique(conformanceFeatureIDs)
        self.conformanceCaseIDs = Self.sortedUnique(conformanceCaseIDs)
        self.northwindAnchorCaseIDs = Self.sortedUnique(northwindAnchorCaseIDs)
        self.sql = sql
        self.dialectIdentifier = dialectIdentifier
        self.minimumDialectVersion = minimumDialectVersion
        self.dialectCapabilitiesRawValue = dialectCapabilitiesRawValue
        self.cardinality = cardinality
        self.parameters = parameters.sorted { $0.logicalIndex < $1.logicalIndex }
        self.results = results.sorted { $0.index < $1.index }
        self.requiredCapabilities = Self.sortedUniqueCapabilities(requiredCapabilities)
    }

    /// Projects an existing static query descriptor into sidecar form.
    ///
    /// Physical placeholder positions are recovered by scanning the rendered
    /// SQL, since `XLStaticQueryDescriptor` intentionally carries only logical
    /// parameter order.
    public init(
        id: String,
        descriptor: XLStaticQueryDescriptor,
        declaredAliases: [String?]? = nil,
        conformanceFeatureIDs: [String] = [],
        conformanceCaseIDs: [String] = [],
        northwindAnchorCaseIDs: [String] = [],
        requiredCapabilities: [String] = []
    ) throws {
        if let declaredAliases, declaredAliases.count != descriptor.results.count {
            throw SQLiteBuildValidationManifestError.resultAliasCountMismatch(
                queryID: id,
                expected: descriptor.results.count,
                actual: declaredAliases.count
            )
        }

        let placeholders = SQLiteBuildValidationManifestPlaceholderScanner.scan(
            descriptor.sql
        )
        var projectedParameters: [SQLiteBuildValidationParameterEntry] = []
        for parameter in descriptor.parameters.sorted(by: {
            $0.slot.index < $1.slot.index
        }) {
            let keyKind: SQLiteBuildValidationParameterEntry.KeyKind
            let keyName: String?
            let keyIndex: Int?
            let physicalIndex: Int
            switch parameter.slot.key {
            case .named(let name):
                keyKind = .named
                keyName = name
                keyIndex = nil
                let spelling = ":\(name)"
                guard let occurrence = placeholders.occurrences.first(
                    where: { $0.spelling == spelling }
                ) else {
                    throw SQLiteBuildValidationManifestError.invalidQuery(
                        id,
                        "named parameter '\(spelling)' is absent from descriptor SQL"
                    )
                }
                physicalIndex = occurrence.physicalIndex
            case .indexed(let zeroBasedIndex):
                keyKind = .indexed
                keyName = nil
                keyIndex = zeroBasedIndex
                let spelling = "?\(zeroBasedIndex + 1)"
                guard placeholders.occurrences.contains(
                    where: { $0.spelling == spelling }
                ) else {
                    throw SQLiteBuildValidationManifestError.invalidQuery(
                        id,
                        "indexed parameter '\(spelling)' is absent from descriptor SQL"
                    )
                }
                physicalIndex = zeroBasedIndex + 1
            }
            projectedParameters.append(SQLiteBuildValidationParameterEntry(
                logicalIndex: parameter.slot.index.rawValue,
                physicalIndex: physicalIndex,
                identity: parameter.identity.description,
                keyKind: keyKind,
                keyName: keyName,
                keyIndex: keyIndex,
                valueTypeIdentifier: parameter.slot.valueTypeIdentifier.rawValue,
                valueTypeName: parameter.slot.valueTypeName,
                nullability: parameter.slot.nullability.rawValue,
                codec: parameter.slot.codecIdentity.map(
                    SQLiteBuildValidationCodecReference.init
                ),
                storageIdentifier: parameter.storageIdentifier.rawValue
            ))
        }

        let aliases = declaredAliases
            ?? Array<String?>(repeating: nil, count: descriptor.results.count)
        let projectedResults = descriptor.results.slots.map { result in
            SQLiteBuildValidationResultEntry(
                index: result.index.rawValue,
                identity: result.identity.description,
                declaredAlias: aliases[result.index.rawValue],
                valueTypeIdentifier: result.valueTypeIdentifier.rawValue,
                valueTypeName: result.valueTypeName,
                nullability: result.nullability.rawValue,
                codec: result.codecIdentity.map(
                    SQLiteBuildValidationCodecReference.init
                ),
                storageIdentifier: result.storageIdentifier.rawValue
            )
        }

        self.init(
            id: id,
            definitionIdentity: descriptor.definitionIdentity.description,
            descriptorIdentity: descriptor.identity.description,
            conformanceFeatureIDs: conformanceFeatureIDs,
            conformanceCaseIDs: conformanceCaseIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            sql: descriptor.sql,
            dialectIdentifier: descriptor.dialectRequirement.identity.rawValue,
            minimumDialectVersion: descriptor.dialectRequirement.minimumVersion?.description,
            dialectCapabilitiesRawValue: descriptor.dialectRequirement.capabilities.rawValue,
            cardinality: descriptor.cardinality.rawValue,
            parameters: projectedParameters,
            results: projectedResults,
            requiredCapabilities: requiredCapabilities
        )
    }

    public var expectedPhysicalParameterCount: Int {
        parameters.map(\.physicalIndex).max() ?? 0
    }

    public var requiredCodecIdentifiers: [String] {
        let codecs = parameters.compactMap(\.codec) + results.compactMap(\.codec)
        return Array(Set(codecs.map(\.stableIdentifier))).sorted()
    }

    /// Re-applies canonical ordering. Used when normalizing a decoded or
    /// externally-constructed manifest.
    func normalized() -> Self {
        Self(
            id: id,
            definitionIdentity: definitionIdentity,
            descriptorIdentity: descriptorIdentity,
            conformanceFeatureIDs: conformanceFeatureIDs,
            conformanceCaseIDs: conformanceCaseIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            sql: sql,
            dialectIdentifier: dialectIdentifier,
            minimumDialectVersion: minimumDialectVersion,
            dialectCapabilitiesRawValue: dialectCapabilitiesRawValue,
            cardinality: cardinality,
            parameters: parameters,
            results: results,
            requiredCapabilities: requiredCapabilities.map(\.id)
        )
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private static func sortedUniqueCapabilities(
        _ ids: [String]
    ) -> [SQLiteBuildValidationCapabilityReference] {
        Self.sortedUnique(ids).map(SQLiteBuildValidationCapabilityReference.init)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case definitionIdentity = "definition_identity"
        case descriptorIdentity = "descriptor_identity"
        case conformanceFeatureIDs = "conformance_feature_ids"
        case conformanceCaseIDs = "conformance_case_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case sql
        case dialectIdentifier = "dialect_identifier"
        case minimumDialectVersion = "minimum_dialect_version"
        case dialectCapabilitiesRawValue = "dialect_capabilities_raw_value"
        case cardinality
        case parameters
        case results
        case requiredCapabilities = "required_capabilities"
    }
}
