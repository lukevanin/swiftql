//
//  SQLJSONFunctionTests.swift
//
//
//  Milestone v1.6, issue #590: the scalar JSON constructor and inspection
//  functions. The execution cases pin what SQLite actually returns, including
//  the NULL-input behaviour that decides which results are optional.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLJSONFunctionRenderingTests: XCTestCase {

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

    // MARK: - Constructors

    func testArrayConstructorRendersItsElementsInOrder() {
        assertSQL(jsonArray(1, "two", 3.5), "json_array(1, 'two', 3.5)")
        assertSQL(jsonArray([1, 2]), "json_array(1, 2)")
        assertSQL(jsonArray(), "json_array()")
    }

    func testObjectConstructorRendersEachMemberAsANamePair() {
        assertSQL(
            jsonObject(("a", 1), ("b", "x")),
            "json_object('a', 1, 'b', 'x')"
        )
        assertSQL(jsonObject(), "json_object()")
    }

    func testObjectConstructorAcceptsAnExpressionAsAName() {
        assertSQL(
            jsonObject((document(), 1)),
            "json_object(:document, 1)"
        )
    }

    // MARK: - Scalar functions

    func testScalarFunctionsRenderTheirSQLiteNames() {
        assertSQL(document().minifiedJSON(), "json(:document)")
        assertSQL(document().prettyJSON(), "json_pretty(:document)")
        assertSQL(document().jsonQuoted(), "json_quote(:document)")
        assertSQL(document().jsonType(), "json_type(:document)")
        assertSQL(
            document().jsonType(at: XLJSONPath.root.key("a")),
            "json_type(:document, '$.a')"
        )
        assertSQL(document().jsonErrorPosition(), "json_error_position(:document)")
        assertSQL(document().validJSONOrNull(), "json_valid(:document)")
    }

    func testValidationFlagsRenderAsTheirCombinedBitmask() {
        assertSQL(
            document().validJSONOrNull(flags: .json),
            "json_valid(:document, 1)"
        )
        assertSQL(
            document().validJSONOrNull(flags: .json5),
            "json_valid(:document, 2)"
        )
        assertSQL(
            document().validJSONOrNull(flags: [.json, .json5]),
            "json_valid(:document, 3)"
        )
        assertSQL(
            document().validJSONOrNull(flags: [.jsonbShallow, .jsonbStrict]),
            "json_valid(:document, 12)"
        )
    }

    func testAnEmptyFlagSetRendersAsSQLitesOwnDefault() {
        // SQLite rejects a zero mask. An empty set means "no choice made",
        // and SQLite's own choice when the argument is absent is 1.
        assertSQL(
            document().validJSONOrNull(flags: []),
            "json_valid(:document, 1)"
        )
    }

    // MARK: - Result types

    func testResultTypesFollowWhatSQLiteCanReturn() {
        assertExpressionType(jsonArray(1), String.self)
        assertExpressionType(jsonObject(("a", 1)), String.self)
        assertExpressionType(document().jsonQuoted(), String.self)
        assertExpressionType(document().minifiedJSON(), String?.self)
        assertExpressionType(document().prettyJSON(), String?.self)
        assertExpressionType(document().jsonType(), String?.self)
        assertExpressionType(document().jsonErrorPosition(), Int?.self)
        assertExpressionType(document().validJSONOrNull(), Bool?.self)
    }

    // Compile-only, and deliberately never called: naming a deprecated method
    // from a live test would put a deprecation warning into the build, and the
    // first-party warning gate treats that as an error. Following
    // `assertLegacyAggregateSignaturesRemainSourceCompatible` in
    // SQLAggregateTests, the check this method carries is that it compiles at
    // all, which is what source compatibility means here.
    @available(*, deprecated, message: "Exercises the source-compatible SwiftQL 1.x JSON surface.")
    private func assertLegacyJSONSignaturesRemainSourceCompatible() {
        let json = XLNamedBindingReference<String>(name: "document")
        let valid: any XLExpression<Bool> = json.validJSON()
        XCTAssertEqual(encoder.makeSQL(valid).sql, "json_valid(:document)")
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


final class XLJSONFunctionExecutionTests: XCTestCase {

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

    /// Evaluates an expression that reads the `document` binding.
    private func evaluate<Value>(
        _ expression: any XLExpression<Value>,
        document json: String
    ) throws -> Value? where Value: XLLiteral {
        let statement = sql { _ in Select(expression) }
        var request = database.makeRequest(with: statement)
        request.set(document(), json)
        return try request.fetchOne()
    }

    /// Evaluates an expression that binds nothing. Setting a parameter the
    /// statement does not declare is rejected, so these need their own path.
    private func evaluate<Value>(
        _ expression: any XLExpression<Value>
    ) throws -> Value? where Value: XLLiteral {
        let statement = sql { _ in Select(expression) }
        return try database.makeRequest(with: statement).fetchOne()
    }

    // MARK: - Constructors

    func testArrayConstructorBuildsAJSONArray() throws {
        XCTAssertEqual(
            try evaluate(jsonArray(1, "two", 3.5)),
            #"[1,"two",3.5]"#
        )
    }

    func testObjectConstructorBuildsAJSONObject() throws {
        XCTAssertEqual(
            try evaluate(jsonObject(("a", 1), ("b", "x"))),
            #"{"a":1,"b":"x"}"#
        )
    }

    func testAConstructedValueTreatsJSONTextAsAStringUnlessItIsMinifiedFirst() throws {
        // This is the trap `minifiedJSON()` exists to avoid: a value that is
        // already JSON is quoted, not nested, unless it is passed through
        // `json(X)` first.
        XCTAssertEqual(
            try evaluate(jsonArray(document()), document: "[1,2]"),
            #"["[1,2]"]"#
        )
        XCTAssertEqual(
            try evaluate(jsonArray(document().minifiedJSON()), document: "[1,2]"),
            "[[1,2]]"
        )
    }

    // MARK: - Scalar functions

    func testMinifiedJSONRemovesWhitespace() throws {
        XCTAssertEqual(
            try evaluate(document().minifiedJSON(), document: #" { "a" : 1 } "#),
            #"{"a":1}"#
        )
    }

    func testPrettyJSONAddsIndentation() throws {
        try SQLiteRuntimeCapability.requireFunction(
            "json_pretty",
            argumentCount: 1,
            since: "SQLite 3.46.0",
            in: databasePool
        )
        XCTAssertEqual(
            try evaluate(document().prettyJSON(), document: #"{"a":1}"#),
            "{\n    \"a\": 1\n}"
        )
    }

    func testQuotingConvertsASQLValueToItsJSONForm() throws {
        XCTAssertEqual(try evaluate("x".jsonQuoted()), #""x""#)
        XCTAssertEqual(try evaluate(5.jsonQuoted()), "5")
    }

    func testTypeReportsTheJSONTypeAtTheRootAndAtAPath() throws {
        let json = #"{"a":[1],"b":"text","c":null}"#
        XCTAssertEqual(try evaluate(document().jsonType(), document: json), "object")
        XCTAssertEqual(
            try evaluate(
                document().jsonType(at: XLJSONPath.root.key("a")),
                document: json
            ),
            "array"
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonType(at: XLJSONPath.root.key("b")),
                document: json
            ),
            "text"
        )
        // A JSON null has a type. It is not the absence of a value.
        XCTAssertEqual(
            try evaluate(
                document().jsonType(at: XLJSONPath.root.key("c")),
                document: json
            ),
            "null"
        )
    }

    func testTypeAtAMissingPathIsSQLNull() throws {
        guard let type = try evaluate(
            document().jsonType(at: XLJSONPath.root.key("missing")),
            document: #"{"a":1}"#
        ) else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(type)
    }

    func testErrorPositionIsZeroForValidInputAndTheFaultPositionOtherwise() throws {
        XCTAssertEqual(
            try evaluate(document().jsonErrorPosition(), document: #"{"a":1}"#),
            0
        )
        XCTAssertEqual(
            try evaluate(document().jsonErrorPosition(), document: #"{"a":"#),
            6
        )
    }

    func testValidityIsReportedForWellFormedAndMalformedInput() throws {
        XCTAssertEqual(
            try evaluate(document().validJSONOrNull(), document: #"{"a":1}"#),
            true
        )
        XCTAssertEqual(
            try evaluate(document().validJSONOrNull(), document: "{a:1}"),
            false
        )
    }

    func testTheJSON5FlagAcceptsInputThatPlainJSONRejects() throws {
        // `{a:1}` is JSON5, not RFC 8259 JSON. The flag is what separates the
        // two answers on one input.
        try SQLiteRuntimeCapability.requireFunction(
            "json_valid",
            argumentCount: 2,
            since: "SQLite 3.45.0",
            in: databasePool
        )
        let json5 = "{a:1}"
        XCTAssertEqual(
            try evaluate(
                document().validJSONOrNull(flags: .json),
                document: json5
            ),
            false
        )
        XCTAssertEqual(
            try evaluate(
                document().validJSONOrNull(flags: .json5),
                document: json5
            ),
            true
        )
    }

    // MARK: - NULL input

    func testAFunctionThatCanReturnNullDoesSoForANullInput() throws {
        // This is why these results are optional and `jsonQuoted()` is not.
        // `json_valid(NULL)` is NULL, not false, which is the reason
        // `validJSON()` is deprecated in favour of `validJSONOrNull()`.
        XCTAssertNil(try evaluateOnNull { $0.minifiedJSON() })
        XCTAssertNil(try evaluateOnNull { $0.jsonType() })
        XCTAssertNil(try evaluateOnNull { $0.validJSONOrNull() })
        XCTAssertNil(try evaluateOnNull { $0.jsonErrorPosition() })
    }

    func testPrettyJSONOfANullIsNull() throws {
        try SQLiteRuntimeCapability.requireFunction(
            "json_pretty",
            argumentCount: 1,
            since: "SQLite 3.46.0",
            in: databasePool
        )
        XCTAssertNil(try evaluateOnNull { $0.prettyJSON() })
    }

    func testQuotingANullGivesJSONNullRatherThanSQLNull() throws {
        let reference = XLNamedBindingReference<String?>(name: "nullDocument")
        let statement = sql { _ in Select(reference.jsonQuoted()) }
        var request = database.makeRequest(with: statement)
        request.set(reference, String?.none)
        XCTAssertEqual(try request.fetchOne(), "null")
    }

    /// Binds SQL NULL and returns the single column, with the outer optional
    /// unwrapped so the assertion reads the column rather than the row.
    private func evaluateOnNull<Value>(
        _ makeExpression: (XLNamedBindingReference<String?>) -> any XLExpression<Value?>
    ) throws -> Value? where Value: XLLiteral, Value?: XLLiteral {
        let reference = XLNamedBindingReference<String?>(name: "nullDocument")
        let statement = sql { _ in Select(makeExpression(reference)) }
        var request = database.makeRequest(with: statement)
        request.set(reference, String?.none)
        guard let column = try request.fetchOne() else {
            XCTFail("the statement should return one row")
            return nil
        }
        return column
    }
}


