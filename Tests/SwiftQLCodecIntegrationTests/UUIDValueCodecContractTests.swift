import Foundation
import XCTest
@testable import SwiftQL


/// Contract-level tests for the built-in SQLite UUID codec presets
/// (``XLUUIDValueCodec/text`` and ``XLUUIDValueCodec/blob``), mirroring
/// `Tests/SwiftQLCoreTests/ValueCodecContractTests.swift`'s style: pure
/// encode/decode/registry behavior, no real SQLite connection. Real-SQLite
/// round-trip coverage (insert, update, select, indexing) lives in
/// `UUIDValueCodecGRDBTests.swift` alongside this file.
final class UUIDValueCodecContractTests: XCTestCase {

    private let dialect = XLSQLiteDialect()

    private let sampleUUID = UUID(
        uuidString: "E02F7C60-8C7F-4C68-8B62-6F0F1A2B3C4D"
    )!

    private func context(_ path: String) -> XLValueCodingContext {
        XLValueCodingContext(site: .property, path: XLValueCodingPath(path))
    }

    // MARK: - Text preset

    func testTextCodecEncodesCanonicalLowercaseHyphenatedString() throws {
        let encoded = try XLUUIDValueCodec.text.encode(
            sampleUUID,
            using: dialect,
            context: context("id")
        )
        XCTAssertEqual(encoded, .text("e02f7c60-8c7f-4c68-8b62-6f0f1a2b3c4d"))
    }

    func testTextCodecDecodesCaseInsensitiveInputToTheSameUUID() throws {
        let lowercase = try XLUUIDValueCodec.text.decode(
            .text("e02f7c60-8c7f-4c68-8b62-6f0f1a2b3c4d"),
            using: dialect,
            context: context("id")
        )
        let uppercase = try XLUUIDValueCodec.text.decode(
            .text("E02F7C60-8C7F-4C68-8B62-6F0F1A2B3C4D"),
            using: dialect,
            context: context("id")
        )
        XCTAssertEqual(lowercase, sampleUUID)
        XCTAssertEqual(uppercase, sampleUUID)
    }

    func testTextCodecRoundTripsThroughEncodeAndDecode() throws {
        for uuid in [
            sampleUUID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            UUID(),
        ] {
            let encoded = try XLUUIDValueCodec.text.encode(
                uuid,
                using: dialect,
                context: context("id")
            )
            let decoded = try XLUUIDValueCodec.text.decode(
                encoded,
                using: dialect,
                context: context("id")
            )
            XCTAssertEqual(decoded, uuid)
        }
    }

    func testTextCodecRejectsMalformedTextWithStructuredCodecAndPropertyContext() throws {
        let malformedContext = context("employee.badge")
        XCTAssertThrowsError(
            try XLUUIDValueCodec.text.decode(
                .text("not-a-uuid"),
                using: dialect,
                context: malformedContext
            )
        ) { error in
            guard case .decodingFailed(let codec, let context, let message)? =
                error as? XLValueCodecError else {
                return XCTFail("Expected a decodingFailed error, received \(error).")
            }
            XCTAssertEqual(codec, XLUUIDValueCodec.text.identity.key)
            XCTAssertEqual(context, malformedContext)
            XCTAssertTrue(
                message.contains("not-a-uuid"),
                "Expected the invalid text to appear in the wrapped message: \(message)"
            )
        }
    }

    // MARK: - BLOB preset

    func testBlobCodecEncodesExactSixteenByteRFC4122Layout() throws {
        let encoded = try XLUUIDValueCodec.blob.encode(
            sampleUUID,
            using: dialect,
            context: context("id")
        )
        var expectedBytes = sampleUUID.uuid
        let expectedData = withUnsafeBytes(of: &expectedBytes) { Data($0) }
        XCTAssertEqual(encoded, .blob(expectedData))
        XCTAssertEqual(expectedData.count, 16)
        XCTAssertEqual(
            [UInt8](expectedData),
            [0xE0, 0x2F, 0x7C, 0x60, 0x8C, 0x7F, 0x4C, 0x68,
             0x8B, 0x62, 0x6F, 0x0F, 0x1A, 0x2B, 0x3C, 0x4D]
        )
    }

    func testBlobCodecRoundTripsThroughEncodeAndDecode() throws {
        for uuid in [
            sampleUUID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            UUID(),
        ] {
            let encoded = try XLUUIDValueCodec.blob.encode(
                uuid,
                using: dialect,
                context: context("id")
            )
            let decoded = try XLUUIDValueCodec.blob.decode(
                encoded,
                using: dialect,
                context: context("id")
            )
            XCTAssertEqual(decoded, uuid)
        }
    }

