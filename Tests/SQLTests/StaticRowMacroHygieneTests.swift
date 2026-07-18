import XCTest
@testable import SwiftQL


@SQLResult
private struct StaticRowMacroHygieneRecord: Equatable {
    let reader: String
    let row: Int
}


final class StaticRowMacroHygieneTests: XCTestCase {

    func testReaderAndRowPropertiesCompileAndRoundTrip() throws {
        let reader = try XLStaticSelectField<
            String,
            String,
            XLSQLiteDialect
        >.intrinsic(
            selecting: XLColumnResult<String>(
                dependency: XLSelectResultDependency(),
                as: "reader"
            ),
            identifiedBy: XLQuerySlotIdentity(
                path: ["macro-hygiene", "reader"]
            )
        )
        let row = try XLStaticSelectField<
            Int,
            Int,
            XLSQLiteDialect
        >.intrinsic(
            selecting: XLColumnResult<Int>(
                dependency: XLSelectResultDependency(),
                as: "row"
            ),
            identifiedBy: XLQuerySlotIdentity(
                path: ["macro-hygiene", "row"]
            )
        )
        let layout = try StaticRowMacroHygieneRecord.staticRowLayout(
            using: XLSQLiteDialect.self,
            reader: reader,
            row: row
        )
        let expected = StaticRowMacroHygieneRecord(
            reader: "value",
            row: 7
        )

        XCTAssertEqual(
            layout.metadata.fields.map(\.alias),
            ["reader", "row"]
        )
        XCTAssertEqual(
            try layout.encode(expected),
            [.text("value"), .integer(7)]
        )
        XCTAssertEqual(
            try layout.decode([.text("value"), .integer(7)]),
            expected
        )
    }
}
