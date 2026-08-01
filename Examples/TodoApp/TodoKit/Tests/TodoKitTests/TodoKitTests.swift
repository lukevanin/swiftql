import XCTest

import TodoKit

final class TodoKitTests: XCTestCase {

    func testANewDatabaseStartsEmpty() throws {
        let database = try TodoDatabase.ephemeral()

        XCTAssertEqual(try database.launchProbeCount(), 0)
    }

    func testAnInsertedRowIsReadBackThroughTheDeclaredQuery() throws {
        let database = try TodoDatabase.ephemeral()

        try database.insertProbe()
        try database.insertProbe()

        XCTAssertEqual(try database.launchProbeCount(), 2)
    }

    func testTwoDatabasesDoNotShareRows() throws {
        let first = try TodoDatabase.ephemeral()
        let second = try TodoDatabase.ephemeral()

        try first.insertProbe()

        XCTAssertEqual(try first.launchProbeCount(), 1)
        XCTAssertEqual(try second.launchProbeCount(), 0)
    }
}
