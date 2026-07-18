import Foundation
import XCTest

@testable import SwiftQL


final class SQLQueryCaptureTests: XCTestCase {

    private let encoder = XLiteEncoder(dialect: XLSQLiteDialect())

    func testIntrinsicCaptureRendersOneStablePlaceholderAndNoValue() throws {
        let identity = try XLQuerySlotIdentity(path: ["invoice", "customer/name"])
        let capture = try XLQueryCapture<String, String, XLSQLiteDialect>
            .intrinsic(identifiedBy: identity)

        let encoding = try encoder.makeValidatedSQL(
            sql { _ in Select(capture) }
        )
        let metadata = try capture.staticQueryParameter(in: encoding)

        guard case .named(let bindingName) = capture.declaration.key else {
            return XCTFail("Stable captures must use a named binding key")
        }
        XCTAssertEqual(encoding.sql, "SELECT :\(bindingName)")
        XCTAssertEqual(
            bindingName,
            "__swiftql_capture_00000000000000020000000000000007696e766f696365000000000000000d637573746f6d65722f6e616d65"
        )
        XCTAssertEqual(encoding.parameterLayout.count, 1)
        XCTAssertEqual(metadata.identity, identity)
        XCTAssertEqual(metadata.slot.index, XLLogicalParameterIndex(0))
        XCTAssertEqual(metadata.slot.codecIdentity, nil)
        XCTAssertEqual(
            metadata.storageIdentifier,
            XLValueStorageIdentifier(rawValue: "text")
        )
    }

