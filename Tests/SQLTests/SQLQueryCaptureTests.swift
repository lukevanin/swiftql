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
            guard case .ambiguousCodecForStorage(_, _, _, let candidates, _) =
                    error as? XLQueryCodecSelectionError else {
                return XCTFail("Unexpected error: \(error)")
            }
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
