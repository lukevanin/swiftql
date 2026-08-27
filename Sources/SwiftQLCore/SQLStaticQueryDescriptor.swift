//
//  SQLStaticQueryDescriptor.swift
//  SwiftQLCore
//
//  A database-independent, fully described query: its identity, its rendered
//  statement, its parameters, its results, and the errors that describe an
//  invalid one.
//
//  Reduced to the descriptor itself by issue #559 -- the identities it is
//  built from are in SQLQueryIdentity.swift, the row metadata in
//  SQLStaticRowMetadata.swift, and the frozen identity encoding in
//  SQLQueryIdentityEncodingV1.swift.
//

import Foundation


public struct XLStaticQueryDescriptor: Hashable, Sendable {

    public let definitionIdentity: XLQueryDefinitionIdentity

    public let statement: XLStaticStatementDefinition

    /// Canonically ordered by logical parameter index.
    public let parameters: [XLStaticQueryParameterMetadata]

    public let results: XLStaticQueryResultMetadata

    public let cardinality: XLQueryCardinality

    public let identity: XLQueryIdentity

    public init(
        definitionIdentity: XLQueryDefinitionIdentity,
        statement: XLStaticStatementDefinition,
        parameters: [XLStaticQueryParameterMetadata],
        results: XLStaticQueryResultMetadata,
        cardinality: XLQueryCardinality,
        identityFormatVersion: XLQueryIdentityFormatVersion = .current
    ) throws {
        guard identityFormatVersion == .v1 else {
            throw XLStaticQueryError.unsupportedIdentityFormatVersion(
                identityFormatVersion
            )
        }
        guard !statement.sql.isEmpty else {
            throw XLStaticQueryError.emptySQL
        }
        guard !statement.dialectRequirement.identity.rawValue.isEmpty else {
            throw XLStaticQueryError.emptyDialectIdentifier
        }
        try _xlValidate(statement.dialectRequirement.minimumVersion)
        for entity in statement.entities where entity.isEmpty {
            throw XLStaticQueryError.emptyEntity
        }

        switch cardinality {
        case .command:
            guard results.isEmpty else {
                throw XLStaticQueryError.commandHasResults(results: results)
            }
        case .exactlyOne, .zeroOrOne, .many:
            guard !results.isEmpty else {
                throw XLStaticQueryError.rowQueryHasNoResults(
                    cardinality: cardinality
                )
            }
        }

        let canonicalParameters = try Self.validateAndCanonicalize(
            parameters,
            for: statement
        )
        try Self.validateResultDialects(results, for: statement)

        let canonicalBytes = XLStaticQueryIdentityEncoder.encodeV1(
            definitionIdentity: definitionIdentity,
            statement: statement,
            parameters: canonicalParameters,
            results: results,
            cardinality: cardinality
        )

        self.definitionIdentity = definitionIdentity
        self.statement = statement
        self.parameters = canonicalParameters
        self.results = results
        self.cardinality = cardinality
        self.identity = XLQueryIdentity(
            formatVersion: identityFormatVersion,
            definitionIdentity: definitionIdentity,
            canonicalBytes: canonicalBytes
        )
    }

    public var sql: String {
        statement.sql
    }

    public var dialectRequirement: XLDialectRequirement {
        statement.dialectRequirement
    }

    public var entities: Set<String> {
        statement.entities
    }

    public var parameterLayout: XLParameterLayout {
        statement.parameterLayout
    }

    /// The complete canonical material used as durable query identity.
    public var canonicalIdentityMaterial: [UInt8] {
        identity.canonicalBytes
    }

    public func parameter(
        at index: XLLogicalParameterIndex
    ) -> XLStaticQueryParameterMetadata? {
        parameters.first { $0.slot.index == index }
    }

    public func parameter(
        for identity: XLQuerySlotIdentity
    ) -> XLStaticQueryParameterMetadata? {
        parameters.first { $0.identity == identity }
    }

