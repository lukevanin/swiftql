import Foundation


/// A durable, human-assigned identity for one static query definition.
///
/// The path identifies the declaration independently of Swift module and type
/// spellings. Increment `version` whenever that named declaration adopts a new
/// canonical query contract, or when it intentionally becomes a new logical
/// query even if its current SQL happens to remain unchanged.
public struct XLQueryDefinitionIdentity:
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let path: [String]

    public let version: UInt64

    public init(path: [String], version: UInt64) throws {
        try _xlValidateStablePath(path, kind: .definition)
        self.path = path
        self.version = version
    }

    public var description: String {
        "\(path.joined(separator: "/"))@\(version)"
    }
}


/// A durable logical identity for one property, parameter, or result slot.
///
/// This is intentionally separate from ``XLValueCodingContext``. Coding
/// contexts are diagnostic paths and may change without changing a query's
/// static SQL or value layout contract.
public struct XLQuerySlotIdentity:
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let path: [String]

    public init(path: [String]) throws {
        try _xlValidateStablePath(path, kind: .slot)
        self.path = path
    }

    public var description: String {
        path.joined(separator: "/")
    }
}


/// The number of rows a static query promises to expose to its caller.
public enum XLQueryCardinality: UInt8, Hashable, Sendable {
    /// A statement executed for its effects without a returned row layout.
    case command = 0

    /// A query that must produce exactly one row.
    case exactlyOne = 1

    /// A query that may produce zero or one row, but never more than one.
    case zeroOrOne = 2

    /// A query that may produce any number of rows.
    case many = 3
}


/// The version of SwiftQL's canonical static-query identity representation.
///
/// Version 1 is frozen. Changing field inclusion, ordering, tags, integer
/// encoding, or string canonicalization requires a new format version.
public struct XLQueryIdentityFormatVersion:
    RawRepresentable,
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public static let v1 = Self(rawValue: 1)

    public static let current = Self.v1

    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public var description: String {
        String(rawValue)
    }
}


/// A collision-safe, cross-process identity for one static query contract.
///
/// `canonicalBytes` is the durable identity. It is produced by a frozen binary
/// encoder and contains the complete identity material instead of a truncated
/// or randomized hash. The `Hashable` conformance is only an in-process
/// collection convenience; never persist `hashValue`.
public struct XLQueryIdentity:
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let formatVersion: XLQueryIdentityFormatVersion

    public let definitionIdentity: XLQueryDefinitionIdentity

    public let canonicalBytes: [UInt8]

    package init(
        formatVersion: XLQueryIdentityFormatVersion,
        definitionIdentity: XLQueryDefinitionIdentity,
        canonicalBytes: [UInt8]
    ) {
        self.formatVersion = formatVersion
        self.definitionIdentity = definitionIdentity
        self.canonicalBytes = canonicalBytes
    }

    /// A stable lowercase hexadecimal spelling suitable for diagnostics and
    /// persisted cache metadata.
    public var canonicalHex: String {
        let digits = Array("0123456789abcdef".utf8)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(canonicalBytes.count * 2)
        for byte in canonicalBytes {
            encoded.append(digits[Int(byte >> 4)])
            encoded.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    public var description: String {
        "swiftql-query-v\(formatVersion.rawValue)-\(canonicalHex)"
    }

    /// Verifies that one durable definition path/version still names the same
    /// canonical query contract.
    ///
    /// Reusing a definition identity for different canonical material is an
    /// explicit collision and fails closed. Incrementing the definition
    /// version produces a distinct identity and does not conflict.
    public func validateDefinitionCompatibility(
        with other: Self
    ) throws {
        guard definitionIdentity == other.definitionIdentity else {
            return
        }
        guard canonicalBytes == other.canonicalBytes else {
            throw XLStaticQueryError.definitionIdentityCollision(
                definition: definitionIdentity,
                existing: self,
                incoming: other
            )
        }
    }
}


/// A rendered, database-independent SQL statement definition.
///
/// The statement captures only static SQL and its logical requirements. It
/// never owns a database, driver, physical statement, codec registry, or
/// invocation values.
public struct XLStaticStatementDefinition: Hashable, Sendable {

    public let sql: String

    public let dialectRequirement: XLDialectRequirement

    public let entities: Set<String>

    public let parameterLayout: XLParameterLayout

    public init(
        sql: String,
        dialectRequirement: XLDialectRequirement,
        entities: Set<String> = [],
        parameterLayout: XLParameterLayout = .empty
    ) {
        self.sql = sql
        self.dialectRequirement = dialectRequirement
        self.entities = entities
        self.parameterLayout = parameterLayout
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        _xlExactUTF8Equal(lhs.sql, rhs.sql)
            && lhs.dialectRequirement == rhs.dialectRequirement
            && lhs.entities == rhs.entities
            && lhs.parameterLayout == rhs.parameterLayout
    }

    public func hash(into hasher: inout Hasher) {
        _xlHashExactUTF8(sql, into: &hasher)
        hasher.combine(dialectRequirement)
        hasher.combine(entities)
        hasher.combine(parameterLayout)
    }
}


/// Static descriptor metadata for one invocation parameter.
///
/// `slot` retains the complete selected codec identity and coding context used
/// by prepared handles. Stable query identity projects only the logical slot,
/// value type, nullability, and storage contract, so changing a codec key or
/// diagnostic context without changing SQL/layout/capabilities does not churn
/// query identity.
public struct XLStaticQueryParameterMetadata: Hashable, Sendable {

    public let identity: XLQuerySlotIdentity

    public let slot: XLParameterSlot

    public let storageIdentifier: XLValueStorageIdentifier

    public init(
        identity: XLQuerySlotIdentity,
        slot: XLParameterSlot,
        storageIdentifier: XLValueStorageIdentifier
    ) {
        self.identity = identity
        self.slot = slot
        self.storageIdentifier = storageIdentifier
    }
}


/// The stable zero-based position of one value in a returned row.
public struct XLLogicalResultIndex:
    RawRepresentable,
    Comparable,
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.init(rawValue: rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        String(rawValue)
    }
}


