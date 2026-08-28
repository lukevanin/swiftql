//
//  SQLJSONPathTests.swift
//
//
//  Milestone v1.6, issue #588: the typed JSON path builder. The rendering
//  cases pin the path text for each segment kind. The execution cases run the
//  built path through real SQLite, so a path that renders but does not select
//  the intended element fails here.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLJSONPathRenderingTests: XCTestCase {

    private var encoder: XLiteEncoder!

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .noEscape)
        )
    }

    override func tearDown() {
        encoder = nil
    }

    // MARK: - Segments

    func testRootRendersAsDollar() {
        XCTAssertEqual(XLJSONPath.root.path, "$")
    }

    func testKeySegmentsRenderQuoted() {
        XCTAssertEqual(XLJSONPath.root.key("address").path, "$.\"address\"")
        XCTAssertEqual(
            XLJSONPath.root.key("address").key("city").path,
            "$.\"address\".\"city\""
        )
    }

    func testIndexSegmentsRenderInBrackets() {
        XCTAssertEqual(XLJSONPath.root.key("items").index(0).path, "$.\"items\"[0]")
        XCTAssertEqual(XLJSONPath.root.index(12).path, "$[12]")
    }

    func testCountingBackFromTheEndRendersHashOffset() {
        XCTAssertEqual(XLJSONPath.root.key("items").last.path, "$.\"items\"[#-1]")
        XCTAssertEqual(
            XLJSONPath.root.key("items").index(fromEnd: 3).path,
            "$.\"items\"[#-3]"
        )
    }

    func testSegmentsCompose() {
        XCTAssertEqual(
            XLJSONPath.root.key("a").key("b").index(0).key("c").path,
            "$.\"a\".\"b\"[0].\"c\""
        )
    }

    // MARK: - Key escaping

    func testKeysHoldingPathSyntaxAreEscaped() {
        XCTAssertEqual(XLJSONPath.root.key("a.b").path, "$.\"a.b\"")
        XCTAssertEqual(XLJSONPath.root.key("a[0]").path, "$.\"a[0]\"")
        XCTAssertEqual(XLJSONPath.root.key("a\"b").path, "$.\"a\\\"b\"")
        XCTAssertEqual(XLJSONPath.root.key("a\\b").path, "$.\"a\\\\b\"")
    }

    func testControlCharactersInKeysUseJSONEscapes() {
        XCTAssertEqual(XLJSONPath.root.key("a\nb").path, "$.\"a\\nb\"")
        XCTAssertEqual(XLJSONPath.root.key("a\tb").path, "$.\"a\\tb\"")
        XCTAssertEqual(XLJSONPath.root.key("a\u{01}b").path, "$.\"a\\u0001b\"")
    }

    func testEmptyAndNonASCIIKeysSurvive() {
        XCTAssertEqual(XLJSONPath.root.key("").path, "$.\"\"")
        XCTAssertEqual(XLJSONPath.root.key("é").path, "$.\"é\"")
    }

    // MARK: - Value semantics

    func testPathsAreEquatableAndHashable() {
        let first = XLJSONPath.root.key("items").index(0)
        let second = XLJSONPath.root.key("items").index(0)
        let third = XLJSONPath.root.key("items").index(1)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(Set([first, second, third]).count, 2)
    }

    func testDescriptionIsThePathText() {
        XCTAssertEqual(String(describing: XLJSONPath.root.key("a")), "$.\"a\"")
    }

    // MARK: - Rendering as a SQL operand

    func testPathRendersAsATextOperand() {
        let json = XLNamedBindingReference<String>(name: "json")
        XCTAssertEqual(
            encoder.makeSQL(
                json.jsonArrayLength(path: XLJSONPath.root.key("items"))
            ).sql,
            "json_array_length(:json, '$.\"items\"')"
        )
    }

    func testAQuoteInAKeyIsEscapedForBothJSONAndSQL() {
        // The key holds one double quote and one single quote. The double
        // quote is escaped for the JSON path label, the single quote for the
        // SQL text literal. Neither escape is allowed to end the operand.
        let json = XLNamedBindingReference<String>(name: "json")
        XCTAssertEqual(
            encoder.makeSQL(
                json.jsonArrayLength(path: XLJSONPath.root.key("a\"b'c"))
            ).sql,
            "json_array_length(:json, '$.\"a\\\"b''c\"')"
        )
    }

    func testTheStringPathOverloadStillCompiles() {
        // v1 source compatibility: the original spelling keeps working.
        let json = XLNamedBindingReference<String>(name: "json")
        XCTAssertEqual(
            encoder.makeSQL(json.jsonArrayLength(path: "$.items")).sql,
            "json_array_length(:json, '$.items')"
        )
    }
}


final class XLJSONPathExecutionTests: XCTestCase {

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

    func testABuiltPathSelectsWhatAHandWrittenPathSelects() throws {
        let json = #"{"items":[1,2,3],"other":[1]}"#
        let built = try evaluate(
            document().jsonArrayLength(path: XLJSONPath.root.key("items")),
            document: json
        )
        let handWritten = try evaluate(
            document().jsonArrayLength(path: "$.items"),
            document: json
        )
        XCTAssertEqual(built, 3)
        XCTAssertEqual(built, handWritten)
    }

    func testARootPathSelectsTheWholeDocument() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root),
                document: "[1,2,3,4]"
            ),
            4
        )
    }

    func testAKeyHoldingADotNamesThatKey() throws {
        // `$.a.b` reads as "b inside a". The built path names the single key
        // `a.b`, which is the whole point of quoting every key.
        let json = #"{"a.b":[1,2,3],"a":{"b":[1]}}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key("a.b")),
                document: json
            ),
            3
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: "$.a.b"),
                document: json
            ),
            1
        )
    }

    func testKeysHoldingBracketsQuotesAndBackslashesSelectTheirValues() throws {
        let json = #"{"a[0]":[1],"a\"b":[1,2],"a\\b":[1,2,3]}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key("a[0]")),
                document: json
            ),
            1
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key(#"a"b"#)),
                document: json
            ),
            2
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key(#"a\b"#)),
                document: json
            ),
            3
        )
    }

    func testControlCharacterKeysSelectTheirValues() throws {
        let json = #"{"a\nb":[1,2]}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key("a\nb")),
                document: json
            ),
            2
        )
    }

    func testIndexAndLastSelectArrayElements() throws {
        let json = #"{"rows":[[1],[1,2],[1,2,3]]}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(
                    path: XLJSONPath.root.key("rows").index(1)
                ),
                document: json
            ),
            2
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(
                    path: XLJSONPath.root.key("rows").last
                ),
                document: json
            ),
            3
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(
                    path: XLJSONPath.root.key("rows").index(fromEnd: 3)
                ),
                document: json
            ),
            1
        )
    }

    func testAPathThatMatchesNothingIsNull() throws {
        // `evaluate` returns `Value?`, and `Value` is itself `Int?` here, so
        // the row is present and its single column is SQL NULL. Unwrapping
        // the outer optional separates that from "no row at all", and keeps
        // the assertion off a double optional, which XCTAssertNil and
        // XCTAssertNotNil both warn about.
        guard let result = try evaluate(
            document().jsonArrayLength(path: XLJSONPath.root.key("missing")),
            document: #"{"items":[1]}"#
        ) else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(result, "the selected column should be SQL NULL")
    }
}