    func testRepeatedCaptureSharesOneLogicalSlot() throws {
        let capture = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["repeated"])
        )
        let probe = CaptureProbe { builder in
            capture.makeSQL(context: &builder)
            capture.makeSQL(context: &builder)
            capture.makeSQL(context: &builder)
        }

        let encoding = try encoder.makeValidatedSQL(probe)

        XCTAssertEqual(encoding.parameterLayout.count, 1)
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.index),
            [XLLogicalParameterIndex(0)]
        )
    }

    func testDistinctCaptureOrderIsFirstTraversalOrderNotIdentityOrder() throws {
        let laterName = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["z"])
        )
        let earlierName = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["a"])
        )
        let probe = CaptureProbe { builder in
            laterName.makeSQL(context: &builder)
            earlierName.makeSQL(context: &builder)
            laterName.makeSQL(context: &builder)
        }

        let encoding = try encoder.makeValidatedSQL(probe)

        XCTAssertEqual(encoding.parameterLayout.count, 2)
        XCTAssertEqual(
            encoding.parameterLayout.slots.map(\.key),
            [laterName.declaration.key, earlierName.declaration.key]
        )
    }

    func testLengthPrefixedIdentityKeyAvoidsJoinedPathCollisions() throws {
        let slashComponent = try XLQueryCapture<Int, Int, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["a/b"])
            )
        let separateComponents = try XLQueryCapture<Int, Int, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["a", "b"])
            )

        XCTAssertNotEqual(
            slashComponent.declaration.key,
            separateComponents.declaration.key
        )
        let encoding = try encoder.makeValidatedSQL(
            CaptureProbe { builder in
                slashComponent.makeSQL(context: &builder)
                separateComponents.makeSQL(context: &builder)
            }
        )
        XCTAssertEqual(encoding.parameterLayout.count, 2)
    }

    func testCanonicalEquivalentIdentityComponentsProduceSameKey() throws {
        let composed = try XLQueryCapture<String, String, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["caf\u{00e9}"])
            )
        let decomposed = try XLQueryCapture<String, String, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["cafe\u{0301}"])
            )

        XCTAssertEqual(composed.declaration.key, decomposed.declaration.key)
    }

    func testReservedLookingLegacyBindingCannotCoalesceWithCapture() throws {
        let capture = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["reserved", "capture"])
        )
        guard case .named(let generatedName) = capture.declaration.key else {
            return XCTFail("Capture key must be named")
        }
        let legacy = XLNamedBindingReference<Int>(name: XLName(generatedName))
        let encoding = encoder.makeSQL(
            CaptureProbe { builder in
                capture.makeSQL(context: &builder)
                legacy.makeSQL(context: &builder)
            }
        )

        guard case .conflictingParameterIndex(_, let existing, let incoming)? =
                encoding.parameterLayoutError else {
            return XCTFail(
                "Expected generated-name collision to fail closed, got \(String(describing: encoding.parameterLayoutError))"
            )
        }
        XCTAssertEqual(existing.key, capture.declaration.key)
        XCTAssertEqual(incoming.key, capture.declaration.key)
    }

    func testSameIdentityWithConflictingContextualCodecsFailsRendering() throws {
        let firstCodec = captureTokenCodec(id: "tests.capture.first")
        let secondCodec = captureTokenCodec(id: "tests.capture.second")
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry()
                .registering(secondCodec)
                .registering(firstCodec)
        )
        let identity = try XLQuerySlotIdentity(path: ["codec", "conflict"])
        XCTAssertThrowsError(try configuration.queryCapture(
            CaptureToken?.self,
            expressedAs: String?.self,
            identifiedBy: identity,
            using: XLSQLiteDialect()
        )) { error in
            XCTAssertEqual(
                error as? XLQueryCaptureError,
                .optionalInputType(
                    identity: identity,
                    valueType: String(reflecting: CaptureToken?.self)
                )
            )
        }
        XCTAssertThrowsError(try configuration.queryCapture(
            CaptureToken.self,
            expressedAs: String.self,
            identifiedBy: identity,
            using: XLSQLiteDialect()
        )) { error in
            guard case .codecSelectionFailed(
                let actualIdentity,
                _,
                _,
                _,
                .inferred,
                let candidates,
                _,
                _
            ) = error as? XLQueryCaptureError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(actualIdentity, identity)
            XCTAssertEqual(
                candidates,
                [firstCodec.identity.key, secondCodec.identity.key]
            )
        }
        let first = try configuration.queryCapture(
            CaptureToken.self,
            expressedAs: String.self,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            selection: .explicit(firstCodec.identity.key)
        )
        let second = try configuration.queryCapture(
            CaptureToken.self,
            expressedAs: String.self,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            selection: .query(secondCodec.identity.key)
        )
        let encoding = encoder.makeSQL(
            CaptureProbe { builder in
                first.makeSQL(context: &builder)
                second.makeSQL(context: &builder)
            }
        )

        guard case .conflictingParameterIndex(_, let existing, let incoming)? =
                encoding.parameterLayoutError else {
            return XCTFail(
                "Expected codec conflict, got \(String(describing: encoding.parameterLayoutError))"
            )
        }
        XCTAssertEqual(existing.codecIdentity, firstCodec.identity)
        XCTAssertEqual(incoming.codecIdentity, secondCodec.identity)
    }

    func testExpressionMetadataInfersRequiredAndNullableCaptureStorage() throws {
        let codec = captureTokenCodec(id: "tests.capture.expression")
        let configuration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(codec)
        )
        let requiredIdentity = try XLQuerySlotIdentity(
            path: ["expression", "required"]
        )
        let nullableIdentity = try XLQuerySlotIdentity(
            path: ["expression", "nullable"]
        )

        let required = try configuration.queryCapture(
            CaptureToken.self,
            matching: CaptureTypedExpression<String>(),
            identifiedBy: requiredIdentity,
            using: XLSQLiteDialect()
        )
        let nullable = try configuration.queryCapture(
            CaptureToken.self,
            matching: CaptureTypedExpression<String?>(),
            identifiedBy: nullableIdentity,
            using: XLSQLiteDialect()
        )

        XCTAssertEqual(required.declaration.nullability, .required)
        XCTAssertEqual(nullable.declaration.nullability, .nullable)
        XCTAssertEqual(required.storageIdentifier, codec.identity.storageIdentifier)
        XCTAssertEqual(nullable.storageIdentifier, codec.identity.storageIdentifier)
        XCTAssertEqual(required.declaration.codecIdentity, codec.identity)
        XCTAssertEqual(nullable.declaration.codecIdentity, codec.identity)
    }

    func testCodecSelectionFailuresRetainCaptureSpecificMetadata() throws {
        let identity = try XLQuerySlotIdentity(
            path: ["diagnostic", "captured-value"]
        )
        let context = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(["custom", "context"])
        )
        let first = captureTokenCodec(id: "tests.capture.z-second")
        let second = captureTokenCodec(id: "tests.capture.a-first")
        let expectedText = XLValueStorageIdentifier(rawValue: "text")

        func assertFailure(
            _ error: Error,
            expectedStorage: XLValueStorageIdentifier,
            selection: XLQueryCodecSelection,
            candidates: [XLValueCodecKey]
        ) {
            guard case .codecSelectionFailed(
                let actualIdentity,
                let valueType,
                let expectedDialect,
                let actualStorage,
                let actualSelection,
                let actualCandidates,
                let actualContext,
                let detail
            ) = error as? XLQueryCaptureError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(actualIdentity, identity)
            XCTAssertEqual(valueType, String(reflecting: CaptureToken.self))
            XCTAssertEqual(expectedDialect, XLSQLiteDialect.identity)
            XCTAssertEqual(actualStorage, expectedStorage)
            XCTAssertEqual(actualSelection, selection)
            XCTAssertEqual(actualCandidates, candidates)
            XCTAssertEqual(actualContext, context)
            XCTAssertFalse(detail.isEmpty)
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains(identity.description))
            XCTAssertTrue(description.contains(expectedDialect.description))
            XCTAssertTrue(description.contains(expectedStorage.description))
            XCTAssertTrue(description.contains(context.description))
        }

        let empty = try XLValueCodingConfiguration()
        XCTAssertThrowsError(try empty.queryCapture(
            CaptureToken.self,
            expressedAs: String.self,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            context: context
        )) { error in
            assertFailure(
                error,
                expectedStorage: expectedText,
                selection: .inferred,
                candidates: []
            )
        }

        let ambiguous = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry()
                .registering(first)
                .registering(second)
        )
        XCTAssertThrowsError(try ambiguous.queryCapture(
            CaptureToken.self,
            expressedAs: String.self,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            context: context
        )) { error in
            assertFailure(
                error,
                expectedStorage: expectedText,
                selection: .inferred,
                candidates: [second.identity.key, first.identity.key]
            )
        }

        let explicit = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(first)
        )
        XCTAssertThrowsError(try explicit.queryCapture(
            CaptureToken.self,
            expressedAs: Int.self,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            context: context,
            selection: .explicit(first.identity.key)
        )) { error in
            assertFailure(
                error,
                expectedStorage: XLValueStorageIdentifier(rawValue: "integer"),
                selection: .explicit(first.identity.key),
                candidates: [first.identity.key]
            )
        }
    }

    func testSameIdentityWithConflictingStorageFailsRendering() throws {
        let identity = try XLQuerySlotIdentity(path: ["conflict"])
        let integer = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: identity
        )
        let text = try XLQueryCapture<String, String, XLSQLiteDialect>.intrinsic(
            identifiedBy: identity
        )
        let encoding = encoder.makeSQL(
            CaptureProbe { builder in
                integer.makeSQL(context: &builder)
                text.makeSQL(context: &builder)
            }
        )

        guard case .conflictingParameterIndex(_, let existing, let incoming)? =
                encoding.parameterLayoutError else {
            return XCTFail(
                "Expected a deterministic storage/type conflict, got \(String(describing: encoding.parameterLayoutError))"
            )
        }
        XCTAssertEqual(existing.key, integer.declaration.key)
        XCTAssertEqual(incoming.key, text.declaration.key)
        XCTAssertThrowsError(try encoder.makeValidatedSQL(
            CaptureProbe { builder in
                integer.makeSQL(context: &builder)
                text.makeSQL(context: &builder)
            }
        ))
    }

    func testOptionalLiteralDeclaresNullableSlot() throws {
        let capture = try XLQueryCapture<String, String?, XLSQLiteDialect>
            .intrinsic(
                identifiedBy: XLQuerySlotIdentity(path: ["nullable"])
            )
        let encoding = try encoder.makeValidatedSQL(
            sql { _ in Select(capture) }
        )

        XCTAssertEqual(
            try capture.staticQueryParameter(in: encoding).slot.nullability,
            .nullable
        )
    }

    func testIntrinsicCaptureRejectsUnsupportedAndOptionalInputTypes() throws {
        let identity = try XLQuerySlotIdentity(path: ["unsupported"])

        XCTAssertThrowsError(
            try XLQueryCapture<UnknownLiteral, UnknownLiteral, XLSQLiteDialect>
                .intrinsic(identifiedBy: identity)
        ) { error in
            guard case .unsupportedLiteralStorage = error as? XLQueryCaptureError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try XLQueryCapture<String?, String?, XLSQLiteDialect>
                .intrinsic(identifiedBy: identity)
        ) { error in
            XCTAssertEqual(
                error as? XLQueryCaptureError,
                .optionalInputType(
                    identity: identity,
                    valueType: String(reflecting: String?.self)
                )
            )
        }
    }

    func testStaticMetadataRejectsForeignDialectEncoding() throws {
        let capture = try XLQueryCapture<Int, Int, XLSQLiteDialect>.intrinsic(
            identifiedBy: XLQuerySlotIdentity(path: ["dialect"])
        )
        let sqliteEncoding = try encoder.makeValidatedSQL(
            sql { _ in Select(capture) }
        )
        let foreign = XLEncoding(
            sql: sqliteEncoding.sql,
            entities: sqliteEncoding.entities,
            dialectRequirement: XLDialectRequirement(
                identity: XLDialectIdentifier(rawValue: "foreign")
            ),
            parameterLayout: sqliteEncoding.parameterLayout
        )

        XCTAssertThrowsError(try capture.staticQueryParameter(in: foreign)) {
            error in
            XCTAssertEqual(
                error as? XLQueryCaptureError,
                .dialectMismatch(
                    identity: capture.identity,
                    expected: XLSQLiteDialect.identity,
                    actual: XLDialectIdentifier(rawValue: "foreign")
                )
            )
        }
    }
}


