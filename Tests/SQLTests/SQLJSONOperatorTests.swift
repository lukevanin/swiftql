//
//  SQLJSONOperatorTests.swift
//
//
//  Milestone v1.6, issue #589: the `->` and `->>` JSON selection operators.
//  The two operators select the same element and differ in result type, so
//  the execution cases compare them on one input and one path.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLJSONOperatorRenderingTests: XCTestCase {

    private var encoder: XLiteEncoder!

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .noEscape)
        )
    }

    override func tearDown() {
        encoder = nil
    }

    private func document() -> XLNamedBindingReference<String> {
        XLNamedBindingReference<String>(name: "document")
    }

    func testElementSelectionRendersTheArrowOperator() {
        assertSQL(
            document().jsonElement(at: XLJSONPath.root.key("a")),
            "(:document -> '$.\"a\"')"
        )
    }

    func testValueSelectionRendersTheDoubleArrowOperator() {
        assertSQL(
            document().jsonValue(at: XLJSONPath.root.key("a"), as: String.self),
            "(:document ->> '$.\"a\"')"
        )
    }

    func testTheValueResultTypeFollowsTheRequestedType() {
        // The rendered SQL is the same for every requested type. Only the
        // Swift result type changes, which is what `->>` promises.
        let path = XLJSONPath.root.key("a")
        assertSQL(
            document().jsonValue(at: path, as: Int.self),
            "(:document ->> '$.\"a\"')"
        )
        assertSQL(
            document().jsonValue(at: path, as: Double.self),
            "(:document ->> '$.\"a\"')"
        )
        assertExpressionType(
            document().jsonValue(at: path, as: Int.self),
            Int?.self
        )
        assertExpressionType(
            document().jsonValue(at: path, as: String.self),
            String?.self
        )
        assertExpressionType(
            document().jsonElement(at: path),
            String?.self
        )
    }

    func testSelectionsNest() {
        assertSQL(
            document()
                .jsonElement(at: XLJSONPath.root.key("a"))
                .jsonValue(at: XLJSONPath.root.key("b"), as: Int.self),
            "((:document -> '$.\"a\"') ->> '$.\"b\"')"
        )
    }

    func testASelectionIsOneOperandInsideAnotherExpression() {
        // Each selection carries its own parentheses, so it stays one operand
        // when it is nested in a function argument.
        assertSQL(
            document().jsonElement(at: XLJSONPath.root.key("a")).validJSON(),
            "json_valid((:document -> '$.\"a\"'))"
        )
    }

    func testAPathSegmentIsEscapedOnTheRightOfTheOperator() {
        assertSQL(
            document().jsonValue(at: XLJSONPath.root.key("a.b"), as: Int.self),
            "(:document ->> '$.\"a.b\"')"
        )
    }

    private func assertSQL<T>(
        _ expression: any XLExpression<T>,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where T: XLLiteral {
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            expected,
            file: file,
            line: line
        )
    }

    private func assertExpressionType<T>(_: any XLExpression<T>, _: T.Type) {
    }
}


final class XLJSONOperatorExecutionTests: XCTestCase {

    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(
            databasePool: databasePool,
            formatter: formatter,
            logger: nil
        )
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }

    private func document() -> XLNamedBindingReference<String> {
        XLNamedBindingReference<String>(name: "document")
    }

    private func evaluate<Value>(
        _ expression: any XLExpression<Value>,
        document json: String
    ) throws -> Value? where Value: XLLiteral {
        let statement = sql { _ in Select(expression) }
        var request = database.makeRequest(with: statement)
        request.set(document(), json)
        return try request.fetchOne()
    }

    // MARK: - The difference between the two operators

    func testAStringKeepsItsQuotesThroughArrowAndLosesThemThroughDoubleArrow() throws {
        let json = #"{"name":"Alice"}"#
        let path = XLJSONPath.root.key("name")
        XCTAssertEqual(
            try evaluate(document().jsonElement(at: path), document: json),
            #""Alice""#
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(at: path, as: String.self),
                document: json
            ),
            "Alice"
        )
    }

    func testANumberIsJSONTextThroughArrowAndAnIntegerThroughDoubleArrow() throws {
        let json = #"{"age":41}"#
        let path = XLJSONPath.root.key("age")
        XCTAssertEqual(
            try evaluate(document().jsonElement(at: path), document: json),
            "41"
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(at: path, as: Int.self),
                document: json
            ),
            41
        )
    }

    func testARealNumberSurvivesAsADouble() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(
                    at: XLJSONPath.root.key("ratio"),
                    as: Double.self
                ),
                document: #"{"ratio":0.25}"#
            ),
            0.25
        )
    }

    func testAJSONNullIsTextThroughArrowAndSQLNullThroughDoubleArrow() throws {
        let json = #"{"a":null}"#
        let path = XLJSONPath.root.key("a")
        XCTAssertEqual(
            try evaluate(document().jsonElement(at: path), document: json),
            "null"
        )
        // The row is present and its single column is SQL NULL. Unwrapping
        // the outer optional separates that from "no row at all", and keeps
        // the assertion off a double optional.
        guard let value = try evaluate(
            document().jsonValue(at: path, as: String.self),
            document: json
        ) else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(value, "a JSON null should read back as SQL NULL")
    }

    func testAPathThatMatchesNothingIsSQLNullForBothOperators() throws {
        let json = #"{"a":1}"#
        let path = XLJSONPath.root.key("missing")
        guard
            let element = try evaluate(
                document().jsonElement(at: path),
                document: json
            ),
            let value = try evaluate(
                document().jsonValue(at: path, as: Int.self),
                document: json
            )
        else {
            XCTFail("both statements should return one row")
            return
        }
        XCTAssertNil(element)
        XCTAssertNil(value)
    }

    func testAnObjectHasNoSQLValueSoBothOperatorsGiveItsJSONText() throws {
        let json = #"{"a":{"b":1}}"#
        let path = XLJSONPath.root.key("a")
        XCTAssertEqual(
            try evaluate(document().jsonElement(at: path), document: json),
            #"{"b":1}"#
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(at: path, as: String.self),
                document: json
            ),
            #"{"b":1}"#
        )
    }

    // MARK: - Composition

    func testSelectionsChain() throws {
        XCTAssertEqual(
            try evaluate(
                document()
                    .jsonElement(at: XLJSONPath.root.key("a"))
                    .jsonValue(at: XLJSONPath.root.key("b"), as: Int.self),
                document: #"{"a":{"b":7}}"#
            ),
            7
        )
    }

    func testAnIndexedPathSelectsAnArrayElement() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(
                    at: XLJSONPath.root.key("items").index(1),
                    as: Int.self
                ),
                document: #"{"items":[10,20,30]}"#
            ),
            20
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(
                    at: XLJSONPath.root.key("items").last,
                    as: Int.self
                ),
                document: #"{"items":[10,20,30]}"#
            ),
            30
        )
    }

    func testAKeyHoldingADotSelectsThroughTheOperator() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonValue(
                    at: XLJSONPath.root.key("a.b"),
                    as: Int.self
                ),
                document: #"{"a.b":1,"a":{"b":2}}"#
            ),
            1
        )
    }
}
