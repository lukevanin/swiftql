import XCTest

@testable import SwiftQL

final class ExecuteTests: BaseTestCase {

    /*
    override func setUpWithError() throws {
        try setupDatabase()
    }
    
    override func tearDownWithError() throws {
        teardownDatabase()
    }
    
    func testInsertOneThenSelectUncached() throws {
        let expectedSample = Sample(id: PrimaryKey(), value: 7)
        try database.execute(cached: false) { db in
            let sample = db.samples()
            Insert(sample, values: expectedSample)
        }
        let result = try database.execute(cached: false) { db in
            let sample = db.samples()
            Select(sample)
            From(sample)
        }
        XCTAssertEqual(result, [expectedSample])
    }
    
    func testInsertTwoThenSelectUncached() throws {
        let expectedSample0 = Sample(id: PrimaryKey(), value: 7)
        let expectedSample1 = Sample(id: PrimaryKey(), value: 3)
        try database.execute(cached: false) { db in
            let sample = db.samples()
            Insert(sample, values: expectedSample0)
        }
        try database.execute(cached: false) { db in
            let sample = db.samples()
            Insert(sample, values: expectedSample1)
        }
        let result = try database.execute(cached: false) { db in
            let sample = db.samples()
            Select(sample)
            From(sample)
            OrderBy { sample.$value.ascending }
        }
        XCTAssertEqual(result, [expectedSample1, expectedSample0])
    }
    
    func testInsertTwoThenSelect() throws {
        let expectedSample0 = Sample(id: PrimaryKey(), value: 7)
        let expectedSample1 = Sample(id: PrimaryKey(), value: 3)
        try database.execute(cached: true) { db in
            let sample = db.samples()
            Insert(sample, values: expectedSample0)
        }
        try database.execute(cached: true) { db in
            let sample = db.samples()
            Insert(sample, values: expectedSample1)
        }
        let result = try database.execute(cached: true) { db in
            let sample = db.samples()
            Select(sample)
            From(sample)
            OrderBy { sample.$value.ascending }
        }
        XCTAssertEqual(result, [expectedSample1, expectedSample0])
    }

    func testInsertThenSelectJoin() throws {
        let expectedPlace = Place(id: PrimaryKey(), name: "United States", verified: true)
        let expectedUser = User(id: PrimaryKey(), placeId: expectedPlace.id, username: "johndoe", active: true)
        try database.execute() { db in
            let user = db.users()
            Insert(user, values: expectedUser)
        }
        try database.execute() { db in
            let place = db.places()
            Insert(place, values: expectedPlace)
        }
        let results = try database.execute() { db in
            let user = db.users()
            let place = db.places()
            Select() {
                (
                    user: user.username,
                    place: place.name
                )
            }
            From(user)
            Join(place) { user.$placeId == place.id }
        }
        XCTAssertEqual(results[0].user, "johndoe")
        XCTAssertEqual(results[0].place, "United States")
    }
     */
}
