//
//  SQLJSONMutationTests.swift
//
//
//  Milestone v1.6, issue #591: json_extract and the five mutation functions.
//  The execution cases pin what SQLite writes back, including the
//  single-path/multiple-path split in json_extract.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLJSONMutationRenderingTests: XCTestCase {

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

    // MARK: - Extraction

    func testSinglePathExtractionRendersOnePath() {
        assertSQL(
            document().jsonExtract(at: XLJSONPath.root.key("a"), as: Int.self),
            "json_extract(:document, '$.a')"
        )
    }

    func testMultiplePathExtractionRendersEveryPath() {
        assertSQL(
            document().jsonExtract(
                at: XLJSONPath.root.key("a"),
                XLJSONPath.root.key("b")
            ),
            "json_extract(:document, '$.a', '$.b')"
        )
        assertSQL(
            document().jsonExtract(
                at: XLJSONPath.root.key("a"),
                XLJSONPath.root.key("b"),
                XLJSONPath.root.key("c")
            ),
            "json_extract(:document, '$.a', '$.b', '$.c')"
        )
    }

    func testTheTwoExtractionFormsHaveDifferentResultTypes() {
        assertExpressionType(
            document().jsonExtract(at: XLJSONPath.root, as: Int.self),
            Int?.self
        )
        assertExpressionType(
            document().jsonExtract(at: XLJSONPath.root, XLJSONPath.root),
            String?.self
        )
    }

    // MARK: - Mutation

    func testMutationFunctionsRenderTheirPathValuePairsInOrder() {
        let a = XLJSONPath.root.key("a")
        let b = XLJSONPath.root.key("b")
        assertSQL(
            document().jsonInserting((a, 1)),
            "json_insert(:document, '$.a', 1)"
        )
        assertSQL(
            document().jsonReplacing((a, 1), (b, "x")),
            "json_replace(:document, '$.a', 1, '$.b', 'x')"
        )
        assertSQL(
            document().jsonSetting((a, 1), (b, "x")),
            "json_set(:document, '$.a', 1, '$.b', 'x')"
        )
    }

    func testRemovalRendersEveryPath() {
        assertSQL(
            document().jsonRemoving(at: XLJSONPath.root.key("a")),
            "json_remove(:document, '$.a')"
        )
        assertSQL(
            document().jsonRemoving(
                at: XLJSONPath.root.key("a"),
                XLJSONPath.root.key("b")
            ),
            "json_remove(:document, '$.a', '$.b')"
        )
    }

    func testPatchRendersBothDocuments() {
        assertSQL(
            document().jsonPatched(with: #"{"a":null}"#),
            #"json_patch(:document, '{"a":null}')"#
        )
    }

    func testAWrittenValueMayBeABoundParameter() {
        let value = XLNamedBindingReference<String>(name: "value")
        assertSQL(
            document().jsonSetting((XLJSONPath.root.key("a"), value)),
            "json_set(:document, '$.a', :value)"
        )
    }

    func testAMutationOnANullableDocumentIsOptional() {
        let a = XLJSONPath.root.key("a")
        let nullable = XLNamedBindingReference<String?>(name: "document")
        assertExpressionType(nullable.jsonInserting((a, 1)), String?.self)
        assertExpressionType(nullable.jsonReplacing((a, 1)), String?.self)
        assertExpressionType(nullable.jsonSetting((a, 1)), String?.self)
        assertExpressionType(nullable.jsonRemoving(at: a), String?.self)
        assertExpressionType(nullable.jsonPatched(with: "{}"), String?.self)
    }

    func testAMutationOnANonNullDocumentIsNotOptional() {
        // Each `let` is inferred, so the assertion names the overload Swift
        // picks when nothing else constrains the result.
        let a = XLJSONPath.root.key("a")
        let inserted = document().jsonInserting((a, 1))
        let replaced = document().jsonReplacing((a, 1))
        let set = document().jsonSetting((a, 1), (a, "x"))
        let removed = document().jsonRemoving(at: a, a)
        assertExpressionType(inserted, String.self)
        assertExpressionType(replaced, String.self)
        assertExpressionType(set, String.self)
        assertExpressionType(removed, String.self)
        // `json_patch` gives `NULL` for a `NULL` patch, so it stays optional.
        let patched = document().jsonPatched(with: "{}")
        assertExpressionType(patched, String?.self)
    }

    func testTheOptionalFormStillServesAnOptionalContext() {
        // A call site written before the non-optional overloads existed:
        // an optional context and `coalesce` both still resolve, and render
        // the same SQL.
        let a = XLJSONPath.root.key("a")
        let optional: any XLExpression<String?> = document().jsonSetting((a, 1))
        assertSQL(optional, "json_set(:document, '$.a', 1)")
        assertSQL(
            document().jsonSetting((a, 1)).coalesce(document()),
            "COALESCE(json_set(:document, '$.a', 1), :document)"
        )
        assertSQL(
            document().jsonRemoving(at: a).coalesce(document()),
            "COALESCE(json_remove(:document, '$.a'), :document)"
        )
    }

    func testAMutationAssignsToANonNullAndToANullableColumn() {
        // `Person.name` is `String` and `Person.occupationId` is `String?`.
        let statement = sql { schema in
            let person = schema.into(Person.self)
            Update(person)
            Setting(person) { row in
                // A non-null column takes the result without `coalesce`.
                row.name = person.name
                    .jsonSetting((XLJSONPath.root.key("a"), 1))
                // A nullable column takes the optional result.
                row.occupationId = person.occupationId
                    .jsonRemoving(at: XLJSONPath.root.key("a"))
            }
            Where(person.id == "p")
        }
        let coalesced = sql { schema in
            let person = schema.into(Person.self)
            Update(person)
            Setting(person) { row in
                // The spelling used before the non-optional form existed.
                row.name = person.name
                    .jsonInserting((XLJSONPath.root.key("a"), 1))
                    .coalesce(person.name)
                // A non-null document into a nullable column.
                row.occupationId = person.name
                    .jsonReplacing((XLJSONPath.root.key("a"), 1))
            }
            Where(person.id == "p")
        }
        let sql = encoder.makeSQL(statement).sql
        XCTAssertTrue(sql.contains("name = json_set(t0.name, '$.a', 1)"), sql)
        XCTAssertTrue(sql.contains("occupationId = json_remove(t0.occupationId, '$.a')"), sql)
        let coalescedSQL = encoder.makeSQL(coalesced).sql
        XCTAssertTrue(
            coalescedSQL.contains("name = COALESCE(json_insert(t0.name, '$.a', 1), t0.name)"),
            coalescedSQL
        )
        XCTAssertTrue(
            coalescedSQL.contains("occupationId = json_replace(t0.name, '$.a', 1)"),
            coalescedSQL
        )
    }

    func testANonOptionalRemovalRejectsTheRootPath() {
        XCTAssertEqual(
            encoder.makeSQL(
                document().jsonRemoving(at: XLJSONPath.root.key("a"), .root)
            ).valueEncodingError,
            .jsonRootRemoval(function: "json_remove")
        )
        XCTAssertNil(
            encoder.makeSQL(
                document().jsonRemoving(at: XLJSONPath.root.key("a"))
            ).valueEncodingError
        )
        // The optional form can hold `NULL`, so it still renders the root.
        let nullable = XLNamedBindingReference<String?>(name: "document")
        let rendered = encoder.makeSQL(nullable.jsonRemoving(at: .root))
        XCTAssertNil(rendered.valueEncodingError)
        XCTAssertEqual(rendered.sql, "json_remove(:document, '$')")
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


final class XLJSONMutationExecutionTests: XCTestCase {

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

    // MARK: - Extraction

    func testSinglePathExtractionReturnsTheElementAsASQLValue() throws {
        let json = #"{"name":"Alice","age":41,"ratio":0.5,"tags":["a"]}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("name"),
                    as: String.self
                ),
                document: json
            ),
            "Alice"
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("age"),
                    as: Int.self
                ),
                document: json
            ),
            41
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("ratio"),
                    as: Double.self
                ),
                document: json
            ),
            0.5
        )
        // An array has no SQL value, so SQLite returns its JSON text.
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("tags"),
                    as: String.self
                ),
                document: json
            ),
            #"["a"]"#
        )
    }

    func testSinglePathExtractionIsNullForAMissingPathAndForAJSONNull() throws {
        let json = #"{"a":null}"#
        guard
            let missing = try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("z"),
                    as: Int.self
                ),
                document: json
            ),
            let jsonNull = try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("a"),
                    as: Int.self
                ),
                document: json
            )
        else {
            XCTFail("both statements should return one row")
            return
        }
        XCTAssertNil(missing)
        XCTAssertNil(jsonNull)
    }

    func testMultiplePathExtractionReturnsAJSONArray() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("a"),
                    XLJSONPath.root.key("b")
                ),
                document: #"{"a":1,"b":"x"}"#
            ),
            #"[1,"x"]"#
        )
    }

    func testAMissingPathContributesJSONNullToTheArray() throws {
        // The array keeps one entry per path. A missing path does not shorten
        // it, so entry order still matches path order.
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("a"),
                    XLJSONPath.root.key("z")
                ),
                document: #"{"a":1}"#
            ),
            "[1,null]"
        )
    }

    // MARK: - Mutation

    func testInsertAddsOnlyWhereNothingIsThere() throws {
        let json = #"{"a":1}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonInserting((XLJSONPath.root.key("b"), 2)),
                document: json
            ),
            #"{"a":1,"b":2}"#
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonInserting((XLJSONPath.root.key("a"), 9)),
                document: json
            ),
            #"{"a":1}"#
        )
    }

    func testReplaceOverwritesOnlyWhereSomethingIsThere() throws {
        let json = #"{"a":1}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonReplacing((XLJSONPath.root.key("a"), 9)),
                document: json
            ),
            #"{"a":9}"#
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonReplacing((XLJSONPath.root.key("b"), 9)),
                document: json
            ),
            #"{"a":1}"#
        )
    }

    func testSetAddsAndOverwrites() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonSetting(
                    (XLJSONPath.root.key("a"), 9),
                    (XLJSONPath.root.key("b"), 8)
                ),
                document: #"{"a":1}"#
            ),
            #"{"a":9,"b":8}"#
        )
    }

    func testRemoveDeletesEveryNamedPath() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonRemoving(
                    at: XLJSONPath.root.key("a"),
                    XLJSONPath.root.key("c")
                ),
                document: #"{"a":1,"b":2,"c":3}"#
            ),
            #"{"b":2}"#
        )
    }

    func testPatchMergesAndRemovesNullMembers() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonPatched(with: #"{"b":null,"c":3}"#),
                document: #"{"a":1,"b":2}"#
            ),
            #"{"a":1,"c":3}"#
        )
    }

    func testAMutationOnANullDocumentIsNull() throws {
        let reference = XLNamedBindingReference<String?>(name: "nullDocument")
        let statement = sql { _ in
            Select(reference.jsonSetting((XLJSONPath.root.key("a"), 1)))
        }
        var request = database.makeRequest(with: statement)
        request.set(reference, String?.none)
        guard let column = try request.fetchOne() else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(column)
    }

    func testANonOptionalRootRemovalFailsBeforeSQLitePreparesTheStatement() {
        let statement = sql { _ in
            Select(document().jsonRemoving(at: .root))
        }
        var request = database.makeRequest(with: statement)
        request.set(document(), "{}")
        XCTAssertThrowsError(try request.fetchOne()) { error in
            XCTAssertEqual(
                error as? XLSQLValueEncodingError,
                .jsonRootRemoval(function: "json_remove")
            )
        }
    }

    // MARK: - Written values

    func testAWrittenLiteralHoldingQuotesAndBackslashesRoundTrips() throws {
        let awkward = #"he said "hi" \ and ' too"#
        guard
            let written = try evaluate(
                document().jsonSetting((XLJSONPath.root.key("a"), awkward)),
                document: "{}"
            )
        else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("a"),
                    as: String.self
                ),
                document: written
            ),
            awkward
        )
    }

    func testAWrittenBoundParameterHoldingQuotesAndBackslashesRoundTrips() throws {
        let awkward = #"he said "hi" \ and ' too"#
        let value = XLNamedBindingReference<String>(name: "value")
        let statement = sql { _ in
            Select(document().jsonSetting((XLJSONPath.root.key("a"), value)))
        }
        var request = database.makeRequest(with: statement)
        request.set(document(), "{}")
        request.set(value, awkward)
        guard let written = try request.fetchOne() else {
            XCTFail("the statement should return one document")
            return
        }
        XCTAssertEqual(
            try evaluate(
                document().jsonExtract(
                    at: XLJSONPath.root.key("a"),
                    as: String.self
                ),
                document: written
            ),
            awkward
        )
    }
}