    private static func validateAndCanonicalize(
        _ parameters: [XLStaticQueryParameterMetadata],
        for statement: XLStaticStatementDefinition
    ) throws -> [XLStaticQueryParameterMetadata] {
        guard parameters.count == statement.parameterLayout.count else {
            throw XLStaticQueryError.parameterMetadataCountMismatch(
                expected: statement.parameterLayout.count,
                actual: parameters.count
            )
        }

        var byIndex: [XLLogicalParameterIndex: XLStaticQueryParameterMetadata] = [:]
        var byIdentity: [XLQuerySlotIdentity: XLStaticQueryParameterMetadata] = [:]

        for parameter in parameters {
            let slot = parameter.slot
            guard let expected = statement.parameterLayout.slot(at: slot.index) else {
                throw XLStaticQueryError.parameterNotInStatement(
                    parameter: parameter
                )
            }
            guard expected == slot else {
                throw XLStaticQueryError.parameterSlotMismatch(
                    expected: expected,
                    actual: slot
                )
            }
            guard !slot.valueTypeIdentifier.rawValue.isEmpty else {
                throw XLStaticQueryError.emptyValueTypeIdentifier(
                    slot: parameter.identity
                )
            }
            guard !parameter.storageIdentifier.rawValue.isEmpty else {
                throw XLStaticQueryError.emptyStorageIdentifier(
                    slot: parameter.identity
                )
            }
            guard slot.codingContext.site == .parameter else {
                throw XLStaticQueryError.invalidParameterCodingSite(
                    parameter: parameter,
                    actual: slot.codingContext.site
                )
            }
            guard byIndex[slot.index] == nil else {
                throw XLStaticQueryError.duplicateParameterIndex(
                    index: slot.index
                )
            }
            guard byIdentity[parameter.identity] == nil else {
                throw XLStaticQueryError.duplicateParameterIdentity(
                    identity: parameter.identity
                )
            }

            switch slot.key {
            case .named(let name):
                guard !name.isEmpty else {
                    throw XLStaticQueryError.emptyNamedBindingKey(slot: slot)
                }
                guard statement.dialectRequirement.capabilities.contains(
                    .namedBindings
                ) else {
                    throw XLStaticQueryError.parameterCapabilityMissing(
                        parameter: parameter,
                        capability: .namedBindings
                    )
                }
            case .indexed(let physicalIndex):
                guard physicalIndex >= 0 else {
                    throw XLStaticQueryError.invalidIndexedBindingKey(slot: slot)
                }
                guard statement.dialectRequirement.capabilities.contains(
                    .indexedBindings
                ) else {
                    throw XLStaticQueryError.parameterCapabilityMissing(
                        parameter: parameter,
                        capability: .indexedBindings
                    )
                }
            }

            if let codecIdentity = slot.codecIdentity {
                guard codecIdentity.dialectIdentifier
                    == statement.dialectRequirement.identity else {
                    throw XLStaticQueryError.parameterCodecDialectMismatch(
                        parameter: parameter,
                        expected: statement.dialectRequirement.identity,
                        actual: codecIdentity.dialectIdentifier
                    )
                }
                guard codecIdentity.storageIdentifier
                    == parameter.storageIdentifier else {
                    throw XLStaticQueryError.parameterCodecStorageMismatch(
                        parameter: parameter,
                        codecStorageIdentifier: codecIdentity.storageIdentifier
                    )
                }
            }

            byIndex[slot.index] = parameter
            byIdentity[parameter.identity] = parameter
        }

        return byIndex.values.sorted { lhs, rhs in
            lhs.slot.index < rhs.slot.index
        }
    }

    private static func validateResultDialects(
        _ results: XLStaticQueryResultMetadata,
        for statement: XLStaticStatementDefinition
    ) throws {
        for result in results.slots {
            guard let codecIdentity = result.codecIdentity else {
                continue
            }
            guard codecIdentity.dialectIdentifier
                == statement.dialectRequirement.identity else {
                throw XLStaticQueryError.resultCodecDialectMismatch(
                    result: result,
                    expected: statement.dialectRequirement.identity,
                    actual: codecIdentity.dialectIdentifier
                )
            }
        }
    }
}


