//
//  FullOuterCrossJoinTests.swift
//
//  Coverage for FULL OUTER JOIN and CROSS JOIN (#95).
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLResult
struct FullOuterRow: Equatable, Hashable {
    let company: String?
    let employee: String?
}


@SQLResult
struct CrossRow: Equatable {
    let company: String
    let employee: String
}


final class FullOuterCrossJoinTests: XCTestCase {

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

    func testFullOuterJoinRendersWithBothSidesNullable() {
        let statement = sql { schema in
            let company = schema.nullableTable(CompanyTable.self)
            let employee = schema.nullableTable(EmployeeTable.self)
            Select(FullOuterRow.columns(company: company.name, employee: employee.name))
            From(company)
            Join.FullOuter(employee, on: employee.companyId == company.id)
        }
        XCTAssertEqual(
            encoder.makeSQL(statement).sql,
            "SELECT `t0`.`name` AS `company`, `t1`.`name` AS `employee` FROM `Company` AS `t0` FULL OUTER JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`)"
        )
    }

    func testFluentFullOuterJoinRenders() {
        let schema = XLSchema()
        let company = schema.nullableTable(CompanyTable.self)
        let employee = schema.nullableTable(EmployeeTable.self)
        let statement = select(FullOuterRow.columns(company: company.name, employee: employee.name))
            .from(company)
            .fullOuterJoin(employee, on: employee.companyId == company.id)
        XCTAssertEqual(
            encoder.makeSQL(statement).sql,
            "SELECT `t0`.`name` AS `company`, `t1`.`name` AS `employee` FROM `Company` AS `t0` FULL OUTER JOIN `Employee` AS `t1` ON (`t1`.`companyId` IS `t0`.`id`)"
        )
    }

    func testQueryBuilderCrossJoinRenders() throws {
        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let employee = schema.table(EmployeeTable.self)
        let query = QueryBuilder(select: CrossRow.columns(company: company.name, employee: employee.name))
            .from(company)
            .crossJoin(employee)
        XCTAssertEqual(
            try encoder.makeSQL(query.build()).sql,
            "SELECT `t0`.`name` AS `company`, `t1`.`name` AS `employee` FROM `Company` AS `t0` CROSS JOIN `Employee` AS `t1`"
        )
    }

    // MARK: - Execution

    /// A `FULL OUTER JOIN`, executed. Every row of both tables must appear: the
    /// matched pair, the company with no employee (NULL employee), and the
    /// employee with no company (NULL company).
    func testFullOuterJoinExecutesKeepingUnmatchedRowsFromBothSides() throws {
        try skipUnlessSQLiteSupportsOuterJoins()
        try database.makeRequest(with: sqlCreate(CompanyTable.self)).execute()
        try database.makeRequest(with: sqlCreate(EmployeeTable.self)).execute()
        for company in [
            CompanyTable(id: "c1", name: "Staffed"),
            CompanyTable(id: "c2", name: "Empty"),
        ] {
            try database.makeRequest(with: sqlInsert(company)).execute()
        }
        for employee in [
            EmployeeTable(id: "e1", name: "Worker", companyId: "c1", managerEmployeeId: nil),
            EmployeeTable(id: "e2", name: "Ghost", companyId: "cX", managerEmployeeId: nil),
        ] {
            try database.makeRequest(with: sqlInsert(employee)).execute()
        }

        let statement = sql { schema in
            let company = schema.nullableTable(CompanyTable.self)
            let employee = schema.nullableTable(EmployeeTable.self)
            Select(FullOuterRow.columns(company: company.name, employee: employee.name))
            From(company)
            Join.FullOuter(employee, on: employee.companyId == company.id)
        }
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows.count, 3, "FULL OUTER JOIN must not produce duplicate rows")
        XCTAssertEqual(
            Set(rows),
            [
                FullOuterRow(company: "Staffed", employee: "Worker"),
                FullOuterRow(company: "Empty", employee: nil),
                FullOuterRow(company: nil, employee: "Ghost"),
            ]
        )
    }

    /// A `CROSS JOIN`, executed. Returns every combination of the two tables'
    /// rows (2 companies × 2 employees = 4 rows).
    func testCrossJoinExecutesEveryCombination() throws {
        try database.makeRequest(with: sqlCreate(CompanyTable.self)).execute()
        try database.makeRequest(with: sqlCreate(EmployeeTable.self)).execute()
        for company in [
            CompanyTable(id: "c1", name: "Acme"),
            CompanyTable(id: "c2", name: "Globex"),
        ] {
            try database.makeRequest(with: sqlInsert(company)).execute()
        }
        for employee in [
            EmployeeTable(id: "e1", name: "Ann", companyId: nil, managerEmployeeId: nil),
            EmployeeTable(id: "e2", name: "Bob", companyId: nil, managerEmployeeId: nil),
        ] {
            try database.makeRequest(with: sqlInsert(employee)).execute()
        }

        let schema = XLSchema()
        let company = schema.table(CompanyTable.self)
        let employee = schema.table(EmployeeTable.self)
        let query = QueryBuilder(select: CrossRow.columns(company: company.name, employee: employee.name))
            .from(company)
            .crossJoin(employee)
        let rows = try database.makeRequest(with: query.build()).fetchAll()
        XCTAssertEqual(
            Set(rows.map { "\($0.company)/\($0.employee)" }),
            ["Acme/Ann", "Acme/Bob", "Globex/Ann", "Globex/Bob"]
        )
    }

    /// Skips a test when the linked SQLite is older than 3.39.0, the release that
    /// introduced `FULL OUTER JOIN`.
    private func skipUnlessSQLiteSupportsOuterJoins() throws {
        let version = try databasePool.read { database in
            try String.fetchOne(database, sql: "SELECT sqlite_version()") ?? ""
        }
        // Parse each component's leading numeric prefix so pre-release suffixes
        // (e.g. "3.39.0rc1") do not drop or misread a component.
        let components = version.split(separator: ".").map { component -> Int in
            Int(component.prefix(while: \.isNumber)) ?? 0
        }
        let required = [3, 39, 0]
        var supported = true
        for index in required.indices {
            let value = index < components.count ? components[index] : 0
            if value != required[index] {
                supported = value > required[index]
                break
            }
        }
        if !supported {
            throw XCTSkip("FULL OUTER JOIN requires SQLite 3.39.0 or later; linked SQLite is \(version).")
        }
    }
}
