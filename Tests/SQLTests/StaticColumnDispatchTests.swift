//
//  StaticColumnDispatchTests.swift
//  SwiftQL
//
//  Pins which `staticColumn` requirement a generated row reader selects.
//
//  Issue #353: a literal column must reach the constrained requirement, whose
//  witness reads the value directly. The unconstrained requirement has to find
//  the literal conformance at run time and reopen the expression as a
//  parameterised existential, which the profile attributes most of the per-row
//  decode cost to. That cost is invisible to a correctness test -- both
//  requirements return the same value -- so it is guarded here instead.
//

import Foundation
import SwiftQL
import XCTest


@SQLResult
struct StaticColumnDispatchRow: Equatable {
    let name: String
    let count: Int
    let note: String?
}


final class StaticColumnDispatchTests: XCTestCase {

    func testGeneratedReaderSelectsTheLiteralRequirementForEveryLiteralColumn() throws {
        let reader = DispatchRecordingRowReader()
        let generated = StaticColumnDispatchRow.SQLReader(
            name: column("name"),
            count: column("count"),
            note: column("note")
        )

        _ = try generated.readRow(reader: reader)

        XCTAssertEqual(reader.literalReads, ["name", "count", "note"])
        XCTAssertEqual(reader.unconstrainedReads, [])
    }

    func testContextualColumnStillReachesTheUnconstrainedRequirement() throws {
        let reader = DispatchRecordingRowReader()

        XCTAssertThrowsError(
            try reader.staticColumn(
                ContextOnlyExpression(),
                alias: "contextual"
            ) as ContextOnlyValue
        )

        XCTAssertEqual(reader.literalReads, [])
        XCTAssertEqual(reader.unconstrainedReads, ["contextual"])
    }

    private func column<T>(_ alias: XLName) -> XLColumnResult<T> where T: XLLiteral {
        XLColumnResult<T>(dependency: XLSelectResultDependency(), as: alias)
    }
}


/// Records which `staticColumn` requirement each read arrived through.
private final class DispatchRecordingRowReader: XLRowReader {

    private(set) var literalReads: [XLName] = []
    private(set) var unconstrainedReads: [XLName] = []

    func column<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) -> T where T: XLLiteral {
        T.sqlDefault()
    }

    func staticColumn<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T where T: XLLiteral {
        literalReads.append(alias)
        return column(expression, alias: alias)
    }

    func staticColumn<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T {
        unconstrainedReads.append(alias)
        throw XLStaticRowReadError.staticLayoutRequired(
            valueType: String(reflecting: T.self),
            alias: alias.rawValue
        )
    }
}


private struct ContextOnlyValue {}


private struct ContextOnlyExpression: XLExpression {
    typealias T = ContextOnlyValue

    func makeSQL(context: inout XLBuilder) {
        context.null()
    }
}
