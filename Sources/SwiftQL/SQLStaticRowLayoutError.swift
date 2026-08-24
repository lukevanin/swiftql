//
//  SQLStaticRowLayoutError.swift
//  SwiftQL
//
//  How a static row layout fails, and the diagnostic each failure prints.
//
//  Split out of SQLStaticRowLayout.swift (issue #559): describing a failure
//  well takes as much room as the machinery that detects it, and mixing the
//  two made both harder to read.
//

import Foundation


public enum XLStaticRowLayoutError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case fieldNotPositioned(identity: XLQuerySlotIdentity)
    case unsupportedSQLiteStorage(
        identity: XLQuerySlotIdentity,
        storageType: String
    )
    case expressionStorageTypeMismatch(
        identity: XLQuerySlotIdentity,
        expectedStorageType: String,
        expressionType: String
    )
    case valueCountMismatch(expected: Int, actual: Int)
    case nullForRequiredField(field: XLStaticRowField)
    case storageMismatch(
        field: XLStaticRowField,
        actual: XLValueStorageIdentifier
    )
    case descriptorResultsMismatch(
        expected: XLStaticQueryResultMetadata,
        actual: XLStaticQueryResultMetadata
    )

    public var errorDescription: String? {
        switch self {
        case .fieldNotPositioned(let identity):
            return "Static result slot \(identity) must be positioned by its generated row-layout factory before use."
        case .unsupportedSQLiteStorage(let identity, let storageType):
            return "Static result slot \(identity) uses storage carrier \(storageType), whose SQLite storage class is not statically known."
        case .expressionStorageTypeMismatch(
            let identity,
            let expectedStorageType,
            let expressionType
        ):
            return "Static result slot \(identity) requires an expression typed as storage carrier \(expectedStorageType), but received \(expressionType)."
        case .valueCountMismatch(let expected, let actual):
            return "Static row layout expected \(expected) values, but received \(actual)."
        case .nullForRequiredField(let field):
            return "Static row property/result slot '\(field.alias)' (\(field.result.identity), codec \(Self.codecDescription(field))) received SQL NULL but is required."
        case .storageMismatch(let field, let actual):
            return "Static row property/result slot '\(field.alias)' (\(field.result.identity), codec \(Self.codecDescription(field))) requires storage \(field.result.storageIdentifier), not \(actual)."
        case .descriptorResultsMismatch(let expected, let actual):
            return Self.descriptorResultsMismatchDescription(
                expected: expected,
                actual: actual
            )
        }
    }

    private static func codecDescription(_ field: XLStaticRowField) -> String {
        field.result.codecIdentity?.key.description ?? "intrinsic/none"
    }

    private static func descriptorResultsMismatchDescription(
        expected: XLStaticQueryResultMetadata,
        actual: XLStaticQueryResultMetadata
    ) -> String {
        let sharedCount = min(expected.slots.count, actual.slots.count)
        for position in 0..<sharedCount {
            let expectedSlot = expected.slots[position]
            let actualSlot = actual.slots[position]
            guard expectedSlot != actualSlot else {
                continue
            }
            return descriptorResultsMismatchDescription(
                position: position,
                expected: expectedSlot,
                actual: actualSlot,
                expectedCount: expected.slots.count,
                actualCount: actual.slots.count
            )
        }

        if expected.slots.count > sharedCount {
            return descriptorResultsMismatchDescription(
                position: sharedCount,
                expected: expected.slots[sharedCount],
                actual: nil,
                expectedCount: expected.slots.count,
                actualCount: actual.slots.count
            )
        }
        if actual.slots.count > sharedCount {
            return descriptorResultsMismatchDescription(
                position: sharedCount,
                expected: nil,
                actual: actual.slots[sharedCount],
                expectedCount: expected.slots.count,
                actualCount: actual.slots.count
            )
        }

        return "Typed static query result metadata does not match its row layout, but no differing result slot could be identified."
    }

    private static func descriptorResultsMismatchDescription(
        position: Int,
        expected: XLStaticQueryResultSlot?,
        actual: XLStaticQueryResultSlot?,
        expectedCount: Int,
        actualCount: Int
    ) -> String {
        [
            "Typed static query result metadata does not match its row layout.",
            "First differing result position \(position):",
            "expected descriptor slot \(slotDescription(expected));",
            "actual layout slot \(slotDescription(actual)).",
            "Result counts: expected \(expectedCount), actual \(actualCount).",
        ].joined(separator: " ")
    }

    private static func slotDescription(
        _ slot: XLStaticQueryResultSlot?
    ) -> String {
        guard let slot else {
            return "<missing>"
        }
        let codec: String
        if let identity = slot.codecIdentity {
            codec = "\(identity.key.description) { " + [
                "value type: \(identity.valueTypeIdentifier)",
                "dialect: \(identity.dialectIdentifier)",
                "storage: \(identity.storageIdentifier)",
            ].joined(separator: ", ") + " }"
        }
        else {
            codec = "intrinsic/none"
        }
        return "{ " + [
            "index: \(slot.index)",
            "identity: \(slot.identity)",
            "type: \(slot.valueTypeName) [\(slot.valueTypeIdentifier)]",
            "nullability: \(slot.nullability.rawValue)",
            "codec: \(codec)",
            "storage: \(slot.storageIdentifier)",
            "coding context: \(slot.codingContext.site.rawValue):\(slot.codingContext.path)",
        ].joined(separator: ", ") + " }"
    }
}


/// One typed projected expression and its immutable result-codec behavior.
///
/// A field created by a value-coding configuration is value-free. It retains
/// an expression, stable descriptor metadata, and stateless conversion
/// closures, but never a model instance, database, SQL reader, or invocation
/// value. Generated row-layout factories assign its declaration position and
/// SQL alias.
