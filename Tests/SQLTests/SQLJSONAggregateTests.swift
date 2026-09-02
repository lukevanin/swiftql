//
//  SQLJSONAggregateTests.swift
//
//
//  Milestone v1.6, issue #592: json_group_array and json_group_object. The
//  execution cases run both as a whole-result aggregate and under GROUP BY,
//  and pin the empty-group result, which is what decides that neither result
//  is optional.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLTable(name: "JSONAggregateInput")
struct JSONAggregateInput: Identifiable {

    let id: String

    let bucket: String

    let name: String

    let value: Int
}


final class XLJSONAggregateRenderingTests: XCTestCase {

    private var encoder: XLiteEncoder!

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .noEscape)
        )
    }

    override func tearDown() {
        encoder = nil
    }

    func testGroupArrayRendersItsSQLiteName() {
        let value = XLNamedBindingReference<Int>(name: "value")
        assertSQL(value.jsonGroupArray(), "json_group_array(:value)")
    }

    func testGroupArrayRendersDISTINCT() {
        let value = XLNamedBindingReference<Int>(name: "value")
        assertSQL(
            value.jsonGroupArray(distinct: true),
            "json_group_array(DISTINCT :value)"
        )
    }

    func testGroupObjectRendersItsNameAndValue() {
        let name = XLNamedBindingReference<String>(name: "name")
        let value = XLNamedBindingReference<Int>(name: "value")
        assertSQL(
            jsonGroupObject(name: name, value: value),
            "json_group_object(:name, :value)"
        )
    }

    func testBothAggregatesReturnNonOptionalJSONText() {
        let name = XLNamedBindingReference<String>(name: "name")
        let value = XLNamedBindingReference<Int>(name: "value")
        assertExpressionType(value.jsonGroupArray(), String.self)
        assertExpressionType(
            jsonGroupObject(name: name, value: value),
            String.self
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


final class XLJSONAggregateExecutionTests: XCTestCase {

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
        try! database.makeRequest(with: sqlCreate(JSONAggregateInput.self))
            .execute()
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }

    private func insert(_ rows: [JSONAggregateInput]) throws {
        for row in rows {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
    }

    private func populate() throws {
        try insert([
            JSONAggregateInput(id: "1", bucket: "a", name: "x", value: 1),
            JSONAggregateInput(id: "2", bucket: "b", name: "y", value: 2),
            JSONAggregateInput(id: "3", bucket: "a", name: "z", value: 3),
        ])
    }

    // MARK: - json_group_array

    func testGroupArrayCollectsEveryRow() throws {
        try populate()
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(input.value.jsonGroupArray())
            From(input)
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchOne(),
            "[1,2,3]"
        )
    }

    func testGroupArrayCollectsOneArrayPerGroup() throws {
        try populate()
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(input.value.jsonGroupArray())
            From(input)
            GroupBy(input.bucket)
            OrderBy(input.bucket.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            ["[1,3]", "[2]"]
        )
    }

    func testGroupArrayDropsRepeatsWhenDistinct() throws {
        try populate()
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(input.bucket.jsonGroupArray(distinct: true))
            From(input)
        }
        // SQLite promises which values survive DISTINCT, not what order they
        // arrive in, and this aggregate has no ORDER BY to fix one. Assert
        // the set, so a future SQLite that collects them differently reports
        // a real change rather than a false failure.
        guard let collected = try database.makeRequest(with: statement).fetchOne()
        else {
            XCTFail("the statement should return one row")
            return
        }
        // Decoded rather than cast: `JSONSerialization` hands back `[Any]`,
        // and a conditional cast to `[String]` relies on bridging that is
        // easy to get subtly wrong. `JSONDecoder` states the expected shape.
        let values = try JSONDecoder().decode(
            [String].self,
            from: Data(collected.utf8)
        )
        XCTAssertEqual(Set(values), ["a", "b"])
        XCTAssertEqual(values.count, 2, "DISTINCT should collapse the repeat")
    }

    func testGroupArrayOverAnEmptyGroupIsAnEmptyArray() throws {
        // Not SQL NULL. This is why the result type is not optional.
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(input.value.jsonGroupArray())
            From(input)
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchOne(),
            "[]"
        )
    }

    // MARK: - json_group_object

    func testGroupObjectCollectsNameValuePairs() throws {
        try populate()
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(jsonGroupObject(name: input.name, value: input.value))
            From(input)
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchOne(),
            #"{"x":1,"y":2,"z":3}"#
        )
    }

    func testGroupObjectCollectsOneObjectPerGroup() throws {
        try populate()
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(jsonGroupObject(name: input.name, value: input.value))
            From(input)
            GroupBy(input.bucket)
            OrderBy(input.bucket.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            [#"{"x":1,"z":3}"#, #"{"y":2}"#]
        )
    }

    func testGroupObjectOverAnEmptyGroupIsAnEmptyObject() throws {
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(jsonGroupObject(name: input.name, value: input.value))
            From(input)
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchOne(),
            "{}"
        )
    }

    func testGroupObjectKeepsARepeatedNameTwice() throws {
        // SQLite does not deduplicate names, so the result can hold the same
        // name more than once. That is valid JSON text, and readers differ on
        // what it means, so it is worth knowing rather than assuming.
        try insert([
            JSONAggregateInput(id: "1", bucket: "a", name: "same", value: 1),
            JSONAggregateInput(id: "2", bucket: "a", name: "same", value: 2),
        ])
        let statement = sql { schema in
            let input = schema.table(JSONAggregateInput.self)
            Select(jsonGroupObject(name: input.name, value: input.value))
            From(input)
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchOne(),
            #"{"same":1,"same":2}"#
        )
    }
}
