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
            let samples = db.samples()
            Insert(samples, values: Sample(id: PrimaryKey(), value: 7))
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "INSERT INTO `samples` " +
            "( `id`, `value` ) " +
            "VALUES ( ?, ? )"
        )
    }
    
    /*
    func testUpdate() throws {
        let subject = try database.query() { db in
            let sample = db.samples()
            Update(sample) {
                Set(sample.$value, 49)
            }
            Where { sample.$id == "foo" }
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
            Select(sample.id)
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
        let subject = try database.query() {
            From(\.places) { place in
                Select { row in
                    row.field(place.id)
                }
                Where { place.verified == true }
            }
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
        let subject = try database.query() {
            From(\.places) { place
                Select { row in
                    row.field(place.id)
                }
                Where { place.verified == true }
            }
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
        let subject = try database.query {
            let t0 = db.photos
            let t1 = db.users
            let t2 = db.places
            Select() { row in
                row.field(photo.id)
            }
            From(db.photos)
            Join(db.users, on: t0.userId)
            Join(db.places, on: t0.placeId)
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
        let subject = try database { db in
            let photo = From(db.photos)
            let user = Join(db.users, photo.userId)
            let userPlace = Join(db.places, user.placeId)
            let photoPlace = Join(db.places, photo.placeId)
            Select { row in
                (
                    username: row.field(user.username),
                    userPlaceName: row.field(userPlace.name),
                    photoURL: row.field(photo.imageURL),
                    photoPlaceName: row.field(photoPlace.name)
                )
            }
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
    
    
//    struct Query<Database>: SelectQuery {
//        var query: some ReadStatement = {
//            let photo = From(\.photo)
//            Select {
//                photo.id
//            }
//        }
//    }

    
//    struct Query<Database>: SelectQuery {
//        var query: ReadStatement = {
//            let photo = From(\.photo)
//            let user = Join(\.user, on: photo.$userId)
//            Select {
//                (
//                    id: photo.id,
//                    imageURL: user.imageURL
//                )
//            }
//            Where {
//                photo.$isActive == active
//            }
//            OrderBy {
//                photo.modifiedData.descending
//                user.name.ascending
//            }
//        }
//    }


    func testSelectJoinWhere() throws {
        let subject = try database.query {
            let photo = From(\.photos)
            let user = Join(\.users, on: photo.$id)
            Select {
                photo.id
            }
            Where {
                user.$active == true
            }
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
        let subject = try database.query {
            From(\.photos) { t0 in
                Join(\.users, on: t0.userId)
                    Select {
                        t1.username
                    }
                    OrderBy {
                        t0.imageURL.ascending
                    }
                }
            }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t1`.`username` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoinOrderBy_shouldExcludeUnReferencedJoin() throws {
        let subject = try database.query() { db in
            let photos = \.photos) { t0 in
                Join(\.users, on: t0.$userId) { t1 in
                    Select {
                        t1.username
                    }
                    OrderBy {
                        t0.$imageURL.ascending
                    }
                }
            }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t1`.`username` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` " +
            "ON `t0`.`user_id` == `t1`.`id` " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoinOrderByTerms() throws {
        let subject = try database.query { t in
            let t0 = t.photos
            let t1 = t.users
            Select { t1.username }
            From(t0)
            Join(user, on: t0.userId)
            OrderBy {
                t0.id.ascending
                t1.username.descending
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
            Select { photo.id }
            From(photo)
            Join(user, on: photo.$userId)
            Where { user.$active == true }
            OrderBy { photo.$imageURL.ascending }
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
            let photo = db.photos
            let user = db.users
            Select { photo.id }
            From(photo)
            Join(user, on: photo.userId)
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
     */
}
