import XCTest

@testable import SwiftQL

final class SwiftQLTests: XCTestCase {
    
    var fileURL: URL!
    var resource: SQLite.Resource!
    var connection: SQLite.Connection!
    var database: MyDatabase!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let filename = UUID().uuidString
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = directory.appendingPathComponent(filename).appendingPathExtension("sqlite3")
        resource = SQLite.Resource(fileURL: fileURL)
        connection = try resource.connect()
        database = MyDatabase(connection: connection)
        try database.query { db in Create(db.users()) }.execute()
        try database.query { db in Create(db.photos()) }.execute()
        try database.query { db in Create(db.samples()) }.execute()
        try database.query { db in Create(db.places()) }.execute()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        database = nil
        connection = nil
        resource = nil
    }

//    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
//    }

//    func testPerformanceExample() throws {
        // This is an example of a performance test case.
//        measure {
            // Put the code you want to measure the time of here.
//        }
//    }
    
    func testCreate() throws {
        let subject = try database.query { db in
            Create(db.users())
        }
        let result = subject.string()
        print(result)
        XCTAssertEqual(
            result,
            "CREATE TABLE IF NOT EXISTS `users` ( " +
            "`id` TEXT PRIMARY KEY NOT NULL, " +
            "`place_id` TEXT REFERENCES `places` ( `id` ) NOT NULL, " +
            "`username` TEXT NOT NULL, " +
            "`active` INT NOT NULL " +
            ")"
        )
    }
    
    func testInsert() throws {
        let subject = try database.query() { db in
            let sample = db.samples()
            Insert(sample, Sample(id: "foo", value: 7))
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "INSERT INTO `samples` " +
            "( `id`, `value` ) " +
            "VALUES ( ?1, ?2 )"
        )
    }
    
    func testUpdate() throws {
        let subject = try database.query() { db in
            let sample = db.samples()
            Update(sample) {
                Set(sample.value, 49)
            }
            Where { sample.id == "foo" }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "UPDATE `samples` AS `t0` " +
            "SET `value` = ?1 " +
            "WHERE `t0`.`id` == ?2"
        )
    }

    func testSelect() throws {
        let subject = try database.query() { db in
            let sample = db.samples()
            Select(sample)
            From(sample)
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t0`.`value` " +
            "FROM `samples` AS `t0`"
        )
    }

    func testSelectField() throws {
        let subject = try database.query() { db in
            let sample = db.samples()
            Select { row in
                row.field(sample.id)
            }
            From(sample)
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `samples` AS `t0`"
        )
    }

    func testSelectWhereBooleanLiteral() throws {
        let subject = try database.query() { db in
            let place = db.places()
            Select { row in
                row.field(place.id)
            }
            From(place)
            Where { place.verified == true }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `places` AS `t0` " +
            "WHERE `t0`.`verified` == ?1"
        )
    }

    func testSelectWhereBooleanBinding() throws {
        let subject = try database.query() { db in
            let place = db.places()
            Select { row in
                row.field(place.id)
            }
            From(place)
            Where { place.verified == true }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `places` AS `t0` " +
            "WHERE `t0`.`verified` == ?1"
        )
    }

    func testSelectWhereString() throws {
        let subject = try database.query() { db in
            let place = db.places()
            Select { row in
                row.field(place.id)
            }
            From(place)
            Where { place.name == "Spain" }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `places` AS `t0` " +
            "WHERE `t0`.`name` == ?1"
        )
    }

    func testSelectComplexWhere() throws {
        let subject = try database.query() { db in
            let place = db.places()
            Select { row in
                row.field(place.id)
            }
            From(place)
            Where { (place.verified == true) && (place.name == "Spain") }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `places` AS `t0` " +
            "WHERE `t0`.`verified` == ?1 AND `t0`.`name` == ?2"
        )
    }

    func testSelectOrderBy() throws {
        let subject = try database.query { db in
            let users = db.users()
            Select { row in
                row.field(users.id)
            }
            From(users)
            OrderBy { users.username.ascending }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `users` AS `t0` " +
            "ORDER BY `t0`.`username` ASC"
        )
    }

    func testSelectOrderByTerms() throws {
        let subject = try database.query { db in
            let users = db.users()
            Select { row in
                row.field(users.id)
            }
            From(users)
            OrderBy {
                users.active.descending
                users.username.ascending
            }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `users` AS `t0` " +
            "ORDER BY " +
            "`t0`.`active` DESC, " +
            "`t0`.`username` ASC"
        )
    }

    func testSelectWhereOrderBy() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            Select { row in
                row.field(photo.id)
            }
            From(photo)
            Where { photo.published == true }
            OrderBy { photo.imageURL.ascending }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "WHERE `t0`.`published` == ?1 " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoin() throws {
        let subject = try database.query() { db in
            let photo = db.photos()
            let user = db.users()
            Select() { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id`"
        )
    }

    func testSelectTwoJoins() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            let user = db.users()
            let place = db.places()
            Select() { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            Join(place) { photo.placeId == place.id }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "JOIN `places` AS `t2` ON `t0`.`place_id` == `t2`.`id`"
        )
    }
    
    func testSelectJoinMultiple() throws {
        let subject = try database.query() { db in
            let photo = db.photos()
            let user = db.users()
            let userPlace = db.places()
            let photoPlace = db.places()
            Select { row in
                (
                    username: row.field(user.username),
                    userPlaceName: row.field(userPlace.name),
                    photoURL: row.field(photo.imageURL),
                    photoPlaceName: row.field(photoPlace.name)
                )
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            Join(userPlace) { userPlace.id == user.placeId }
            Join(photoPlace) { photoPlace.id == photo.placeId }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT " +
            "`t1`.`username`, " +
            "`t2`.`name`, " +
            "`t0`.`image_url`, " +
            "`t3`.`name` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "JOIN `places` AS `t2` ON `t2`.`id` == `t1`.`place_id` " +
            "JOIN `places` AS `t3` ON `t3`.`id` == `t0`.`place_id`"
        )
    }


    func testSelectJoinWhere() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            let user = db.users()
            Select { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            Where { user.active == true }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "WHERE `t1`.`active` == ?1"
        )
    }

    func testSelectJoinOrderBy() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            let user = db.users()
            Select { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            OrderBy { photo.imageURL.ascending }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoinOrderByTerms() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            let user = db.users()
            Select { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            OrderBy {
                photo.id.ascending
                user.username.descending
            }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "ORDER BY " +
            "`t0`.`id` ASC, " +
            "`t1`.`username` DESC"
        )
    }

    func testSelectJoinWhereOrderBy() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            let user = db.users()
            Select { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            Where { user.active == true }
            OrderBy { photo.imageURL.ascending }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "WHERE `t1`.`active` == ?1 " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoinCompoundWhere() throws {
        let subject = try database.query { db in
            let photo = db.photos()
            let user = db.users()
            Select { row in
                row.field(photo.id)
            }
            From(photo)
            Join(user) { photo.userId == user.id }
            Where { user.active == true && photo.published == true }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "WHERE `t1`.`active` == ?1 AND `t0`.`published` == ?2"
        )
    }
    
    func testInsertOneThenSelect() throws {
        let expectedSample = Sample(id: "a", value: 7)
        let insertQuery =  try database.query() { db in
            let sample = db.samples()
            Insert(sample, expectedSample)
        }
        let selectQuery = try database.query { db in
            let sample = db.samples()
            Select(sample)
            From(sample)
        }
        try insertQuery.execute()
        let result = try selectQuery.execute()
        XCTAssertEqual(result, [expectedSample])
    }
    
    func testInsertTwoThenSelect() throws {
        let expectedSample0 = Sample(id: "a", value: 7)
        let expectedSample1 = Sample(id: "b", value: 3)
        try database.execute { db in
            let sample = db.samples()
            Insert(sample, expectedSample0)
        }
        try database.execute { db in
            let sample = db.samples()
            Insert(sample, expectedSample1)
        }
        let result = try database.execute { db in
            let sample = db.samples()
            Select(sample)
            From(sample)
            OrderBy { sample.value.ascending }
        }
        XCTAssertEqual(result, [expectedSample1, expectedSample0])
    }
    
    func testInsertThenSelectJoin() throws {
        let expectedUser = User(id: "john", placeId: "us", username: "johndoe", active: true)
        let expectedPlace = Place(id: "us", name: "United States", verified: true)
        try database.execute { db in
            let user = db.users()
            Insert(user, expectedUser)
        }
        try database.execute { db in
            let place = db.places()
            Insert(place, expectedPlace)
        }
        let results = try database.execute { db in
            let user = db.users()
            let place = db.places()
            Select() { row in
                (
                    user: row.field(user.username),
                    place: row.field(place.name)
                )
            }
            From(user)
            Join(place) { user.placeId == place.id }
        }
        XCTAssertEqual(results[0].user, "johndoe")
        XCTAssertEqual(results[0].place, "United States")
    }
    
}