/// Deterministic validation failures while constructing static query metadata.
public enum XLStaticQueryError: Error, Equatable, Sendable, LocalizedError {
    case emptyDefinitionPath
    case emptyDefinitionPathComponent(index: Int)
    case emptySlotPath
    case emptySlotPathComponent(index: Int)
    case unsupportedIdentityFormatVersion(XLQueryIdentityFormatVersion)
    case definitionIdentityCollision(
        definition: XLQueryDefinitionIdentity,
        existing: XLQueryIdentity,
        incoming: XLQueryIdentity
    )
    case emptySQL
    case emptyDialectIdentifier
    case negativeDialectVersion(XLDialectVersion)
    case emptyEntity
    case invalidResultIndex(slot: XLStaticQueryResultSlot)
    case noncontiguousResultIndex(
        slot: XLStaticQueryResultSlot,
        expected: XLLogicalResultIndex
    )
    case conflictingResultIndex(
        index: XLLogicalResultIndex,
        existing: XLStaticQueryResultSlot,
        incoming: XLStaticQueryResultSlot
    )
    case conflictingResultIdentity(
        identity: XLQuerySlotIdentity,
        existing: XLStaticQueryResultSlot,
        incoming: XLStaticQueryResultSlot
    )
    case emptyValueTypeIdentifier(slot: XLQuerySlotIdentity)
    case emptyStorageIdentifier(slot: XLQuerySlotIdentity)
    case invalidResultCodingSite(
        result: XLStaticQueryResultSlot,
        actual: XLValueCodingSite
    )
    case resultCodecValueTypeMismatch(
        slot: XLStaticQueryResultSlot,
        codecValueTypeIdentifier: XLValueTypeIdentifier
    )
    case resultCodecStorageMismatch(
        slot: XLStaticQueryResultSlot,
        codecStorageIdentifier: XLValueStorageIdentifier
    )
    case commandHasResults(results: XLStaticQueryResultMetadata)
    case rowQueryHasNoResults(cardinality: XLQueryCardinality)
    case parameterMetadataCountMismatch(expected: Int, actual: Int)
    case parameterNotInStatement(parameter: XLStaticQueryParameterMetadata)
    case parameterSlotMismatch(expected: XLParameterSlot, actual: XLParameterSlot)
    case duplicateParameterIndex(index: XLLogicalParameterIndex)
    case duplicateParameterIdentity(identity: XLQuerySlotIdentity)
    case invalidParameterCodingSite(
        parameter: XLStaticQueryParameterMetadata,
        actual: XLValueCodingSite
    )
    case emptyNamedBindingKey(slot: XLParameterSlot)
    case invalidIndexedBindingKey(slot: XLParameterSlot)
    case parameterCapabilityMissing(
        parameter: XLStaticQueryParameterMetadata,
        capability: XLDialectCapabilities
    )
    case parameterCodecDialectMismatch(
        parameter: XLStaticQueryParameterMetadata,
        expected: XLDialectIdentifier,
        actual: XLDialectIdentifier
    )
    case parameterCodecStorageMismatch(
        parameter: XLStaticQueryParameterMetadata,
        codecStorageIdentifier: XLValueStorageIdentifier
    )
    case resultCodecDialectMismatch(
        result: XLStaticQueryResultSlot,
        expected: XLDialectIdentifier,
        actual: XLDialectIdentifier
    )

    public var errorDescription: String? {
        switch self {
        case .emptyDefinitionPath:
            return "A static query definition identity requires at least one path component."
        case .emptyDefinitionPathComponent(let index):
            return "Static query definition identity has an empty path component at index \(index)."
        case .emptySlotPath:
            return "A static query slot identity requires at least one path component."
        case .emptySlotPathComponent(let index):
            return "Static query slot identity has an empty path component at index \(index)."
        case .unsupportedIdentityFormatVersion(let version):
            return "Static query identity format version \(version) is unsupported."
        case .definitionIdentityCollision(let definition, _, _):
            return "Static query definition \(definition) names different canonical query contracts; increment its definition version."
        case .emptySQL:
            return "A static query statement cannot have empty SQL."
        case .emptyDialectIdentifier:
            return "A static query statement requires a stable dialect identifier."
        case .negativeDialectVersion(let version):
            return "Dialect minimum version \(version) cannot contain negative components."
        case .emptyEntity:
            return "A referenced entity identity cannot be empty."
        case .invalidResultIndex(let slot):
            return "Result slot \(slot.identity) has invalid index \(slot.index)."
        case .noncontiguousResultIndex(let slot, let expected):
            return "Result slot \(slot.identity) has noncontiguous index \(slot.index); expected \(expected)."
        case .conflictingResultIndex(let index, let existing, let incoming):
            return "Result index \(index) is declared by both \(existing.identity) and \(incoming.identity)."
        case .conflictingResultIdentity(let identity, let existing, let incoming):
            return "Result identity \(identity) has conflicting declarations at indices \(existing.index) and \(incoming.index)."
        case .emptyValueTypeIdentifier(let slot):
            return "Static query slot \(slot) requires a stable value type identifier."
        case .emptyStorageIdentifier(let slot):
            return "Static query slot \(slot) requires a stable storage identifier."
        case .invalidResultCodingSite(let result, let actual):
            return "Static result \(result.identity) has coding site \(actual.rawValue); expected result or property."
        case .resultCodecValueTypeMismatch(let slot, let codecValueTypeIdentifier):
            return "Result slot \(slot.identity) has value type \(slot.valueTypeIdentifier), but its codec targets \(codecValueTypeIdentifier)."
        case .resultCodecStorageMismatch(let slot, let codecStorageIdentifier):
            return "Result slot \(slot.identity) has storage \(slot.storageIdentifier), but its codec uses \(codecStorageIdentifier)."
        case .commandHasResults(let results):
            return "Command cardinality cannot declare \(results.count) result slots."
        case .rowQueryHasNoResults(let cardinality):
            return "Row cardinality \(cardinality) requires at least one result slot."
        case .parameterMetadataCountMismatch(let expected, let actual):
            return "Static query parameter metadata count \(actual) does not match statement parameter count \(expected)."
        case .parameterNotInStatement(let parameter):
            return "Static parameter \(parameter.identity) is not in the statement parameter layout."
        case .parameterSlotMismatch(let expected, let actual):
            return "Static parameter \(actual.key) does not match statement slot \(expected.key) at logical index \(expected.index)."
        case .duplicateParameterIndex(let index):
            return "Static query parameter index \(index) is declared more than once."
        case .duplicateParameterIdentity(let identity):
            return "Static query parameter identity \(identity) is declared more than once."
        case .invalidParameterCodingSite(let parameter, let actual):
            return "Static parameter \(parameter.identity) has coding site \(actual.rawValue); expected parameter."
        case .emptyNamedBindingKey:
            return "A static query parameter cannot use an empty named binding key."
        case .invalidIndexedBindingKey(let slot):
            return "Static query parameter \(slot.key) uses a negative indexed binding key."
        case .parameterCapabilityMissing(let parameter, let capability):
            return "Static parameter \(parameter.identity) requires dialect capability \(capability.rawValue)."
        case .parameterCodecDialectMismatch(let parameter, let expected, let actual):
            return "Static parameter \(parameter.identity) requires codec dialect \(actual), not statement dialect \(expected)."
        case .parameterCodecStorageMismatch(let parameter, let codecStorageIdentifier):
            return "Static parameter \(parameter.identity) has storage \(parameter.storageIdentifier), but its codec uses \(codecStorageIdentifier)."
        case .resultCodecDialectMismatch(let result, let expected, let actual):
            return "Static result \(result.identity) requires codec dialect \(actual), not statement dialect \(expected)."
        }
    }
}


