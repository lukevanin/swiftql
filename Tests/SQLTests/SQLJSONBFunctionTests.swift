//
//  SQLJSONBFunctionTests.swift
//
//
//  Milestone v1.6, issue #593: the jsonb_ variants. JSONB arrived in SQLite
//  3.45.0 and the oldest runtime in the supported matrix is 3.43.2, so every
//  execution case asks the connection what it defines before it runs. The
//  rendering cases do not, because rendering does not depend on the runtime.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLJSONBFunctionRenderingTests: XCTestCase {

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

    func testConstructorsRenderTheirSQLiteNames() {
        assertSQL(jsonbArray(1, "two"), "jsonb_array(1, 'two')")
        assertSQL(jsonbObject(("a", 1)), "jsonb_object('a', 1)")
        assertSQL(document().minifiedJSONB(), "jsonb(:document)")
    }

    func testExtractionRendersBothForms() {
        assertSQL(
            document().jsonbExtract(at: XLJSONPath.root.key("a"), as: Int.self),
            "jsonb_extract(:document, '$.a')"
        )
        assertSQL(
            document().jsonbExtract(
                at: XLJSONPath.root.key("a"),
                XLJSONPath.root.key("b")
            ),
            "jsonb_extract(:document, '$.a', '$.b')"
        )
    }

    func testMutationsRenderTheirSQLiteNames() {
        let a = XLJSONPath.root.key("a")
        let b = XLJSONPath.root.key("b")
        assertSQL(
            document().jsonbInserting((a, 1)),
            "jsonb_insert(:document, '$.a', 1)"
        )
        assertSQL(
            document().jsonbReplacing((a, 1)),
            "jsonb_replace(:document, '$.a', 1)"
        )
        assertSQL(
            document().jsonbSetting((a, 1), (b, 2)),
            "jsonb_set(:document, '$.a', 1, '$.b', 2)"
        )
        assertSQL(
            document().jsonbRemoving(at: a, b),
            "jsonb_remove(:document, '$.a', '$.b')"
        )
        assertSQL(
            document().jsonbPatched(with: "{}"),
            "jsonb_patch(:document, '{}')"
        )
    }

    func testAggregatesRenderTheirSQLiteNames() {
        let name = XLNamedBindingReference<String>(name: "name")
        let value = XLNamedBindingReference<Int>(name: "value")
        assertSQL(value.jsonbGroupArray(), "jsonb_group_array(:value)")
        assertSQL(
            value.jsonbGroupArray(distinct: true),
            "jsonb_group_array(DISTINCT :value)"
        )
        assertSQL(
            jsonbGroupObject(name: name, value: value),
            "jsonb_group_object(:name, :value)"
        )
    }

    func testResultTypesAreBinary() {
        let a = XLJSONPath.root.key("a")
        let value = XLNamedBindingReference<Int>(name: "value")
        assertExpressionType(jsonbArray(1), Data.self)
        assertExpressionType(jsonbObject(("a", 1)), Data.self)
        assertExpressionType(document().minifiedJSONB(), Data?.self)
        assertExpressionType(document().jsonbSetting((a, 1)), Data?.self)
        assertExpressionType(document().jsonbExtract(at: a, a), Data?.self)
        assertExpressionType(value.jsonbGroupArray(), Data.self)
        // The single-path form still follows the selected element, so a
        // scalar comes back as a scalar and not as a BLOB.
        assertExpressionType(
            document().jsonbExtract(at: a, as: Int.self),
            Int?.self
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


final class XLJSONBFunctionExecutionTests: XCTestCase {

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

    /// Every case here needs JSONB. `jsonb/1` is the whole family's marker:
    /// SQLite added all eleven functions in the same release.
    private func requireJSONB() throws {
        try SQLiteRuntimeCapability.requireFunction(
            "jsonb",
            argumentCount: 1,
            since: "SQLite 3.45.0",
            in: databasePool
        )
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

    private func evaluate<Value>(
        _ expression: any XLExpression<Value>
    ) throws -> Value? where Value: XLLiteral {
        let statement = sql { _ in Select(expression) }
        return try database.makeRequest(with: statement).fetchOne()
    }

    /// Reads a JSONB value back as JSON text, which is the only way to state
    /// an expected value without depending on SQLite's private binary layout.
    private func text(of blob: Data) throws -> String? {
        // `evaluate` returns the row, and the column is itself optional, so
        // the two optionals are flattened here rather than at every call.
        try evaluate(blob.minifiedJSON()) ?? nil
    }

    // MARK: - Round trip

    func testAJSONBValueIsABlobThatReadsBackAsTheSameDocument() throws {
        try requireJSONB()
        guard
            let row = try evaluate(
                document().minifiedJSONB(),
                document: #" { "a" : 1 } "#
            ),
            let blob = row
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertFalse(blob.isEmpty)
        XCTAssertEqual(try text(of: blob), #"{"a":1}"#)
    }

    func testTheJSONFunctionsReadJSONBWithoutConversion() throws {
        try requireJSONB()
        // #590's and #591's functions take a JSONB input directly. That is why
        // there is no `jsonb_type` or `jsonb_valid` to add here.
        guard
            let row = try evaluate(
                document().minifiedJSONB(),
                document: #"{"a":[1,2,3]}"#
            ),
            let blob = row
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try evaluate(blob.jsonType()), "object")
        XCTAssertEqual(
            try evaluate(
                blob.jsonExtract(at: XLJSONPath.root.key("a"), as: String.self)
            ),
            "[1,2,3]"
        )
        XCTAssertEqual(
            try evaluate(
                blob.jsonArrayLength(path: XLJSONPath.root.key("a"))
            ),
            3
        )
    }

    // MARK: - Constructors

    func testConstructorsBuildBinaryValues() throws {
        try requireJSONB()
        guard let array = try evaluate(jsonbArray(1, "two")) else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try text(of: array), #"[1,"two"]"#)

        guard let object = try evaluate(jsonbObject(("a", 1), ("b", 2))) else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try text(of: object), #"{"a":1,"b":2}"#)
    }

    // MARK: - Extraction

    func testSinglePathExtractionFollowsTheSelectedElement() throws {
        try requireJSONB()
        let json = #"{"n":5,"o":{"b":1}}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonbExtract(
                    at: XLJSONPath.root.key("n"),
                    as: Int.self
                ),
                document: json
            ),
            5
        )
        // An object has no SQL value, so it comes back as JSONB rather than
        // as the JSON text `json_extract` would return.
        guard
            let row = try evaluate(
                document().jsonbExtract(
                    at: XLJSONPath.root.key("o"),
                    as: Data.self
                ),
                document: json
            ),
            let blob = row
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try text(of: blob), #"{"b":1}"#)
    }

    func testMultiplePathExtractionBuildsABinaryArray() throws {
        try requireJSONB()
        guard
            let row = try evaluate(
                document().jsonbExtract(
                    at: XLJSONPath.root.key("a"),
                    XLJSONPath.root.key("b")
                ),
                document: #"{"a":1,"b":"x"}"#
            ),
            let blob = row
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try text(of: blob), #"[1,"x"]"#)
    }

    // MARK: - Mutation

    func testMutationsWriteBackAndReadAsJSON() throws {
        try requireJSONB()
        let json = #"{"a":1,"b":2}"#
        let cases: [(any XLExpression<Data?>, String)] = [
            (document().jsonbInserting((XLJSONPath.root.key("c"), 3)),
             #"{"a":1,"b":2,"c":3}"#),
            (document().jsonbReplacing((XLJSONPath.root.key("a"), 9)),
             #"{"a":9,"b":2}"#),
            (document().jsonbSetting((XLJSONPath.root.key("a"), 9)),
             #"{"a":9,"b":2}"#),
            (document().jsonbRemoving(at: XLJSONPath.root.key("a")),
             #"{"b":2}"#),
            (document().jsonbPatched(with: #"{"b":null,"c":3}"#),
             #"{"a":1,"c":3}"#),
        ]
        for (expression, expected) in cases {
            guard
                let row = try evaluate(expression, document: json),
                let blob = row
            else {
                XCTFail("the statement should return one document")
                continue
            }
            XCTAssertEqual(try text(of: blob), expected)
        }
    }

    func testAMutationOnANullDocumentIsNull() throws {
        try requireJSONB()
        let reference = XLNamedBindingReference<String?>(name: "nullDocument")
        let statement = sql { _ in
            Select(reference.jsonbSetting((XLJSONPath.root.key("a"), 1)))
        }
        var request = database.makeRequest(with: statement)
        request.set(reference, String?.none)
        guard let column = try request.fetchOne() else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(column)
    }

    // MARK: - Aggregates

    func testAggregatesCollectIntoBinaryValues() throws {
        try requireJSONB()
        try database.makeRequest(with: sqlCreate(JSONAggregateInput.self))
            .execute()
        for row in [
            JSONAggregateInput(id: "1", bucket: "a", name: "x", value: 1),
            JSONAggregateInput(id: "2", bucket: "a", name: "y", value: 2),
        ] {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }

        let arrayStatement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(input.value.jsonbGroupArray())
            From(input)
        }
        guard let array = try database.makeRequest(with: arrayStatement).fetchOne()
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try text(of: array), "[1,2]")

        let objectStatement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(jsonbGroupObject(name: input.name, value: input.value))
            From(input)
        }
        guard let object = try database.makeRequest(with: objectStatement).fetchOne()
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(try text(of: object), #"{"x":1,"y":2}"#)
    }

    func testAnEmptyGroupIsAnEmptyArrayAndNeverNull() throws {
        try requireJSONB()
        // The invariant is what matters and what the result type rests on:
        // an empty group gives an empty array, never SQL NULL. Its byte-level
        // representation is not pinned here. SQLite 3.51.0 returns the two
        // text characters `[]` rather than the JSONB encoding of an empty
        // array, and that is an engine detail this suite has no reason to
        // hold still across the versions it runs on. Reading the result back
        // through `json(X)` is what a caller would do anyway.
        try database.makeRequest(with: sqlCreate(JSONAggregateInput.self))
            .execute()
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(input.value.jsonbGroupArray())
            From(input)
        }
        guard let empty = try database.makeRequest(with: statement).fetchOne()
        else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertEqual(try text(of: empty), "[]")
    }
}
