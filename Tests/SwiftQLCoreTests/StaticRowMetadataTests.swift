import XCTest
@testable import SwiftQLCore


final class StaticRowMetadataTests: XCTestCase {

    func testPreservesDeclarationOrderAndDelegatesSlotValidation() throws {
        let first = try field(alias: "name", index: 0, path: ["row", "name"])
        let second = try field(alias: "AGE", index: 1, path: ["row", "age"])

        let metadata = try XLStaticRowMetadata(fields: [first, second])

        XCTAssertEqual(metadata.fields, [first, second])
        XCTAssertEqual(metadata.results.slots, [first.result, second.result])
    }

    func testRejectsPositionMismatchBeforeCanonicalResultSorting() throws {
        let misplaced = try field(
            alias: "value",
            index: 1,
            path: ["row", "value"]
        )

        XCTAssertThrowsError(try XLStaticRowMetadata(fields: [misplaced])) {
            XCTAssertEqual(
                $0 as? XLStaticRowMetadataError,
                .fieldPositionMismatch(
                    field: misplaced,
                    expected: XLLogicalResultIndex(0)
                )
            )
        }
    }

    func testRejectsEmptyAndCanonicalCaseInsensitiveDuplicateAliases() throws {
        let empty = try field(alias: "", index: 0, path: ["row", "empty"])
        XCTAssertThrowsError(try XLStaticRowMetadata(fields: [empty])) {
            XCTAssertEqual(
                $0 as? XLStaticRowMetadataError,
                .emptyFieldAlias(field: empty)
            )
        }

        let composed = try field(
            alias: "Caf\u{00E9}",
            index: 0,
            path: ["row", "first"]
        )
        let decomposed = try field(
            alias: "CAFE\u{0301}",
            index: 1,
            path: ["row", "second"]
        )
        XCTAssertThrowsError(
            try XLStaticRowMetadata(fields: [composed, decomposed])
        ) {
            XCTAssertEqual(
                $0 as? XLStaticRowMetadataError,
                .duplicateFieldAlias(
                    alias: decomposed.alias,
                    existing: composed,
                    incoming: decomposed
                )
            )
            XCTAssertTrue($0.localizedDescription.contains("codec"))
            XCTAssertTrue($0.localizedDescription.contains("row/second"))
        }
    }

    private func field(
        alias: String,
        index: Int,
        path: [String]
    ) throws -> XLStaticRowField {
        let identity = try XLQuerySlotIdentity(path: path)
        return XLStaticRowField(
            alias: alias,
            result: XLStaticQueryResultSlot(
                index: XLLogicalResultIndex(index),
                identity: identity,
                valueTypeIdentifier: XLValueTypeIdentifier(
                    rawValue: "tests.value"
                ),
                valueTypeName: "Tests.Value",
                nullability: .required,
                codecIdentity: nil,
                storageIdentifier: XLValueStorageIdentifier(
                    rawValue: "text"
                ),
                codingContext: XLValueCodingContext(
                    site: .property,
                    path: XLValueCodingPath(path)
                )
            )
        )
    }
}
