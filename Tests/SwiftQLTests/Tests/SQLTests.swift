import XCTest

@testable import SwiftQL

final class SwiftQLTests: BaseTestCase {

    override func setUpWithError() throws {
        try setupDatabase()
    }
    
    override func tearDownWithError() throws {
        teardownDatabase()
    }
    
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
            "VALUES ( ?, ? )"
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
            "SET `value` = ? " +
            "WHERE `t0`.`id` == ?"
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
            "WHERE `t0`.`verified` == ?"
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
            "WHERE `t0`.`verified` == ?"
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
            "WHERE `t0`.`name` == ?"
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
            "WHERE `t0`.`verified` == ? AND `t0`.`name` == ?"
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
            "WHERE `t0`.`published` == ? " +
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
            "WHERE `t1`.`active` == ?"
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
            "WHERE `t1`.`active` == ? " +
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
            "WHERE `t1`.`active` == ? AND `t0`.`published` == ?"
        )
    }
}
