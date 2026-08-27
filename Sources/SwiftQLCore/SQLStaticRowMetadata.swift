//
//  SQLStaticRowMetadata.swift
//  SwiftQLCore
//
//  The immutable description of one statement's shape: its rendered SQL and
//  dialect requirement, its parameters, and the metadata for every value in a
//  row it returns.
//
//  Split out of SQLStaticQueryDescriptor.swift (issue #559).
//

import Foundation


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

        self.slots = try _xlCanonicalSlotOrder(
            Array(slotsByIndex.values),
            index: \.index,
            expectedIndex: { XLLogicalResultIndex($0) },
            noncontiguous: { slot, expected in
                XLStaticQueryError.noncontiguousResultIndex(
                    slot: slot,
                    expected: expected
                )
            }
        )
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