/// Static metadata for one value in a returned row.
///
/// Each selected property or direct output column is represented by one flat
/// result slot. Generated static row metadata composes these slots without
/// changing their frozen query-identity representation.
public struct XLStaticQueryResultSlot: Hashable, Sendable {

    public let index: XLLogicalResultIndex

    public let identity: XLQuerySlotIdentity

    public let valueTypeIdentifier: XLValueTypeIdentifier

    /// A diagnostic Swift type spelling excluded from stable query identity.
    public let valueTypeName: String

    public let nullability: XLParameterNullability

    /// The selected codec retained for result decoding. Its key and version are
    /// excluded from query identity when the storage contract is unchanged.
    public let codecIdentity: XLValueCodecIdentity?

    public let storageIdentifier: XLValueStorageIdentifier

    /// Diagnostic codec context excluded from stable query identity.
    public let codingContext: XLValueCodingContext

    public init(
        index: XLLogicalResultIndex,
        identity: XLQuerySlotIdentity,
        valueTypeIdentifier: XLValueTypeIdentifier,
        valueTypeName: String,
        nullability: XLParameterNullability,
        codecIdentity: XLValueCodecIdentity?,
        storageIdentifier: XLValueStorageIdentifier,
        codingContext: XLValueCodingContext
    ) {
        self.index = index
        self.identity = identity
        self.valueTypeIdentifier = valueTypeIdentifier
        self.valueTypeName = valueTypeName
        self.nullability = nullability
        self.codecIdentity = codecIdentity
        self.storageIdentifier = storageIdentifier
        self.codingContext = codingContext
    }
}


/// Canonical immutable metadata for every value in a returned row.
public struct XLStaticQueryResultMetadata: Hashable, Sendable {

    public static let empty = Self(canonicalSlots: [])

    public let slots: [XLStaticQueryResultSlot]

