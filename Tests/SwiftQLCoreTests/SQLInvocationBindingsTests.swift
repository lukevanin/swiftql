import Foundation
import XCTest

import SwiftQLCore


final class SQLInvocationBindingsTests: XCTestCase {

    func testIndexFreeDeclarationProducesLosslessIndexedSlot() {
        let declaration = XLParameterDeclaration(
            key: .named("token"),
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: String(reflecting: InvocationToken.self),
            nullability: .nullable,
            codecIdentity: codecIdentity,
            codingContext: parameterContext
        )

        let slot = declaration.slot(at: XLLogicalParameterIndex(7))

        XCTAssertEqual(slot.index, XLLogicalParameterIndex(7))
        XCTAssertEqual(slot.declaration, declaration)

        let error = XLInvocationBindingError.parameterDeclarationNotInLayout(
            declaration: declaration
        )
        XCTAssertTrue(error.localizedDescription.contains("named(\"token\")"))
        XCTAssertTrue(error.localizedDescription.contains(codecKey.description))
        XCTAssertTrue(error.localizedDescription.contains(parameterContext.description))
    }

    func testDiagnosticTypeNamesDoNotAffectStableParameterIdentity() throws {
        let firstDeclaration = XLParameterDeclaration(
            key: .named("token"),
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: "OriginalModule.InvocationToken",
            nullability: .nullable,
            codecIdentity: codecIdentity,
            codingContext: parameterContext
        )
        let renamedDeclaration = XLParameterDeclaration(
            key: .named("token"),
            valueTypeIdentifier: valueTypeIdentifier,
            valueTypeName: "RenamedModule.InvocationToken",
            nullability: .nullable,
            codecIdentity: codecIdentity,
            codingContext: parameterContext
        )

        XCTAssertEqual(firstDeclaration, renamedDeclaration)
        XCTAssertEqual(Set([firstDeclaration, renamedDeclaration]).count, 1)

        let firstSlot = firstDeclaration.slot(at: XLLogicalParameterIndex(0))
        let renamedSlot = renamedDeclaration.slot(at: XLLogicalParameterIndex(0))
        XCTAssertEqual(firstSlot, renamedSlot)
        XCTAssertEqual(Set([firstSlot, renamedSlot]).count, 1)

        let coalesced = try XLParameterLayout(slots: [firstSlot, renamedSlot])
        XCTAssertEqual(coalesced.count, 1)
        XCTAssertEqual(coalesced.slots[0].valueTypeName, firstDeclaration.valueTypeName)
        XCTAssertEqual(
            coalesced,
            try XLParameterLayout(slots: [renamedSlot])
        )
    }

    func testLayoutCanonicalizesIndicesAndCoalescesIdenticalOccurrences() throws {
        let first = slot(index: 0, key: .named("first"))
        let second = slot(index: 1, key: .named("second"))

        let layout = try XLParameterLayout(
            slots: [second, first, first, second]
        )

        XCTAssertEqual(layout.slots, [first, second])
        XCTAssertEqual(layout.slot(at: XLLogicalParameterIndex(0)), first)
        XCTAssertEqual(layout.slot(for: .named("second")), second)
        XCTAssertEqual(layout.count, 2)
        XCTAssertFalse(layout.isEmpty)
        XCTAssertEqual(XLParameterLayout.empty.slots, [])
    }

    func testLayoutRejectsInvalidAndConflictingDeclarations() throws {
        let invalid = slot(index: -1, key: .named("invalid"))
        assertBindingError(
            try XLParameterLayout(slots: [invalid]),
            equals: .invalidParameterIndex(slot: invalid)
        )

        let first = slot(index: 0, key: .named("first"))
        let conflictingIndex = slot(index: 0, key: .named("second"))
        assertBindingError(
            try XLParameterLayout(slots: [first, conflictingIndex]),
            equals: .conflictingParameterIndex(
                index: XLLogicalParameterIndex(0),
                existing: first,
                incoming: conflictingIndex
            )
        )

        let conflictingKey = slot(index: 1, key: .named("first"))
        assertBindingError(
            try XLParameterLayout(slots: [first, conflictingKey]),
            equals: .conflictingParameterKey(
                key: .named("first"),
                existing: first,
                incoming: conflictingKey
            )
        )
    }

    func testLayoutRejectsNoncontiguousCanonicalIndices() {
        let firstGap = slot(index: 1, key: .named("gap"))

        assertBindingError(
            try XLParameterLayout(slots: [firstGap]),
            equals: .noncontiguousParameterIndex(
                slot: firstGap,
                expected: XLLogicalParameterIndex(0)
            )
        )

        let first = slot(index: 0, key: .named("first"))
        let laterGap = slot(index: 2, key: .named("laterGap"))
        assertBindingError(
            try XLParameterLayout(slots: [laterGap, first]),
            equals: .noncontiguousParameterIndex(
                slot: laterGap,
                expected: XLLogicalParameterIndex(1)
            )
        )
    }

