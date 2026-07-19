import Foundation
import SwiftQLCore


package enum SQLiteBuildValidationVerdict: String, Codable, CaseIterable, Sendable {
    case passed
    case failed
    case unsupported
}


package struct SQLiteBuildValidationSchemaInput: Codable, Equatable, Sendable {
    package enum Kind: String, Codable, Sendable {
        case checkedInSnapshot = "checked-in-snapshot"
    }

    package let kind: Kind
    package let identifier: String
    package let databaseSHA256: String
    package let databaseByteCount: Int
    package let schemaRowCount: Int
    package let schemaFNV1A64: String

    package init(
        kind: Kind = .checkedInSnapshot,
        identifier: String,
        databaseSHA256: String,
        databaseByteCount: Int,
        schemaRowCount: Int,
        schemaFNV1A64: String
    ) {
        self.kind = kind
        self.identifier = identifier
        self.databaseSHA256 = databaseSHA256.lowercased()
        self.databaseByteCount = databaseByteCount
        self.schemaRowCount = schemaRowCount
        self.schemaFNV1A64 = schemaFNV1A64.lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case identifier
        case databaseSHA256 = "database_sha256"
        case databaseByteCount = "database_byte_count"
        case schemaRowCount = "schema_row_count"
        case schemaFNV1A64 = "schema_fnv1a_64"
    }
}


