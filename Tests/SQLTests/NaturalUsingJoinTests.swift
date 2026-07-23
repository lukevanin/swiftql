//
//  NaturalUsingJoinTests.swift
//
//  Coverage for NATURAL JOIN and USING (...) join constraints (#45).
//

import Foundation
import XCTest
import GRDB
import SwiftQL


@SQLTable(name: "Passport")
struct PassportTable: Equatable, Identifiable {
    let id: String
    let country: String
}


@SQLTable(name: "Citizen")
struct CitizenTable: Equatable, Identifiable {
    let id: String
    let fullName: String
}


@SQLResult
struct PassportCitizenRow: Equatable {
    let name: String
    let country: String
}


final class NaturalUsingJoinTests: XCTestCase {

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

    func testNaturalJoinRendersWithoutConstraint() {
        let statement = sql { schema in
            let passport = schema.table(PassportTable.self)
            let citizen = schema.table(CitizenTable.self)
            Select(PassportCitizenRow.columns(name: citizen.fullName, country: passport.country))
            From(passport)
            Join.Natural(citizen)
        }
        XCTAssertEqual(
            encoder.makeSQL(statement).sql,
            "SELECT `t1`.`fullName` AS `name`, `t0`.`country` AS `country` FROM `Passport` AS `t0` NATURAL JOIN `Citizen` AS `t1`"
        )
    }

    func testUsingJoinRendersColumnList() {
        let statement = sql { schema in
            let passport = schema.table(PassportTable.self)
            let citizen = schema.table(CitizenTable.self)
            Select(PassportCitizenRow.columns(name: citizen.fullName, country: passport.country))
            From(passport)
            Join.Inner(citizen, using: "id")
        }
        XCTAssertEqual(
            encoder.makeSQL(statement).sql,
            "SELECT `t1`.`fullName` AS `name`, `t0`.`country` AS `country` FROM `Passport` AS `t0` INNER JOIN `Citizen` AS `t1` USING (`id`)"
        )
    }

    func testFluentNaturalAndUsingJoinsRender() {
        let schema = XLSchema()
        let passport = schema.table(PassportTable.self)
        let citizen = schema.table(CitizenTable.self)
        let natural = select(PassportCitizenRow.columns(name: citizen.fullName, country: passport.country))
            .from(passport)
            .naturalJoin(citizen)
        XCTAssertEqual(
            encoder.makeSQL(natural).sql,
            "SELECT `t1`.`fullName` AS `name`, `t0`.`country` AS `country` FROM `Passport` AS `t0` NATURAL JOIN `Citizen` AS `t1`"
        )

        let schema2 = XLSchema()
        let passport2 = schema2.table(PassportTable.self)
        let citizen2 = schema2.table(CitizenTable.self)
        let using = select(PassportCitizenRow.columns(name: citizen2.fullName, country: passport2.country))
            .from(passport2)
            .innerJoin(citizen2, using: "id")
        XCTAssertEqual(
            encoder.makeSQL(using).sql,
            "SELECT `t1`.`fullName` AS `name`, `t0`.`country` AS `country` FROM `Passport` AS `t0` INNER JOIN `Citizen` AS `t1` USING (`id`)"
        )
    }

    // MARK: - Execution

    func testNaturalJoinExecutesMatchingSharedColumn() throws {
        try seed()
        let statement = sql { schema in
            let passport = schema.table(PassportTable.self)
            let citizen = schema.table(CitizenTable.self)
            Select(PassportCitizenRow.columns(name: citizen.fullName, country: passport.country))
            From(passport)
            Join.Natural(citizen)
            OrderBy(citizen.fullName.ascending())
        }
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [PassportCitizenRow(name: "Ann", country: "US")])
    }

    func testUsingJoinExecutesMatchingSharedColumn() throws {
        try seed()
        let statement = sql { schema in
            let passport = schema.table(PassportTable.self)
            let citizen = schema.table(CitizenTable.self)
            Select(PassportCitizenRow.columns(name: citizen.fullName, country: passport.country))
            From(passport)
            Join.Inner(citizen, using: "id")
            OrderBy(citizen.fullName.ascending())
        }
        let rows = try database.makeRequest(with: statement).fetchAll()
        XCTAssertEqual(rows, [PassportCitizenRow(name: "Ann", country: "US")])
    }

    private func seed() throws {
        try database.makeRequest(with: sqlCreate(PassportTable.self)).execute()
        try database.makeRequest(with: sqlCreate(CitizenTable.self)).execute()
        for passport in [
            PassportTable(id: "a", country: "US"),
            PassportTable(id: "b", country: "UK"),
        ] {
            try database.makeRequest(with: sqlInsert(passport)).execute()
        }
        for citizen in [
            CitizenTable(id: "a", fullName: "Ann"),
            CitizenTable(id: "c", fullName: "Cy"),
        ] {
            try database.makeRequest(with: sqlInsert(citizen)).execute()
        }
    }
}