    func testBlobCodecRejectsWrongLengthWithStructuredCodecAndPropertyContext() throws {
        let malformedContext = context("employee.badge")
        XCTAssertThrowsError(
            try XLUUIDValueCodec.blob.decode(
                .blob(Data([0x01, 0x02, 0x03])),
                using: dialect,
                context: malformedContext
            )
        ) { error in
            guard case .decodingFailed(let codec, let context, let message)? =
                error as? XLValueCodecError else {
                return XCTFail("Expected a decodingFailed error, received \(error).")
            }
            XCTAssertEqual(codec, XLUUIDValueCodec.blob.identity.key)
            XCTAssertEqual(context, malformedContext)
            XCTAssertTrue(
                message.contains("3"),
                "Expected the received byte count in the wrapped message: \(message)"
            )
        }
    }

    // MARK: - Text and BLOB are not interchangeable

    func testTextAndBlobPresetsShareValueTypeButDeclareDifferentStorage() {
        XCTAssertEqual(
            XLUUIDValueCodec.text.identity.valueTypeIdentifier,
            XLUUIDValueCodec.blob.identity.valueTypeIdentifier
        )
        XCTAssertEqual(
            XLUUIDValueCodec.text.identity.storageIdentifier,
            XLValueStorageIdentifier(rawValue: "text")
        )
        XCTAssertEqual(
            XLUUIDValueCodec.blob.identity.storageIdentifier,
            XLValueStorageIdentifier(rawValue: "blob")
        )
        XCTAssertNotEqual(
            XLUUIDValueCodec.text.identity.key,
            XLUUIDValueCodec.blob.identity.key
        )
    }

    func testTextCodecRejectsABlobValueBeforeItsOwnDecodeClosureRuns() throws {
        let mismatchContext = context("id")
        let blobValue = try XLUUIDValueCodec.blob.encode(
            sampleUUID,
            using: dialect,
            context: mismatchContext
        )
        XCTAssertThrowsError(
            try XLUUIDValueCodec.text.decode(
                blobValue,
                using: dialect,
                context: mismatchContext
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .storageMismatch(
                    codec: XLUUIDValueCodec.text.identity.key,
                    expected: XLValueStorageIdentifier(rawValue: "text"),
                    actual: XLValueStorageIdentifier(rawValue: "blob"),
                    context: mismatchContext
                )
            )
        }
    }

    func testBlobCodecRejectsATextValueBeforeItsOwnDecodeClosureRuns() throws {
        let mismatchContext = context("id")
        let textValue = try XLUUIDValueCodec.text.encode(
            sampleUUID,
            using: dialect,
            context: mismatchContext
        )
        XCTAssertThrowsError(
            try XLUUIDValueCodec.blob.decode(
                textValue,
                using: dialect,
                context: mismatchContext
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .storageMismatch(
                    codec: XLUUIDValueCodec.blob.identity.key,
                    expected: XLValueStorageIdentifier(rawValue: "blob"),
                    actual: XLValueStorageIdentifier(rawValue: "text"),
                    context: mismatchContext
                )
            )
        }
    }

    // MARK: - Database-default ambiguity requires explicit per-property selection

    func testRegisteringBothPresetsAsDefaultsIsRejectedAsAmbiguous() throws {
        let registry = try XLValueCodecRegistry()
            .registering(XLUUIDValueCodec.text)
            .registering(XLUUIDValueCodec.blob)

        XCTAssertThrowsError(
            try XLValueCodingConfiguration(
                registry: registry,
                defaultCodecKeys: [
                    XLUUIDValueCodec.text.identity.key,
                    XLUUIDValueCodec.blob.identity.key,
                ]
            )
        ) { error in
            guard case .duplicateDefault? = error as? XLValueCodecError else {
                return XCTFail("Expected a duplicateDefault error, received \(error).")
            }
        }
    }

    func testOneSchemaSelectsBothPresetsExplicitlyForDifferentProperties() throws {
        // No default is installed -- both presets are registered, and each
        // property selects one explicitly. This is the "one schema, two UUID
        // properties, two representations, no wrapper structs" shape.
        let registry = try XLValueCodecRegistry()
            .registering(XLUUIDValueCodec.text)
            .registering(XLUUIDValueCodec.blob)
        let configuration = try XLValueCodingConfiguration(registry: registry)

        let publicIDContext = context("employee.publicID")
        let legacyIDContext = context("employee.legacyBadgeID")
        let publicID = UUID()
        let legacyBadgeID = UUID()

        let publicIDCodec = try configuration.resolvedCodec(
            for: UUID.self,
            using: dialect,
            context: publicIDContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: XLUUIDValueCodec.text.identity.key
            )
        )
        let legacyBadgeIDCodec = try configuration.resolvedCodec(
            for: UUID.self,
            using: dialect,
            context: legacyIDContext,
            selection: XLValueCodecSelection(
                explicitCodecKey: XLUUIDValueCodec.blob.identity.key
            )
        )