    func testLayoutRejectsCodecWhoseStableValueTypeDoesNotMatchSlot() throws {
        let identity = XLValueCodecIdentity(
            key: codecKey,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "other-type"),
            dialectIdentifier: InvocationTestDialect.identity,
            storageIdentifier: storageIdentifier(.text)
        )
        let mismatched = slot(
            index: 0,
            key: .named("value"),
            codecIdentity: identity
        )

        assertBindingError(
            try XLParameterLayout(slots: [mismatched]),
            equals: .codecValueTypeMismatch(
                slot: mismatched,
                codecValueTypeIdentifier: identity.valueTypeIdentifier
            )
        )
    }

    func testPacketIsCanonicalAndDistinguishesMissingFromExplicitNull() throws {
        let first = slot(index: 0, key: .named("first"))
        let second = slot(
            index: 1,
            key: .named("second"),
            nullability: .nullable
        )
        let layout = try XLParameterLayout(slots: [second, first])
        let empty = XLInvocationBindings<InvocationTestValue>(layout: layout)

        XCTAssertNil(empty.binding(at: first.index))
        XCTAssertEqual(empty.missingSlots, [first, second])
        XCTAssertFalse(empty.isComplete)

        let packet = try XLInvocationBindings<InvocationTestValue>(
            layout: layout,
            bindings: [
                try XLInvocationBinding<InvocationTestValue>(
                    slot: second,
                    value: .null
                ),
                try XLInvocationBinding<InvocationTestValue>(
                    slot: first,
                    value: .text("present")
                ),
            ]
        )

        XCTAssertEqual(packet.bindings.map(\.slot), [first, second])
        XCTAssertEqual(packet.binding(for: .named("second"))?.value, .null)
        XCTAssertEqual(packet.missingSlots, [])
        XCTAssertTrue(packet.isComplete)
        XCTAssertEqual(try packet.validatingComplete(), packet)

        let erased: any XLInvocationBindingPacket = packet
        XCTAssertEqual(erased.layout, layout)
        XCTAssertEqual(erased.bindingCount, 2)
        XCTAssertTrue(erased.isComplete)
        XCTAssertNotNil(erased as? XLInvocationBindings<InvocationTestValue>)
    }

    func testPacketRejectsUnknownMismatchedDuplicateAndMissingBindings() throws {
        let declared = slot(index: 0, key: .named("declared"))
        let layout = try XLParameterLayout(slots: [declared])
        let empty = XLInvocationBindings<InvocationTestValue>(layout: layout)
        let unknown = slot(index: 1, key: .named("unknown"))

        let mismatch = XLInvocationBindingError.packetLayoutMismatch(
            expected: layout,
            actual: .empty
        )
        XCTAssertEqual(
            mismatch.localizedDescription,
            "Invocation parameter count 0 does not match prepared parameter count 1."
        )

        let equalCountLayout = try XLParameterLayout(
            slots: [slot(index: 0, key: .named("other"))]
        )
        let equalCountMismatch = XLInvocationBindingError.packetLayoutMismatch(
            expected: layout,
            actual: equalCountLayout
        )
        XCTAssertEqual(
            equalCountMismatch.localizedDescription,
            "Invocation parameter layout does not match the prepared layout; both contain the same number of parameters (1)."
        )

        assertBindingError(
            try empty.binding(.text("unknown"), to: unknown),
            equals: .parameterNotInLayout(slot: unknown)
        )

        let mismatched = XLParameterSlot(
            index: declared.index,
            key: declared.key,
            valueTypeIdentifier: declared.valueTypeIdentifier,
            valueTypeName: declared.valueTypeName,
            nullability: .nullable,
            codecIdentity: declared.codecIdentity,
            codingContext: declared.codingContext
        )
        assertBindingError(
            try empty.binding(.text("mismatch"), to: mismatched),
            equals: .parameterMetadataMismatch(
                expected: declared,
                actual: mismatched
            )
        )

        let bound = try empty.binding(.text("first"), to: declared)
        assertBindingError(
            try bound.binding(.text("second"), to: declared),
            equals: .duplicateBinding(slot: declared)
        )
        assertBindingError(
            try empty.validatingComplete(),
            equals: .missingBindings(slots: [declared])
        )
    }

    func testRawBindingRejectsCodecSlotButAcceptsIntrinsicSlot() throws {
        let contextual = slot(
            index: 0,
            key: .named("contextual"),
            codecIdentity: codecIdentity
        )
        assertBindingError(
            try XLInvocationBinding(
                slot: contextual,
                value: InvocationTestValue.text("forged")
            ),
            equals: .codecBindingRequiresPreparedParameter(
                slot: contextual,
                codecIdentity: codecIdentity
            )
        )

        let intrinsic = slot(
            index: 0,
            key: .named("intrinsic"),
            codecIdentity: nil
        )
        let binding = try XLInvocationBinding(
            slot: intrinsic,
            value: InvocationTestValue.text("raw")
        )
        XCTAssertEqual(binding.slot, intrinsic)
        XCTAssertEqual(binding.value, .text("raw"))
    }

    func testSlotBearingCodecValidationErrorsRetainContext() {
        let contextual = slot(
            index: 0,
            key: .named("contextual"),
            codecIdentity: codecIdentity
        )
        let actualIdentity = XLValueCodecIdentity(
            key: XLValueCodecKey(id: "swiftql.tests.actual", version: 2),
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: InvocationTestDialect.identity,
            storageIdentifier: storageIdentifier(.text)
        )
        let expectedDialect = XLDialectIdentifier(rawValue: "swiftql.tests.other")
        let actualStorage = storageIdentifier(.null)

        let errors: [XLInvocationBindingError] = [
            .preparedCodecUnavailable(
                slot: contextual,
                codecIdentity: codecIdentity
            ),
            .preparedCodecIdentityMismatch(
                slot: contextual,
                expected: codecIdentity,
                actual: actualIdentity
            ),
            .preparedCodecDialectMismatch(
                slot: contextual,
                codecIdentity: codecIdentity,
                expectedDialectIdentifier: expectedDialect
            ),
            .dialectValueStorageMismatch(
                slot: contextual,
                expectedCodecIdentity: codecIdentity,
                actualStorageIdentifier: actualStorage
            ),
        ]

        for error in errors {
            XCTAssertTrue(error.localizedDescription.contains("named(\"contextual\")"))
            XCTAssertTrue(error.localizedDescription.contains(contextual.codingContext.description))
        }
    }

    func testPreparedParameterEncodesThroughResolvedCodecAndMakesNullPresent() throws {
        let nullable = try preparedParameter(
            index: 0,
            key: .named("token"),
            nullability: .nullable
        )

        let encoded = try nullable.encode(InvocationToken(rawValue: 42))
        XCTAssertEqual(encoded.slot, nullable.slot)
        XCTAssertEqual(encoded.value, .text("token:42"))
        XCTAssertEqual(nullable.codecIdentity, codecIdentity)
        XCTAssertEqual(nullable.codingContext, parameterContext)

        let encodedNull = try nullable.encodeOptional(nil)
        XCTAssertEqual(encodedNull.value, .null)
        let layout = try XLParameterLayout(slots: [nullable.slot])
        let packet = try XLInvocationBindings(
            layout: layout,
            bindings: [encodedNull]
        )
        XCTAssertNotNil(packet.binding(at: nullable.slot.index))
        XCTAssertEqual(packet.binding(at: nullable.slot.index)?.value, .null)

        let required = try preparedParameter(
            index: 0,
            key: .named("required"),
            nullability: .required
        )
        assertBindingError(
            try required.encodeOptional(nil),
            equals: .nullForRequiredParameter(slot: required.slot)
        )
    }

    func testPreparedParameterRetainsSlotCodecAndContextInEncodingFailure() throws {
        let parameter = try preparedParameter(
            index: 3,
            key: .named("failing"),
            nullability: .required
        )

        XCTAssertThrowsError(try parameter.encode(InvocationToken(rawValue: -1))) { error in
            guard case .codecEncodingFailed(
                let slot,
                let identity,
                let context,
                let message
            ) = error as? XLInvocationBindingError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(slot, parameter.slot)
            XCTAssertEqual(identity, codecIdentity)
            XCTAssertEqual(context, parameterContext)
            XCTAssertTrue(message.contains("negativeToken"))
        }
    }

    func testPreparedParameterBuildsIsolatedPacketsAcrossConcurrentCalls() async throws {
        let parameter = try preparedParameter(
            index: 0,
            key: .named("token"),
            nullability: .required
        )
        let layout = try XLParameterLayout(slots: [parameter.slot])

        let values = try await withThrowingTaskGroup(
            of: InvocationTestValue.self,
            returning: [InvocationTestValue].self
        ) { group in
            for index in 0 ..< 32 {
                group.addTask {
                    let binding = try parameter.encode(
                        InvocationToken(rawValue: index)
                    )
                    let packet = try XLInvocationBindings(
                        layout: layout,
                        bindings: [binding]
                    )
                    return try packet.validatingComplete().bindings[0].value
                }
            }

            var values: [InvocationTestValue] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(
            Set(values),
            Set((0 ..< 32).map { .text("token:\($0)") })
        )
    }
}