private enum XLStaticQueryIdentityEncoder {

    private static let domain = Array("SwiftQL.StaticQueryIdentity".utf8)

    static func encodeV1(
        definitionIdentity: XLQueryDefinitionIdentity,
        statement: XLStaticStatementDefinition,
        parameters: [XLStaticQueryParameterMetadata],
        results: XLStaticQueryResultMetadata,
        cardinality: XLQueryCardinality
    ) -> [UInt8] {
        var writer = XLCanonicalByteWriter()
        writer.bytes(domain)
        writer.byte(0)
        writer.uint16(XLQueryIdentityFormatVersion.v1.rawValue)

        // Metadata uses NFC so canonical-equivalent Swift strings encode to
        // the same durable identity material.
        writer.metadataStringArray(definitionIdentity.path)
        writer.uint64(definitionIdentity.version)

        // Rendered SQL remains exact and is deliberately not normalized.
        writer.string(statement.sql)
        writer.metadataString(statement.dialectRequirement.identity.rawValue)
        writer.optional(statement.dialectRequirement.minimumVersion) { writer, version in
            writer.uint64(UInt64(version.major))
            writer.uint64(UInt64(version.minor))
            writer.uint64(UInt64(version.patch))
        }
        writer.uint64(statement.dialectRequirement.capabilities.rawValue)

        writer.uint64(UInt64(parameters.count))
        for parameter in parameters {
            writer.metadataStringArray(parameter.identity.path)
            writer.uint64(UInt64(parameter.slot.index.rawValue))
            switch parameter.slot.key {
            case .named(let name):
                writer.byte(0)
                writer.metadataString(name)
            case .indexed(let index):
                writer.byte(1)
                writer.uint64(UInt64(index))
            }
            writer.metadataString(parameter.slot.valueTypeIdentifier.rawValue)
            writer.byte(parameter.slot.nullability == .required ? 0 : 1)
            writer.metadataString(parameter.storageIdentifier.rawValue)
        }

        writer.byte(cardinality.rawValue)
        writer.uint64(UInt64(results.count))
        for result in results.slots {
            writer.metadataStringArray(result.identity.path)
            writer.uint64(UInt64(result.index.rawValue))
            writer.metadataString(result.valueTypeIdentifier.rawValue)
            writer.byte(result.nullability == .required ? 0 : 1)
            writer.metadataString(result.storageIdentifier.rawValue)
        }

        let entities = statement.entities.map {
            $0.precomposedStringWithCanonicalMapping
        }.sorted { lhs, rhs in
            lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
        writer.uint64(UInt64(entities.count))
        for entity in entities {
            writer.metadataString(entity)
        }

        return writer.output
    }
}
