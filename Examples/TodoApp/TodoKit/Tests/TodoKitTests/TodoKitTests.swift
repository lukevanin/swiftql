import XCTest

import TodoKit

final class TodoKitTests: XCTestCase {

    func testANewDatabaseStartsEmpty() throws {
        let database = try TodoDatabase.temporary()

        XCTAssertEqual(try database.launchProbeCount(), 0)
    }

    func testAnInsertedRowIsReadBackThroughTheDeclaredQuery() throws {
        let database = try TodoDatabase.temporary()

        try database.insertProbe()
        try database.insertProbe()

        XCTAssertEqual(try database.launchProbeCount(), 2)
    }

    func testTwoDatabasesDoNotShareRows() throws {
        let first = try TodoDatabase.temporary()
        let second = try TodoDatabase.temporary()

        try first.insertProbe()

        XCTAssertEqual(try first.launchProbeCount(), 1)
        XCTAssertEqual(try second.launchProbeCount(), 0)
    }
}