private let valueTypeIdentifier = XLValueTypeIdentifier(
    rawValue: "swiftql.tests.invocation-token"
)

private let codecKey = XLValueCodecKey(
    id: "swiftql.tests.invocation-token.text",
    version: 1
)

private let parameterContext = XLValueCodingContext(
    site: .parameter,
    path: XLValueCodingPath(["query", "token"])
)

private var codecIdentity: XLValueCodecIdentity {
    XLValueCodecIdentity(
        key: codecKey,
        valueTypeIdentifier: valueTypeIdentifier,
        dialectIdentifier: InvocationTestDialect.identity,
        storageIdentifier: storageIdentifier(.text)
    )
}


private struct InvocationToken {
    let rawValue: Int
}


private enum InvocationTestFailure: Error {
    case negativeToken
    case invalidValue
}


private enum InvocationTestStorage: String, Hashable, Sendable {
    case null
    case text
}


private enum InvocationTestValue: Hashable, Sendable, XLDialectValue {
    case null
    case text(String)

    var storageType: InvocationTestStorage {
        switch self {
        case .null:
            return .null
        case .text:
            return .text
        }
    }
}


private struct InvocationTestDialect: XLValueCodingDialect {

    typealias Value = InvocationTestValue

    static let identity = XLDialectIdentifier(
        rawValue: "swiftql.tests.invocation-dialect"
    )

