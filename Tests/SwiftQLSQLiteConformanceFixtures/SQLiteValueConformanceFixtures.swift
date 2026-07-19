import Foundation
import SwiftQLCore


/// Stable identifiers shared by adapter-neutral and real-SQLite value tests.
///
/// These identifiers are intentionally independent of XCTest method names so
/// future SQLite adapters can run the same semantic cases unchanged.
public enum SQLiteValueConformanceCaseID:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Sendable
{
    case nullStorage = "storage.null"
    case minimumInteger = "storage.integer.minimum"
    case maximumInteger = "storage.integer.maximum"
    case finiteReal = "storage.real.finite"
    case positiveInfinity = "storage.real.positive-infinity"
    case negativeInfinity = "storage.real.negative-infinity"
    case rejectedNaN = "storage.real.nan-rejected"
    case emptyText = "storage.text.empty"
    case unicodeText = "storage.text.unicode"
    case emptyBlob = "storage.blob.empty"
    case embeddedZeroBlob = "storage.blob.embedded-zero"
    case invalidUTF8Blob = "storage.blob.invalid-utf8"
    case numericTextIntegerAffinity = "affinity.integer.numeric-text"
    case integerTextAffinity = "affinity.text.integer"
    case integerRealAffinity = "affinity.real.integer"
    case optionalNullVersusMissing = "optional.null-vs-missing"
    case textRawValueEnum = "enum.text.round-trip"
    case namedTextCodec = "codec.named.text"
    case defaultIntegerCodec = "codec.default.integer"
    case namedBinding = "binding.named"
    case repeatedNamedBinding = "binding.repeated-named"
    case integerOverflow = "failure.integer-overflow"
    case storageMismatch = "failure.storage-mismatch"
    case decodeAfterValidRow = "failure.decode-after-valid-row"
}


public enum SQLiteValueConformanceExpectation: String, Sendable {
    case roundTrip
    case bindingRejected
}


/// One normalized value case that both core-only and adapter integration tests
/// can consume without importing a concrete database adapter.
public struct SQLiteValueConformanceCase: Sendable {
    public let id: SQLiteValueConformanceCaseID
    public let value: XLSQLiteValue
    public let expectedStorage: XLSQLiteStorageClass
    public let expectation: SQLiteValueConformanceExpectation

    public init(
        id: SQLiteValueConformanceCaseID,
        value: XLSQLiteValue,
        expectedStorage: XLSQLiteStorageClass,
        expectation: SQLiteValueConformanceExpectation = .roundTrip
    ) {
        self.id = id
        self.value = value
        self.expectedStorage = expectedStorage
        self.expectation = expectation
    }
}


public enum SQLiteValueConformanceFixtures {

    /// Exact upstream revisions used by the checked-in provenance manifest.
    /// Keeping these pins with the shared fixtures lets every adapter validate
    /// the same evidence without introducing adapter names into core tests.
    public static let pinnedProvenanceCommitsByRepository: [String: String] = [
        "groue/GRDB.swift": "b83108d10f42680d78f23fe4d4d80fc88dab3212",
        "stephencelis/SQLite.swift": "ccaae3d01fd655be40f20665f1f61dc6deecec27",
        "Lighter-swift/Lighter": "3486fc08d580aa3a87cd29ede023ba291a90de8b",
        "marcoarment/Blackbird": "0960ffc7649e9c35cfdb5f6b0b98216a34e8c09a",
        "vapor/fluent-kit": "6f8844284df4f797d2a81721511d053357d97b56",
        "lukevanin/swiftql": "03f504a1e47e0580b2c20eeeecea104cb9d7f2a9",
    ]

    /// Cases that cross both the driver-neutral SQLite dialect boundary and a
    /// real SQLite connection. NaN remains a normalized `REAL` at the pure
    /// dialect layer, while the concrete binding boundary rejects it before
    /// SQLite can silently normalize it to SQL NULL.
    public static let storageCases: [SQLiteValueConformanceCase] = [
        SQLiteValueConformanceCase(
            id: .nullStorage,
            value: .null,
            expectedStorage: .null
        ),
        SQLiteValueConformanceCase(
            id: .minimumInteger,
            value: .integer(.min),
            expectedStorage: .integer
        ),
        SQLiteValueConformanceCase(
            id: .maximumInteger,
            value: .integer(.max),
            expectedStorage: .integer
        ),
        SQLiteValueConformanceCase(
            id: .finiteReal,
            value: .real(42.125),
            expectedStorage: .real
        ),
        SQLiteValueConformanceCase(
            id: .positiveInfinity,
            value: .real(.infinity),
            expectedStorage: .real
        ),
        SQLiteValueConformanceCase(
            id: .negativeInfinity,
            value: .real(-.infinity),
            expectedStorage: .real
        ),
        SQLiteValueConformanceCase(
            id: .rejectedNaN,
            value: .real(.nan),
            expectedStorage: .real,
            expectation: .bindingRejected
        ),
        SQLiteValueConformanceCase(
            id: .emptyText,
            value: .text(""),
            expectedStorage: .text
        ),
        SQLiteValueConformanceCase(
            id: .unicodeText,
            value: .text("SwiftQL: é / e\u{301} / 你好 / 🌍"),
            expectedStorage: .text
        ),
        SQLiteValueConformanceCase(
            id: .emptyBlob,
            value: .blob(Data()),
            expectedStorage: .blob
        ),
        SQLiteValueConformanceCase(
            id: .embeddedZeroBlob,
            value: .blob(Data([0x00, 0x41, 0x00, 0xff])),
            expectedStorage: .blob
        ),
        SQLiteValueConformanceCase(
            id: .invalidUTF8Blob,
            value: .blob(Data([0xff, 0xfe, 0x00])),
            expectedStorage: .blob
        ),
    ]

    public static let storageCaseIDs = Set(storageCases.map(\.id))
}