    public init(slots: [XLStaticQueryResultSlot] = []) throws {
        var slotsByIndex: [XLLogicalResultIndex: XLStaticQueryResultSlot] = [:]
        var slotsByIdentity: [XLQuerySlotIdentity: XLStaticQueryResultSlot] = [:]

        for slot in slots {
            guard slot.index.rawValue >= 0 else {
                throw XLStaticQueryError.invalidResultIndex(slot: slot)
            }
            guard !slot.valueTypeIdentifier.rawValue.isEmpty else {
                throw XLStaticQueryError.emptyValueTypeIdentifier(
                    slot: slot.identity
                )
            }
            guard !slot.storageIdentifier.rawValue.isEmpty else {
                throw XLStaticQueryError.emptyStorageIdentifier(
                    slot: slot.identity
                )
            }
            guard slot.codingContext.site == .result
                    || slot.codingContext.site == .property else {
                throw XLStaticQueryError.invalidResultCodingSite(
                    result: slot,
                    actual: slot.codingContext.site
                )
            }
            if let existing = slotsByIndex[slot.index] {
                throw XLStaticQueryError.conflictingResultIndex(
                    index: slot.index,
                    existing: existing,
                    incoming: slot
                )
            }
            if let existing = slotsByIdentity[slot.identity] {
                throw XLStaticQueryError.conflictingResultIdentity(
                    identity: slot.identity,
                    existing: existing,
                    incoming: slot
                )
            }
            if let codecIdentity = slot.codecIdentity {
                guard codecIdentity.valueTypeIdentifier == slot.valueTypeIdentifier else {
                    throw XLStaticQueryError.resultCodecValueTypeMismatch(
                        slot: slot,
                        codecValueTypeIdentifier: codecIdentity.valueTypeIdentifier
                    )
                }
                guard codecIdentity.storageIdentifier == slot.storageIdentifier else {
                    throw XLStaticQueryError.resultCodecStorageMismatch(
                        slot: slot,
                        codecStorageIdentifier: codecIdentity.storageIdentifier
                    )
                }
            }
            slotsByIndex[slot.index] = slot
            slotsByIdentity[slot.identity] = slot
        }

        let canonicalSlots = slotsByIndex.values.sorted { lhs, rhs in
            lhs.index < rhs.index
        }
        for (offset, slot) in canonicalSlots.enumerated() {
            let expected = XLLogicalResultIndex(offset)
            guard slot.index == expected else {
                throw XLStaticQueryError.noncontiguousResultIndex(
                    slot: slot,
                    expected: expected
                )
            }
        }
        self.slots = canonicalSlots
    }

    private init(canonicalSlots: [XLStaticQueryResultSlot]) {
        self.slots = canonicalSlots
    }

    public var isEmpty: Bool {
        slots.isEmpty
    }

    public var count: Int {
        slots.count
    }

    public func slot(at index: XLLogicalResultIndex) -> XLStaticQueryResultSlot? {
        slots.first { $0.index == index }
    }

    public func slot(
        for identity: XLQuerySlotIdentity
    ) -> XLStaticQueryResultSlot? {
        slots.first { $0.identity == identity }
    }
}


/// Structural metadata for one property in a statically described row.
///
/// The field carries no expression, database value, or executable closure. It
/// is safe to retain in generated descriptors and can be inspected without
/// constructing the model that ultimately receives the value.
public struct XLStaticRowField: Hashable, Sendable {

    /// The SQL result alias generated for the property.
    public let alias: String

    /// The complete static result-slot contract for the property.
    public let result: XLStaticQueryResultSlot

    public init(alias: String, result: XLStaticQueryResultSlot) {
        self.alias = alias
        self.result = result
    }
}


/// An immutable, declaration-ordered structural description of a Swift row.
///
/// Validation deliberately happens before any operational row layout is
/// retained. Result-slot validation is delegated to
/// ``XLStaticQueryResultMetadata`` so a row and a static query share exactly
/// the same index, identity, nullability, value-type, codec, and storage
/// invariants.
public struct XLStaticRowMetadata: Hashable, Sendable {

    public static let empty = Self(
        canonicalFields: [],
        results: .empty
    )

    /// Fields in declaration and projection order.
    public let fields: [XLStaticRowField]

    /// Canonical result metadata for the same fields.
    public let results: XLStaticQueryResultMetadata

    public init(fields: [XLStaticRowField]) throws {
        var aliases: [String: XLStaticRowField] = [:]

        for (offset, field) in fields.enumerated() {
            let expected = XLLogicalResultIndex(offset)
            guard field.result.index == expected else {
                throw XLStaticRowMetadataError.fieldPositionMismatch(
                    field: field,
                    expected: expected
                )
            }

            let canonicalAlias = field.alias
                .precomposedStringWithCanonicalMapping
                .lowercased()
            guard !canonicalAlias.isEmpty else {
                throw XLStaticRowMetadataError.emptyFieldAlias(field: field)
            }
            if let existing = aliases[canonicalAlias] {
                throw XLStaticRowMetadataError.duplicateFieldAlias(
                    alias: field.alias,
                    existing: existing,
                    incoming: field
                )
            }
            aliases[canonicalAlias] = field
        }

        self.fields = fields
        self.results = try XLStaticQueryResultMetadata(
            slots: fields.map(\.result)
        )
    }