package struct SQLiteBuildValidationCodec: Codable, Equatable, Hashable, Sendable {
    package let keyID: String
    package let keyVersion: UInt64
    package let valueTypeIdentifier: String
    package let dialectIdentifier: String
    package let storageIdentifier: String

    package init(
        keyID: String,
        keyVersion: UInt64,
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

    package init(_ identity: XLValueCodecIdentity) {
        self.init(
            keyID: identity.key.id,
            keyVersion: UInt64(identity.key.version),
            valueTypeIdentifier: identity.valueTypeIdentifier.rawValue,
            dialectIdentifier: identity.dialectIdentifier.rawValue,
            storageIdentifier: identity.storageIdentifier.rawValue
        )
    }

    /// Stable CLI spelling for an available codec. The sidecar retains the
    /// structured fields; this spelling is only an invocation convenience.
    package var stableIdentifier: String {
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


package struct SQLiteBuildValidationCapabilityRequirement:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    package let id: String

    package init(id: String) {
        self.id = id
    }
}


package struct SQLiteBuildValidationParameter: Codable, Equatable, Sendable {
    package enum KeyKind: String, Codable, Sendable {
        case named
        case indexed
    }

    package let logicalIndex: Int
    package let physicalIndex: Int
    package let identity: String
    package let keyKind: KeyKind
    package let keyName: String?
    package let keyIndex: Int?
    package let valueTypeIdentifier: String
    package let valueTypeName: String
    package let nullability: String
    package let codec: SQLiteBuildValidationCodec?
    package let storageIdentifier: String

    package init(
        logicalIndex: Int,
        physicalIndex: Int,
        identity: String,
        keyKind: KeyKind,
        keyName: String?,
        keyIndex: Int?,
        valueTypeIdentifier: String,
        valueTypeName: String,
        nullability: String,
        codec: SQLiteBuildValidationCodec?,
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

    package var expectedSQLiteName: String {
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


package struct SQLiteBuildValidationResult: Codable, Equatable, Sendable {
    package let index: Int
    package let identity: String
    package let expectedAlias: String?
    package let valueTypeIdentifier: String
    package let valueTypeName: String
    package let nullability: String
    package let codec: SQLiteBuildValidationCodec?
    package let storageIdentifier: String

    package init(
        index: Int,
        identity: String,
        expectedAlias: String?,
        valueTypeIdentifier: String,
        valueTypeName: String,
        nullability: String,
        codec: SQLiteBuildValidationCodec?,
        storageIdentifier: String
    ) {
        self.index = index
        self.identity = identity
        self.expectedAlias = expectedAlias
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.codec = codec
        self.storageIdentifier = storageIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case identity
        case expectedAlias = "expected_alias"
        case valueTypeIdentifier = "value_type_identifier"
        case valueTypeName = "value_type_name"
        case nullability
        case codec
        case storageIdentifier = "storage_identifier"
    }
}


package struct SQLiteBuildValidationQuery: Codable, Equatable, Sendable {
    package let id: String
    package let definitionIdentity: String
    package let descriptorIdentity: String
    package let conformanceCaseIDs: [String]
    package let northwindAnchorCaseIDs: [String]
    package let inventoryFeatureIDs: [String]
    package let sql: String
    package let dialectIdentifier: String
    package let minimumSQLiteVersion: String?
    package let dialectCapabilitiesRawValue: UInt64
    package let cardinality: UInt8
    package let parameters: [SQLiteBuildValidationParameter]
    package let results: [SQLiteBuildValidationResult]
    package let requiredCapabilities: [SQLiteBuildValidationCapabilityRequirement]

    package init(
        id: String,
        definitionIdentity: String,
        descriptorIdentity: String,
        conformanceCaseIDs: [String] = [],
        northwindAnchorCaseIDs: [String] = [],
        inventoryFeatureIDs: [String] = [],
        sql: String,
        dialectIdentifier: String = XLSQLiteDialect.identity.rawValue,
        minimumSQLiteVersion: String? = nil,
        dialectCapabilitiesRawValue: UInt64 = 0,
        cardinality: UInt8,
        parameters: [SQLiteBuildValidationParameter] = [],
        results: [SQLiteBuildValidationResult] = [],
        requiredCapabilities: [SQLiteBuildValidationCapabilityRequirement] = []
    ) {
        self.id = id
        self.definitionIdentity = definitionIdentity
        self.descriptorIdentity = descriptorIdentity
        self.conformanceCaseIDs = Self.sortedUnique(conformanceCaseIDs)
        self.northwindAnchorCaseIDs = Self.sortedUnique(northwindAnchorCaseIDs)
        self.inventoryFeatureIDs = Self.sortedUnique(inventoryFeatureIDs)
        self.sql = sql
        self.dialectIdentifier = dialectIdentifier
        self.minimumSQLiteVersion = minimumSQLiteVersion
        self.dialectCapabilitiesRawValue = dialectCapabilitiesRawValue
        self.cardinality = cardinality
        self.parameters = parameters.sorted { $0.logicalIndex < $1.logicalIndex }
        self.results = results.sorted { $0.index < $1.index }
        self.requiredCapabilities = Array(Set(requiredCapabilities)).sorted {
            $0.id < $1.id
        }
    }

    package init(
        id: String,
        descriptor: XLStaticQueryDescriptor,
        resultAliases: [String?]? = nil,
        conformanceCaseIDs: [String] = [],
        northwindAnchorCaseIDs: [String] = [],
        inventoryFeatureIDs: [String] = [],
        requiredCapabilities: [String] = []
    ) throws {
        if let resultAliases, resultAliases.count != descriptor.results.count {
            throw SQLiteBuildValidationModelError.resultAliasCountMismatch(
                queryID: id,
                expected: descriptor.results.count,
                actual: resultAliases.count
            )
        }

        let placeholderAnalysis = SQLiteBuildValidationPlaceholderScanner.scan(
            descriptor.sql
        )
        var projectedParameters: [SQLiteBuildValidationParameter] = []
        for parameter in descriptor.parameters.sorted(by: {
            $0.slot.index < $1.slot.index
        }) {
            let keyKind: SQLiteBuildValidationParameter.KeyKind
            let keyName: String?
            let keyIndex: Int?
            let physicalIndex: Int
            switch parameter.slot.key {
            case .named(let name):
                keyKind = .named
                keyName = name
                keyIndex = nil
                let spelling = ":\(name)"
                guard let occurrence = placeholderAnalysis.occurrences.first(
                    where: { $0.spelling == spelling }
                ) else {
                    throw SQLiteBuildValidationModelError.invalidQuery(
                        id,
                        "named parameter '\(spelling)' is absent from descriptor SQL"
                    )
                }
                physicalIndex = occurrence.physicalIndex
            case .indexed(let zeroBasedIndex):
                keyKind = .indexed
                keyName = nil
                keyIndex = zeroBasedIndex
                physicalIndex = zeroBasedIndex + 1
            }
            projectedParameters.append(SQLiteBuildValidationParameter(
                logicalIndex: parameter.slot.index.rawValue,
                physicalIndex: physicalIndex,
                identity: parameter.identity.description,
                keyKind: keyKind,
                keyName: keyName,
                keyIndex: keyIndex,
                valueTypeIdentifier: parameter.slot.valueTypeIdentifier.rawValue,
                valueTypeName: parameter.slot.valueTypeName,
                nullability: parameter.slot.nullability.rawValue,
                codec: parameter.slot.codecIdentity.map(SQLiteBuildValidationCodec.init),
                storageIdentifier: parameter.storageIdentifier.rawValue
            ))
        }

        let aliases = resultAliases
            ?? Array<String?>(repeating: nil, count: descriptor.results.count)
        let projectedResults = descriptor.results.slots.map { result in
            SQLiteBuildValidationResult(
                index: result.index.rawValue,
                identity: result.identity.description,
                expectedAlias: aliases[result.index.rawValue],
                valueTypeIdentifier: result.valueTypeIdentifier.rawValue,
                valueTypeName: result.valueTypeName,
                nullability: result.nullability.rawValue,
                codec: result.codecIdentity.map(SQLiteBuildValidationCodec.init),
                storageIdentifier: result.storageIdentifier.rawValue
            )
        }

        self.init(
            id: id,
            definitionIdentity: descriptor.definitionIdentity.description,
            descriptorIdentity: descriptor.identity.description,
            conformanceCaseIDs: conformanceCaseIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            inventoryFeatureIDs: inventoryFeatureIDs,
            sql: descriptor.sql,
            dialectIdentifier: descriptor.dialectRequirement.identity.rawValue,
            minimumSQLiteVersion: descriptor.dialectRequirement.minimumVersion?.description,
            dialectCapabilitiesRawValue: descriptor.dialectRequirement.capabilities.rawValue,
            cardinality: descriptor.cardinality.rawValue,
            parameters: projectedParameters,
            results: projectedResults,
            requiredCapabilities: requiredCapabilities.map {
                SQLiteBuildValidationCapabilityRequirement(id: $0)
            }
        )
    }

    package var expectedPhysicalParameterCount: Int {
        parameters.map(\.physicalIndex).max() ?? 0
    }

    package var requiredCodecIdentifiers: [String] {
        let codecs = parameters.compactMap(\.codec) + results.compactMap(\.codec)
        return Array(Set(codecs.map(\.stableIdentifier))).sorted()
    }

    fileprivate func normalized() -> Self {
        Self(
            id: id,
            definitionIdentity: definitionIdentity,
            descriptorIdentity: descriptorIdentity,
            conformanceCaseIDs: conformanceCaseIDs,
            northwindAnchorCaseIDs: northwindAnchorCaseIDs,
            inventoryFeatureIDs: inventoryFeatureIDs,
            sql: sql,
            dialectIdentifier: dialectIdentifier,
            minimumSQLiteVersion: minimumSQLiteVersion,
            dialectCapabilitiesRawValue: dialectCapabilitiesRawValue,
            cardinality: cardinality,
            parameters: parameters,
            results: results,
            requiredCapabilities: requiredCapabilities
        )
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case definitionIdentity = "definition_identity"
        case descriptorIdentity = "descriptor_identity"
        case conformanceCaseIDs = "conformance_case_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case inventoryFeatureIDs = "inventory_feature_ids"
        case sql
        case dialectIdentifier = "dialect_identifier"
        case minimumSQLiteVersion = "minimum_sqlite_version"
        case dialectCapabilitiesRawValue = "dialect_capabilities_raw_value"
        case cardinality
        case parameters
        case results
        case requiredCapabilities = "required_capabilities"
    }
}


package struct SQLiteBuildValidationPlan: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let inventoryVersion: String
    package let schema: SQLiteBuildValidationSchemaInput
    package let queries: [SQLiteBuildValidationQuery]

    package init(
        schemaVersion: Int = 1,
        inventoryVersion: String,
        schema: SQLiteBuildValidationSchemaInput,
        queries: [SQLiteBuildValidationQuery]
    ) {
        self.schemaVersion = schemaVersion
        self.inventoryVersion = inventoryVersion
        self.schema = schema
        self.queries = queries.map { $0.normalized() }.sorted { $0.id < $1.id }
    }

    package static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data).validating()
    }

    package static func decode(contentsOf url: URL) throws -> Self {
        try decode(Data(contentsOf: url))
    }

    package func validating() throws -> Self {
        guard schemaVersion == 1 else {
            throw SQLiteBuildValidationModelError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !inventoryVersion.isEmpty else {
            throw SQLiteBuildValidationModelError.invalidPlan(
                "inventory_version must not be empty"
            )
        }
        guard !queries.isEmpty else {
            throw SQLiteBuildValidationModelError.invalidPlan(
                "queries must not be empty"
            )
        }
        guard !schema.identifier.isEmpty,
              schema.databaseByteCount > 0,
              schema.schemaRowCount > 0,
              Self.isLowercaseHex(schema.databaseSHA256, count: 64),
              Self.isLowercaseHex(schema.schemaFNV1A64, count: 16) else {
            throw SQLiteBuildValidationModelError.invalidPlan(
                "checked-in schema identity, byte count, row count, SHA-256, and FNV-1a-64 are required"
            )
        }

        let duplicateQueryID = Dictionary(grouping: queries, by: \.id)
            .first { $0.value.count > 1 }?.key
        if let duplicateQueryID {
            throw SQLiteBuildValidationModelError.duplicateQueryID(duplicateQueryID)
        }
        for query in queries {
            try Self.validate(query)
        }
        return Self(
            schemaVersion: schemaVersion,
            inventoryVersion: inventoryVersion,
            schema: schema,
            queries: queries
        )
    }

    package func canonicalJSONData() throws -> Data {
        try SQLiteBuildValidationCanonicalJSON.encode(validating())
    }

    private static func validate(_ query: SQLiteBuildValidationQuery) throws {
        guard !query.id.isEmpty,
              !query.definitionIdentity.isEmpty,
              !query.descriptorIdentity.isEmpty,
              !query.dialectIdentifier.isEmpty else {
            throw SQLiteBuildValidationModelError.invalidQuery(
                query.id,
                "query and descriptor identities must not be empty"
            )
        }
        guard !query.conformanceCaseIDs.contains(where: \.isEmpty),
              !query.northwindAnchorCaseIDs.contains(where: \.isEmpty),
              !query.inventoryFeatureIDs.contains(where: \.isEmpty),
              !query.requiredCapabilities.contains(where: { $0.id.isEmpty }) else {
            throw SQLiteBuildValidationModelError.invalidQuery(
                query.id,
                "case, feature, and capability identifiers must not be empty"
            )
        }

        for (offset, parameter) in query.parameters.enumerated() {
            guard parameter.logicalIndex == offset,
                  parameter.physicalIndex > 0,
                  !parameter.identity.isEmpty,
                  !parameter.valueTypeIdentifier.isEmpty,
                  !parameter.valueTypeName.isEmpty,
                  !parameter.storageIdentifier.isEmpty else {
                throw SQLiteBuildValidationModelError.invalidQuery(
                    query.id,
                    "parameter metadata must be contiguous and complete"
                )
            }
            switch parameter.keyKind {
            case .named:
                guard let name = parameter.keyName, !name.isEmpty,
                      parameter.keyIndex == nil else {
                    throw SQLiteBuildValidationModelError.invalidQuery(
                        query.id,
                        "named parameters require key_name and no key_index"
                    )
                }
            case .indexed:
                guard parameter.keyName == nil,
                      let index = parameter.keyIndex,
                      index >= 0,
                      parameter.physicalIndex == index + 1 else {
                    throw SQLiteBuildValidationModelError.invalidQuery(
                        query.id,
                        "indexed parameters require a nonnegative key_index matching physical_index"
                    )
                }
            }
            try validate(parameter.codec, queryID: query.id)
        }
        guard Set(query.parameters.map(\.physicalIndex)).count
                == query.parameters.count else {
            throw SQLiteBuildValidationModelError.invalidQuery(
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
                  result.expectedAlias?.isEmpty != true else {
                throw SQLiteBuildValidationModelError.invalidQuery(
                    query.id,
                    "result metadata must be contiguous and complete"
                )
            }
            try validate(result.codec, queryID: query.id)
        }
    }

    private static func validate(
        _ codec: SQLiteBuildValidationCodec?,
        queryID: String
    ) throws {
        guard let codec else {
            return
        }
        guard !codec.keyID.isEmpty,
              !codec.valueTypeIdentifier.isEmpty,
              !codec.dialectIdentifier.isEmpty,
              !codec.storageIdentifier.isEmpty else {
            throw SQLiteBuildValidationModelError.invalidQuery(
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
        case schemaVersion = "schema_version"
        case inventoryVersion = "inventory_version"
        case schema
        case queries
    }
}


package enum SQLiteBuildValidationModelError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case unsupportedSchemaVersion(Int)
    case invalidPlan(String)
    case duplicateQueryID(String)
    case invalidQuery(String, String)
    case resultAliasCountMismatch(queryID: String, expected: Int, actual: Int)

    package var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported build-validation sidecar schema version \(version)."
        case .invalidPlan(let reason):
            return "Invalid build-validation plan: \(reason)."
        case .duplicateQueryID(let id):
            return "Build-validation query id '\(id)' is duplicated."
        case .invalidQuery(let id, let reason):
            return "Invalid build-validation query '\(id)': \(reason)."
        case .resultAliasCountMismatch(let queryID, let expected, let actual):
            return "Build-validation query '\(queryID)' supplied \(actual) result aliases for \(expected) result slots."
        }
    }
}


enum SQLiteBuildValidationCanonicalJSON {
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