private struct CaptureProbe: XLEncodable {
    let render: (inout XLBuilder) -> Void

    func makeSQL(context: inout XLBuilder) {
        render(&context)
    }
}


private struct CaptureTypedExpression<Literal>: XLExpression
where Literal: XLLiteral {
    typealias T = Literal

    func makeSQL(context: inout XLBuilder) {
        context.null()
    }
}


private struct UnknownLiteral: XLExpression, XLLiteral {
    typealias T = Self

    static func sqlDefault() -> Self {
        Self()
    }

    init() {}

    init(reader: XLColumnReader, at index: Int) throws {
        self.init()
    }

    func bind(context: inout XLBindingContext) {
        context.bindNull()
    }

    func makeSQL(context: inout XLBuilder) {
        context.null()
    }
}


private struct CaptureToken {
    let value: String
}


private func captureTokenCodec(
    id: String
) -> XLValueCodec<CaptureToken, XLSQLiteDialect> {
    XLValueCodec(
        key: XLValueCodecKey(id: id, version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "tests.CaptureToken"),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
        encode: { value, _, _ in .text(value.value) },
        decode: { value, _, _ in
            guard case .text(let value) = value else {
                throw CaptureTokenError.invalidValue
            }
            return CaptureToken(value: value)
        }
    )
}


private enum CaptureTokenError: Error {
    case invalidValue
}
