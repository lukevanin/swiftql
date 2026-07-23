//
//  ScalarCommonTableTests.swift
//
//  Direct-scalar common table expressions and scalar compound queries (#43).
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLTable(name: "Number")
struct NumberRow: Equatable, Identifiable {
    let id: String
    let value: Int
}


@SQLTable(name: "Blob")
struct BlobRow: Equatable, Identifiable {
    let id: String
    let payload: Data
}


final class ScalarCommonTableTests: XCTestCase {

    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        encoder = XLiteEncoder(formatter: formatter)
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        encoder = nil
        databasePool = nil
        database = nil
    }

    // MARK: - Rendering

    func testScalarCommonTableRendersExplicitColumnList() {
        let schema = XLSchema()
        let cte = schema.scalarCommonTable(Int.self) { s in
            let number = s.table(NumberRow.self)
            return select(number.value).from(number)
        }
        let output = schema.table(cte)
        let query = with(cte).select(output.value).from(output)
        XCTAssertEqual(
            encoder.makeSQL(query).sql,
            "WITH `cte0`(`value`) AS (SELECT `t0`.`value` FROM `Number` AS `t0`) SELECT `t0`.`value` FROM `cte0` AS `t0`"
        )
    }

    // MARK: - Execution

    func testNonRecursiveScalarCommonTableExecutesAsInt() throws {
        try database.makeRequest(with: sqlCreate(NumberRow.self)).execute()
        for row in [NumberRow(id: "a", value: 3), NumberRow(id: "b", value: 1), NumberRow(id: "c", value: 2)] {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
        let statement = sql { schema in
            let cte = schema.scalarCommonTable(Int.self) { inner in
                let number = inner.table(NumberRow.self)
                return select(number.value).from(number)
            }
            let output = schema.table(cte)
            With(cte)
            Select(output.value)
            From(output)
            OrderBy(output.value.ascending())
        }
        let rows: [Int] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [1, 2, 3])
    }

    func testScalarCompoundQueryExecutesWithoutWrapper() throws {
        try database.makeRequest(with: sqlCreate(NumberRow.self)).execute()
        for row in [NumberRow(id: "a", value: 1), NumberRow(id: "b", value: 2)] {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
        let schema = XLSchema()
        let number = schema.table(NumberRow.self)
        let statement = select(number.value).from(number)
            .unionAll { select(number.value).from(number) }
        let rows: [Int] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows.sorted(), [1, 1, 2, 2])
    }

    func testEmptyScalarCommonTableFetchesNoRows() throws {
        try database.makeRequest(with: sqlCreate(NumberRow.self)).execute()
        let statement = sql { schema in
            let cte = schema.scalarCommonTable(Int.self) { inner in
                let number = inner.table(NumberRow.self)
                return select(number.value).from(number)
            }
            let output = schema.table(cte)
            With(cte)
            Select(output.value)
            From(output)
        }
        let rows: [Int] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [])
    }

    /// The recursive organization example from the documentation, expressed with
    /// a direct scalar common table instead of `SQLScalarResult<String?>`.
    func testRecursiveScalarCommonTableExecutesOrgHierarchy() throws {
        try database.makeRequest(with: sqlCreate(Org.self)).execute()
        for value in [
            Org(name: "Alice", boss: nil),
            Org(name: "Jane", boss: "Alice"),
            Org(name: "Rachel", boss: "Alice"),
            Org(name: "Cindy", boss: "Jane"),
            Org(name: "Candace", boss: "Jane"),
            Org(name: "Dick", boss: nil),
            Org(name: "Bob", boss: "Dick"),
        ] {
            try database.makeRequest(with: sqlInsert(value)).execute()
        }

        let statement = sql { schema in
            let cte = schema.recursiveScalarCommonTable(String?.self) { inner, this in
                let org = inner.table(Org.self)
                return select("Alice".toNullable())
                    .union {
                        select(org.name)
                            .from(org)
                            .crossJoin(this)
                            .where(org.boss == this.value)
                    }
            }
            let org = schema.table(Org.self)
            With(cte)
            Select(org.name)
            From(org)
            Where(org.name.in(cte))
        }

        let result: [String?] = try database.makeRequest(with: statement).fetchAll()
        let names = Set(result.compactMap { $0 })
        XCTAssertEqual(names, ["Alice", "Jane", "Rachel", "Cindy", "Candace"])
    }

    func testScalarCommonTableExecutesAsStringOverUnionDistinct() throws {
        try database.makeRequest(with: sqlCreate(NumberRow.self)).execute()
        for row in [NumberRow(id: "a", value: 1), NumberRow(id: "b", value: 2)] {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
        let statement = sql { schema in
            let cte = schema.scalarCommonTable(String.self) { inner in
                let number = inner.table(NumberRow.self)
                return select(number.id).from(number)
                    .union { select(number.id).from(number) }
            }
            let output = schema.table(cte)
            With(cte)
            Select(output.value)
            From(output)
            OrderBy(output.value.ascending())
        }
        let rows: [String] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, ["a", "b"])
    }

    func testScalarCommonTableExecutesAsData() throws {
        try database.makeRequest(with: sqlCreate(BlobRow.self)).execute()
        let payload = Data([0x01, 0x02, 0x03])
        try database.makeRequest(with: sqlInsert(BlobRow(id: "a", payload: payload))).execute()
        let statement = sql { schema in
            let cte = schema.scalarCommonTable(Data.self) { inner in
                let blob = inner.table(BlobRow.self)
                return select(blob.payload).from(blob)
            }
            let output = schema.table(cte)
            With(cte)
            Select(output.value)
            From(output)
        }
        let rows: [Data] = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [payload])
    }

    func testQueryBuilderComposesScalarCommonTable() throws {
        try database.makeRequest(with: sqlCreate(NumberRow.self)).execute()
        for row in [NumberRow(id: "a", value: 5), NumberRow(id: "b", value: 7)] {
            try database.makeRequest(with: sqlInsert(row)).execute()
        }
        let schema = XLSchema()
        let cte = schema.scalarCommonTable(Int.self) { inner in
            let number = inner.table(NumberRow.self)
            return select(number.value).from(number)
        }
        let output = schema.table(cte)
        let query = QueryBuilder(select: output.value)
            .with(cte)
            .from(output)
            .orderBy(output.value.ascending())
        let rows: [Int] = try database.makeRequest(with: query.build()).fetchAll()
        XCTAssertEqual(rows, [5, 7])
    }
}