    private init(
        canonicalFields: [XLStaticRowField],
        results: XLStaticQueryResultMetadata
    ) {
        self.fields = canonicalFields
        self.results = results
    }
}


/// Deterministic row-layout validation failures.
public enum XLStaticRowMetadataError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case fieldPositionMismatch(
        field: XLStaticRowField,
        expected: XLLogicalResultIndex
    )
    case emptyFieldAlias(field: XLStaticRowField)
    case duplicateFieldAlias(
        alias: String,
        existing: XLStaticRowField,
        incoming: XLStaticRowField
    )

    public var errorDescription: String? {
        switch self {
        case .fieldPositionMismatch(let field, let expected):
            return "Static row property '\(field.alias)' (result slot \(field.result.identity), codec \(Self.codecDescription(field.result))) is at index \(field.result.index); expected declaration position \(expected)."
        case .emptyFieldAlias(let field):
            return "Static row result slot \(field.result.identity) (codec \(Self.codecDescription(field.result))) requires a nonempty property/result alias."
        case .duplicateFieldAlias(let alias, let existing, let incoming):
            return "Static row property/result alias '\(alias)' is declared by both result slot \(existing.result.identity) (codec \(Self.codecDescription(existing.result))) and result slot \(incoming.result.identity) (codec \(Self.codecDescription(incoming.result)))."
        }
    }

    private static func codecDescription(
        _ result: XLStaticQueryResultSlot
    ) -> String {
        result.codecIdentity?.key.description ?? "intrinsic/none"
    }
}


/// An immutable, database-independent static query contract.
///
/// Invocation values are deliberately absent. Callers create a fresh
/// ``XLInvocationBindings`` packet from `parameterLayout` for each execution.
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


private enum XLStablePathKind {
    case definition
    case slot
}


private func _xlValidateStablePath(
    _ path: [String],
    kind: XLStablePathKind
) throws {
    guard !path.isEmpty else {
        switch kind {
        case .definition:
            throw XLStaticQueryError.emptyDefinitionPath
        case .slot:
            throw XLStaticQueryError.emptySlotPath
        }
    }
    for (index, component) in path.enumerated() where component.isEmpty {
        switch kind {
        case .definition:
            throw XLStaticQueryError.emptyDefinitionPathComponent(index: index)
        case .slot:
            throw XLStaticQueryError.emptySlotPathComponent(index: index)
        }
    }
}


private func _xlValidate(_ version: XLDialectVersion?) throws {
    guard let version else {
        return
    }
    guard version.major >= 0, version.minor >= 0, version.patch >= 0 else {
        throw XLStaticQueryError.negativeDialectVersion(version)
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


private struct XLCanonicalByteWriter {

    private(set) var output: [UInt8] = []

    mutating func byte(_ value: UInt8) {
        output.append(value)
    }

    mutating func bytes(_ values: [UInt8]) {
        output.append(contentsOf: values)
    }

    mutating func uint16(_ value: UInt16) {
        output.append(UInt8((value >> 8) & 0xff))
        output.append(UInt8(value & 0xff))
    }

    mutating func uint64(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            output.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    mutating func string(_ value: String) {
        let bytes = Array(value.utf8)
        uint64(UInt64(bytes.count))
        self.bytes(bytes)
    }

    mutating func stringArray(_ values: [String]) {
        uint64(UInt64(values.count))
        for value in values {
            string(value)
        }
    }

    mutating func metadataString(_ value: String) {
        string(value.precomposedStringWithCanonicalMapping)
    }

    mutating func metadataStringArray(_ values: [String]) {
        uint64(UInt64(values.count))
        for value in values {
            metadataString(value)
        }
    }

    mutating func optional<Value>(
        _ value: Value?,
        write: (inout Self, Value) -> Void
    ) {
        guard let value else {
            byte(0)
            return
        }
        byte(1)
        write(&self, value)
    }
}


private func _xlExactUTF8Equal(_ lhs: String, _ rhs: String) -> Bool {
    Array(lhs.utf8) == Array(rhs.utf8)
}


private func _xlHashExactUTF8(_ value: String, into hasher: inout Hasher) {
    let bytes = Array(value.utf8)
    hasher.combine(bytes.count)
    for byte in bytes {
        hasher.combine(byte)
    }
}
