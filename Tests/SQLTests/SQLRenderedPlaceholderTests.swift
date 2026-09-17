import XCTest
@testable import SwiftQL


///
/// References one named binding twice, the way a statement that compares a
/// column to the same parameter in two clauses does.
///
private struct RepeatedNamedParameterProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.namedBinding(XLName("alpha"))
        context.namedBinding(XLName("alpha"))
    }
}


private struct MixedParameterProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.namedBinding(XLName("alpha"))
        context.indexedBinding(4)
        context.namedBinding(XLName("beta"))
    }
}


final class SQLRenderedPlaceholderTests: XCTestCase {

    func testARepeatedNamedParameterRecordsTwoOccurrencesAndOneSlot() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter())
            .makeSQL(RepeatedNamedParameterProbe())

        // Rendered twice, so the SQL text carries it twice.
        XCTAssertEqual(encoding.sql, ":alpha :alpha")

        // Bound once, so there is one logical slot.
        XCTAssertEqual(encoding.parameterLayout.slots.count, 1)
        XCTAssertEqual(encoding.parameterLayout.slots[0].key, .named("alpha"))

        // Both appearances are recorded, in render order.
        XCTAssertEqual(encoding.parameterLayout.occurrences.count, 2)
        for occurrence in encoding.parameterLayout.occurrences {
            XCTAssertEqual(occurrence.key, .named("alpha"))
            XCTAssertEqual(occurrence.placeholder, .named("alpha"))
            XCTAssertEqual(occurrence.index, XLLogicalParameterIndex(0))
            XCTAssertEqual(occurrence.physicalIndex, 1)
        }
    }

    func testSQLiteKeepsItsPhysicalAssignmentForAMixedStatement() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter())
            .makeSQL(MixedParameterProbe())

        XCTAssertEqual(encoding.sql, ":alpha ?5 :beta")

        let physicalIndices = encoding.parameterLayout.occurrences.map(\.physicalIndex)

        // SQLite's rule, unchanged: a named parameter takes the next physical
        // index, an explicit `?NNN` takes NNN, and the following name
        // continues after the largest index seen.
        XCTAssertEqual(physicalIndices, [1, 5, 6])
    }

    func testOccurrencesRecordTheOrderTheyWereRendered() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter())
            .makeSQL(MixedParameterProbe())

        XCTAssertEqual(
            encoding.parameterLayout.occurrences.map(\.key),
            [.named("alpha"), .indexed(4), .named("beta")]
        )
    }

    func testTheLayoutReportsThePlaceholderThatWasRendered() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter())
            .makeSQL(MixedParameterProbe())

        XCTAssertEqual(
            encoding.parameterLayout.placeholder(for: .named("alpha")),
            .named("alpha")
        )
        XCTAssertEqual(
            encoding.parameterLayout.placeholder(for: .indexed(4)),
            .indexed(4)
        )
    }
}