        let encodedPublicID = try publicIDCodec.encode(publicID)
        let encodedLegacyBadgeID = try legacyBadgeIDCodec.encode(legacyBadgeID)

        XCTAssertEqual(encodedPublicID.storageType, .text)
        XCTAssertEqual(encodedLegacyBadgeID.storageType, .blob)
        XCTAssertEqual(try publicIDCodec.decode(encodedPublicID), publicID)
        XCTAssertEqual(try legacyBadgeIDCodec.decode(encodedLegacyBadgeID), legacyBadgeID)
    }

    // MARK: - No retroactive conformance

    func testUUIDHasNoVisibleV1LiteralConformance() {
        XCTAssertFalse(_uuidValueCodecTestsHasVisibleV1LiteralConformance(UUID.self))
    }

    // MARK: - Optionality lives outside the codec

    func testOptionalEncodingAndDecodingMapNilDirectlyToSQLNullForBothPresets() throws {
        let registry = try XLValueCodecRegistry()
            .registering(XLUUIDValueCodec.text)
            .registering(XLUUIDValueCodec.blob)
        let configuration = try XLValueCodingConfiguration(registry: registry)
        let textSelection = XLValueCodecSelection(
            explicitCodecKey: XLUUIDValueCodec.text.identity.key
        )
        let blobSelection = XLValueCodecSelection(
            explicitCodecKey: XLUUIDValueCodec.blob.identity.key
        )

        let nullFromText = try configuration.encodeOptional(
            Optional<UUID>.none,
            using: dialect,
            context: context("id"),
            selection: textSelection
        )
        let nullFromBlob = try configuration.encodeOptional(
            Optional<UUID>.none,
            using: dialect,
            context: context("id"),
            selection: blobSelection
        )
        XCTAssertEqual(nullFromText, .null)
        XCTAssertEqual(nullFromBlob, .null)

        let decodedTextNil: UUID? = try configuration.decodeOptional(
            UUID.self,
            from: .null,
            using: dialect,
            context: context("id"),
            selection: textSelection
        )
        let decodedBlobNil: UUID? = try configuration.decodeOptional(
            UUID.self,
            from: .null,
            using: dialect,
            context: context("id"),
            selection: blobSelection
        )
        XCTAssertNil(decodedTextNil)
        XCTAssertNil(decodedBlobNil)

        let present = try configuration.encodeOptional(
            Optional(sampleUUID),
            using: dialect,
            context: context("id"),
            selection: textSelection
        )
        XCTAssertEqual(present, .text("e02f7c60-8c7f-4c68-8b62-6f0f1a2b3c4d"))
    }

    // MARK: - Concurrency: an immutable snapshot has no shared mutable state

    func testResolvedUUIDCodecSnapshotIsSafeForConcurrentEncodeAndDecode() async throws {
        let registry = try XLValueCodecRegistry().registering(XLUUIDValueCodec.text)
        let configuration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [XLUUIDValueCodec.text.identity.key]
        )
        let resolved = try configuration.resolvedCodec(
            for: UUID.self,
            using: dialect,
            context: context("id")
        )
        let uuids = (0 ..< 64).map { _ in UUID() }

        // Every task shares the same `resolved` value. If encoding or
        // decoding depended on any hidden shared mutable state, concurrent
        // use from many tasks would risk cross-talk between the UUIDs.
        let roundTripped = try await withThrowingTaskGroup(
            of: (UUID, UUID).self,
            returning: [(UUID, UUID)].self
        ) { group in
            for uuid in uuids {
                group.addTask {
                    let encoded = try resolved.encode(uuid)
                    let decoded = try resolved.decode(encoded)
                    return (uuid, decoded)
                }
            }
            var results: [(UUID, UUID)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(roundTripped.count, uuids.count)
        for (original, decoded) in roundTripped {
            XCTAssertEqual(original, decoded)
        }
    }
}


/// Uses compile-time overload selection so the assertion is not affected by
/// retroactive conformances loaded from other test modules into one XCTest
/// bundle. Mirrors the identically named idiom in
/// `ContextualValueCodecGRDBTests.swift`; kept file-private per that file's
/// convention of each contract test file owning its own fixture helpers.
private func _uuidValueCodecTestsHasVisibleV1LiteralConformance<Value>(
    _: Value.Type
) -> Bool {
    false
}


private func _uuidValueCodecTestsHasVisibleV1LiteralConformance<Value>(
    _: Value.Type
) -> Bool where Value: XLLiteral {
    true
}
