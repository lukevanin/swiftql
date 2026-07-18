import XCTest
@testable import SwiftQL


@SQLResult
private struct StaticRowDiagnosticRecord: Equatable {
    let leading: Int
    let value: String
}


final class StaticRowDiagnosticTests: XCTestCase {

    func testDescriptorMismatchIdentifiesFirstSlotAndCompleteContracts() throws {
        let identity = try XLQuerySlotIdentity(
            path: ["diagnostics", "shared-value"]
        )
        let layout = try makeLayout(identity: identity)
        let expectedType = XLValueTypeIdentifier(
            rawValue: "tests.diagnostics.expected"
        )
        let expectedStorage = XLValueStorageIdentifier(rawValue: "integer")
        let expectedCodec = XLValueCodecIdentity(
            key: XLValueCodecKey(
                id: "tests.diagnostics.expected-codec",
                version: 7
            ),
            valueTypeIdentifier: expectedType,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: expectedStorage
        )
        let expectedSlot = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(1),
            identity: identity,
            valueTypeIdentifier: expectedType,
            valueTypeName: "Diagnostics.ExpectedValue",
            nullability: .nullable,
            codecIdentity: expectedCodec,
            storageIdentifier: expectedStorage,
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath(["expected", "result"])
            )
        )
        let expectedResults = try XLStaticQueryResultMetadata(
            slots: [layout.metadata.results.slots[0], expectedSlot]
        )
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-row-diagnostics"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "SELECT 0, 1",
                dialectRequirement: XLDialectRequirement(
                    identity: XLSQLiteDialect.identity
                )
            ),
            parameters: [],
            results: expectedResults,
            cardinality: .exactlyOne
        )

        XCTAssertThrowsError(
            try XLTypedStaticQueryDescriptor(
                descriptor: descriptor,
                layout: layout
            )
        ) { error in
            guard case .descriptorResultsMismatch(let expected, let actual) =
                    error as? XLStaticRowLayoutError else {
                return XCTFail(
                    "Expected descriptor result mismatch, received \(error)"
                )
            }
            XCTAssertEqual(expected, expectedResults)
            XCTAssertEqual(actual, layout.metadata.results)

            let actualSlot = layout.metadata.results.slots[1]
            let description = error.localizedDescription
            XCTAssertTrue(
                description.contains("First differing result position 1")
            )
            XCTAssertTrue(description.contains("identity: \(identity)"))
            XCTAssertTrue(
                description.contains(
                    "type: \(expectedSlot.valueTypeName) [\(expectedSlot.valueTypeIdentifier)]"
                )
            )
            XCTAssertTrue(
                description.contains(
                    "type: \(actualSlot.valueTypeName) [\(actualSlot.valueTypeIdentifier)]"
                )
            )
            XCTAssertTrue(description.contains("nullability: nullable"))
            XCTAssertTrue(description.contains("nullability: required"))
            XCTAssertTrue(
                description.contains("codec: \(expectedCodec.key.description)")
            )
            XCTAssertTrue(description.contains("codec: intrinsic/none"))
            XCTAssertTrue(description.contains("storage: integer"))
            XCTAssertTrue(description.contains("storage: text"))
            XCTAssertTrue(
                description.contains("coding context: result:expected.result")
            )
            XCTAssertTrue(
                description.contains(
                    "coding context: property:diagnostics.shared-value"
                )
            )
        }
    }

    func testUnpositionedFieldDiagnosticRetainsIdentity() throws {
        let identity = try XLQuerySlotIdentity(
            path: ["diagnostics", "unpositioned"]
        )
        let field = try makeField(identity: identity)

        XCTAssertThrowsError(try field.erased()) { error in
            XCTAssertEqual(
                error as? XLStaticRowLayoutError,
                .fieldNotPositioned(identity: identity)
            )
            XCTAssertTrue(error.localizedDescription.contains("\(identity)"))
            XCTAssertTrue(
                error.localizedDescription.contains("positioned")
            )
        }
    }

    func testRequiredNullDiagnosticRetainsFieldAndCodecContext() throws {
        let identity = try XLQuerySlotIdentity(
            path: ["diagnostics", "required-null"]
        )
        let layout = try makeLayout(identity: identity)
        let field = layout.metadata.fields[1]

        XCTAssertThrowsError(
            try layout.decode([.integer(0), .null])
        ) { error in
            XCTAssertEqual(
                error as? XLStaticRowLayoutError,
                .nullForRequiredField(field: field)
            )
            XCTAssertTrue(error.localizedDescription.contains("'value'"))
            XCTAssertTrue(error.localizedDescription.contains("\(identity)"))
            XCTAssertTrue(
                error.localizedDescription.contains("codec intrinsic/none")
            )
            XCTAssertTrue(error.localizedDescription.contains("SQL NULL"))
        }
    }

    func testStorageMismatchDiagnosticRetainsExpectedAndActualStorage() throws {
        let identity = try XLQuerySlotIdentity(
            path: ["diagnostics", "storage"]
        )
        let layout = try makeLayout(identity: identity)
        let field = layout.metadata.fields[1]
        let integerStorage = XLValueStorageIdentifier(rawValue: "integer")

        XCTAssertThrowsError(
            try layout.decode([.integer(0), .integer(1)])
        ) { error in
            XCTAssertEqual(
                error as? XLStaticRowLayoutError,
                .storageMismatch(field: field, actual: integerStorage)
            )
            XCTAssertTrue(error.localizedDescription.contains("'value'"))
            XCTAssertTrue(error.localizedDescription.contains("\(identity)"))
            XCTAssertTrue(error.localizedDescription.contains("storage text"))
            XCTAssertTrue(error.localizedDescription.contains("not integer"))
        }
    }

    private func makeLayout(
        identity: XLQuerySlotIdentity
    ) throws -> XLStaticRowLayout<
        StaticRowDiagnosticRecord,
        XLSQLiteDialect
    > {
        try StaticRowDiagnosticRecord.staticRowLayout(
            using: XLSQLiteDialect.self,
            leading: try XLStaticSelectField<
                Int,
                Int,
                XLSQLiteDialect
            >.intrinsic(
                selecting: XLColumnResult<Int>(
                    dependency: XLSelectResultDependency(),
                    as: "leading"
                ),
                identifiedBy: XLQuerySlotIdentity(
                    path: ["diagnostics", "leading"]
                )
            ),
            value: makeField(identity: identity)
        )
    }

    private func makeField(
        identity: XLQuerySlotIdentity
    ) throws -> XLStaticSelectField<String, String, XLSQLiteDialect> {
        try XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: XLColumnResult<String>(
                dependency: XLSelectResultDependency(),
                as: "value"
            ),
            identifiedBy: identity
        )
    }
}
