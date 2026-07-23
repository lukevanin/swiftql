//
//  MaterializedCommonTableTests.swift
//
//  Coverage for MATERIALIZED / NOT MATERIALIZED common table hints (#10).
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLResult
struct MaterializedScalar: Equatable {
    let scalarValue: Int
}


final class MaterializedCommonTableTests: XCTestCase {

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
        encoder = nil
        databasePool = nil
        database = nil
    }

    // MARK: - Rendering

    func testMaterializedCommonTableRendersKeyword() {
        let schema = XLSchema()
        let cte = schema.commonTable(materialization: .materialized) { s in
            let company = s.table(CompanyTable.self)
            return select(company).from(company)
        }
        let table = schema.table(cte)
        let query = with(cte).select(table).from(table)
        XCTAssertEqual(
            encoder.makeSQL(query).sql,
            "WITH `cte0` AS MATERIALIZED (SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `cte0` AS `t0`"
        )
    }

    func testNotMaterializedCommonTableRendersKeyword() {
        let schema = XLSchema()
        let cte = schema.commonTable(materialization: .notMaterialized) { s in
            let company = s.table(CompanyTable.self)
            return select(company).from(company)
        }
        let table = schema.table(cte)
        let query = with(cte).select(table).from(table)
        XCTAssertEqual(
            encoder.makeSQL(query).sql,
            "WITH `cte0` AS NOT MATERIALIZED (SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `cte0` AS `t0`"
        )
    }

    func testUnspecifiedMaterializationRendersNoKeyword() {
        let schema = XLSchema()
        let cte = schema.commonTable { s in
            let company = s.table(CompanyTable.self)
            return select(company).from(company)
        }
        let table = schema.table(cte)
        let query = with(cte).select(table).from(table)
        XCTAssertEqual(
            encoder.makeSQL(query).sql,
            "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `Company` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`name` AS `name` FROM `cte0` AS `t0`"
        )
    }

    func testMaterializedRecursiveCommonTableRendersKeyword() {
        let schema = XLSchema()
        let cte = schema.recursiveCommonTable(MaterializedScalar.self, materialization: .materialized) { s, this in
            select(MaterializedScalar.columns(scalarValue: 1))
                .unionAll {
                    select(MaterializedScalar.columns(scalarValue: this.scalarValue + 1))
                        .from(this)
                        .where(this.scalarValue < 3)
                }
        }
        let table = schema.table(cte)
        let query = with(cte).select(table).from(table)
        XCTAssertEqual(
            encoder.makeSQL(query).sql,
            "WITH `cte0` AS MATERIALIZED (SELECT 1 AS `scalarValue` UNION ALL SELECT (`t0`.`scalarValue` + 1) AS `scalarValue` FROM `cte0` AS `t0` WHERE (`t0`.`scalarValue` < 3)) SELECT `t0`.`scalarValue` AS `scalarValue` FROM `cte0` AS `t0`"
        )
    }

    func testMaterializationCarriesThroughDependencyModifier() {
        let base = XLCommonTableDependency(alias: "cte", statement: MaterializedInlineExpression(value: 1))
        XCTAssertEqual(base.materialization, .unspecified)
        XCTAssertEqual(base.materialized(.materialized).materialization, .materialized)
        XCTAssertEqual(base.materialized(.notMaterialized).materialization, .notMaterialized)
        // The original value is unchanged (value semantics).
        XCTAssertEqual(base.materialization, .unspecified)
    }

    // MARK: - Execution

    func testMaterializedCommonTableExecutes() throws {
        try skipUnlessSQLiteSupportsMaterializationHints()
        try seedCompanies()
        let statement = sql { schema in
            let cte = schema.commonTableExpression(materialization: .materialized) { inner in
                let company = inner.table(CompanyTable.self)
                Select(company)
                From(company)
            }
            let table = schema.table(cte)
            With(cte)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(
            rows,
            [
                CompanyTable(id: "c1", name: "Acme"),
                CompanyTable(id: "c2", name: "Globex"),
            ]
        )
    }

    func testNotMaterializedCommonTableExecutes() throws {
        try skipUnlessSQLiteSupportsMaterializationHints()
        try seedCompanies()
        let statement = sql { schema in
            let cte = schema.commonTableExpression(materialization: .notMaterialized) { inner in
                let company = inner.table(CompanyTable.self)
                Select(company)
                From(company)
            }
            let table = schema.table(cte)
            With(cte)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(
            rows,
            [
                CompanyTable(id: "c1", name: "Acme"),
                CompanyTable(id: "c2", name: "Globex"),
            ]
        )
    }

    private func seedCompanies() throws {
        try database.makeRequest(with: sqlCreate(CompanyTable.self)).execute()
        for company in [
            CompanyTable(id: "c1", name: "Acme"),
            CompanyTable(id: "c2", name: "Globex"),
        ] {
            try database.makeRequest(with: sqlInsert(company)).execute()
        }
    }

    /// Skips a test when the linked SQLite is older than 3.35.0, the release that
    /// introduced the `MATERIALIZED` / `NOT MATERIALIZED` CTE hints.
    private func skipUnlessSQLiteSupportsMaterializationHints() throws {
        let version = try databasePool.read { database in
            try String.fetchOne(database, sql: "SELECT sqlite_version()") ?? ""
        }
        let components = version.split(separator: ".").compactMap { Int($0) }
        let required = [3, 35, 0]
        var supported = true
        for index in required.indices {
            let value = index < components.count ? components[index] : 0
            if value != required[index] {
                supported = value > required[index]
                break
            }
        }
        if !supported {
            throw XCTSkip("MATERIALIZED CTE hints require SQLite 3.35.0 or later; linked SQLite is \(version).")
        }
    }
}


private struct MaterializedInlineExpression: XLExpression {
    typealias T = Int
    let value: Int
    func makeSQL(context: inout XLBuilder) {
        context.integer(value)
    }
}