    let descriptor = XLDialectDescriptor(
        identity: identity,
        capabilities: [.namedBindings, .indexedBindings]
    )

    func formatIdentifier(_ identifier: String) -> String {
        identifier
    }

    func formatQualifiedIdentifier(_ components: [String]) -> String {
        components.joined(separator: ".")
    }

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        switch placeholder {
        case .named(let name):
            return ":\(name)"
        case .indexed(let index):
            return "?\(index)"
        }
    }

    func isNull(_ value: InvocationTestValue) -> Bool {
        value == .null
    }

    var nullValue: InvocationTestValue {
        .null
    }

    func stableStorageIdentifier(
        for value: InvocationTestValue
    ) -> XLValueStorageIdentifier {
        storageIdentifier(value.storageType)
    }
}


private func slot(
    index: Int,
    key: XLBindingKey,
    nullability: XLParameterNullability = .required,
    codecIdentity: XLValueCodecIdentity? = nil
) -> XLParameterSlot {
    XLParameterSlot(
        index: XLLogicalParameterIndex(index),
        key: key,
        valueTypeIdentifier: valueTypeIdentifier,
        valueTypeName: String(reflecting: InvocationToken.self),
        nullability: nullability,
        codecIdentity: codecIdentity,
        codingContext: XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(String(describing: key))
        )
    )
}


private func preparedParameter(
    index: Int,
    key: XLBindingKey,
    nullability: XLParameterNullability
) throws -> XLPreparedParameter<InvocationToken, InvocationTestDialect> {
    let codec = XLValueCodec<InvocationToken, InvocationTestDialect>(
        key: codecKey,
        valueTypeIdentifier: valueTypeIdentifier,
        dialectIdentifier: InvocationTestDialect.identity,
        storageIdentifier: storageIdentifier(.text),
        encode: { value, _, _ in
            guard value.rawValue >= 0 else {
                throw InvocationTestFailure.negativeToken
            }
            return .text("token:\(value.rawValue)")
        },
        decode: { value, _, _ in
            guard case .text(let text) = value,
                  text.hasPrefix("token:"),
                  let rawValue = Int(text.dropFirst("token:".count)) else {
                throw InvocationTestFailure.invalidValue
            }
            return InvocationToken(rawValue: rawValue)
        }
    )
    let configuration = try XLValueCodingConfiguration(
        registry: XLValueCodecRegistry().registering(codec)
    )
    let resolved = try configuration.resolvedCodec(
        for: InvocationToken.self,
        using: InvocationTestDialect(),
        context: parameterContext,
        selection: XLValueCodecSelection(explicitCodecKey: codecKey)
    )
    return XLPreparedParameter(
        index: XLLogicalParameterIndex(index),
        key: key,
        nullability: nullability,
        codec: resolved
    )
}


private func storageIdentifier(
    _ storage: InvocationTestStorage
) -> XLValueStorageIdentifier {
    XLValueStorageIdentifier(rawValue: storage.rawValue)
}


private func assertBindingError<T>(
    _ expression: @autoclosure () throws -> T,
    equals expected: XLInvocationBindingError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(
        try expression(),
        file: file,
        line: line
    ) { error in
        XCTAssertEqual(
            error as? XLInvocationBindingError,
            expected,
            file: file,
            line: line
        )
    }
}
