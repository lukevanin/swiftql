//
//  GRDBStatementLifecycleTests.swift
//  SQLTests
//
//  Issue #677: the GRDB connection's statement lifecycle hooks. Resetting a
//  statement drops the values bound to it, and a statement stays with the
//  connection that prepared it.
//

import Foundation
import SwiftQLTestSupport
import XCTest
@testable import SwiftQL


final class GRDBStatementLifecycleTests: XCTestCase {

    func testResetDropsTheBoundValuesSoTheStatementCanBeBoundAgain() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "grdb-statement-lifecycle")
        defer { fixture.tearDown() }
        let driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: XLSQLiteDialect())
        let logicalStatement = makeLogicalStatement(for: driver, sql: "SELECT :value")

        let (first, second) = try driver.withBlockingReadConnection { connection in
            var statement = try connection.prepare(logicalStatement)
            statement = try connection.bind(.integer(1), to: .named("value"), in: statement)
            let first = try connection.fetchOne(statement)

            statement = try connection.resetPhysical(statement)
            XCTAssertThrowsError(
                try connection.validateBindings(in: statement),
                "A reset statement has no values bound."
            )

            statement = try connection.bind(.integer(2), to: .named("value"), in: statement)
            let second = try connection.fetchOne(statement)
            connection.finalizePhysical(statement)
            return (first, second)
        }

        XCTAssertEqual(first, [.integer(1)])
        XCTAssertEqual(second, [.integer(2)])
    }

    func testResetRefusesAStatementFromAnotherConnection() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "grdb-statement-lifecycle-owner")
        defer { fixture.tearDown() }
        let driver = GRDBDatabaseDriver(databasePool: fixture.pool, dialect: XLSQLiteDialect())
        let logicalStatement = makeLogicalStatement(for: driver, sql: "SELECT 1")
        let foreignStatement = try driver.withBlockingReadConnection { connection in
            try connection.prepare(logicalStatement)
        }

        XCTAssertThrowsError(
            try driver.withBlockingReadConnection { connection in
                try connection.resetPhysical(foreignStatement)
            }
        ) { error in
            guard case .prepareFailure = error as? XLDatabaseContractError else {
                return XCTFail("Expected an ownership failure, got \(error).")
            }
        }
    }

    private func makeLogicalStatement(
        for driver: GRDBDatabaseDriver,
        sql: String
    ) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: XLDialectRequirement(
                identity: XLSQLiteDialect.identity,
                capabilities: [.namedBindings]
            ),
            sql: sql
        )
    }
}
