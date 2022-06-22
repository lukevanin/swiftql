import XCTest

@testable import SwiftQL

final class SQLTests: BaseTestCase {

    override func setUpWithError() throws {
        try setupDatabase()
    }
    
    override func tearDownWithError() throws {
        teardownDatabase()
    }
    
    func testCreate() throws {
        let subject = try Transaction {
            Create(User.self)
        }
        let result = subject.sql()
        print(result)
        XCTAssertEqual(
            result,
            "CREATE TABLE IF NOT EXISTS `user` ( " +
            "`id` TEXT PRIMARY KEY, " +
            "`place_id` TEXT REFERENCES `place` ( `id` ), " +
            "`username` TEXT, " +
            "`active` INT " +
            ")"
        )
    }

    func testInsert() throws {
        let subject = try Transaction {
            Insert(Sample(id: PrimaryKey(), value: 7))
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "INSERT INTO `sample` " +
            "( `id`, `value` ) " +
            "VALUES ( ?, ? )"
        )
    }

    func testUpdate() throws {
        let key = PrimaryKey()
        let subject = try Transaction {
            Update(Sample.self) { sample in
                Set {
                    sample.value = 49
                }
                Where {
                    sample.$id == key
                }
            }
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "UPDATE `sample` AS `t0` " +
            "SET `t0`.`value` = ? " +
            "WHERE `t0`.`id` == ?"
        )
    }

    func testSelectRow() throws {
        let subject = try Transaction {
            From(Sample.self) { sample in
                Select<Sample>(sample)
            }
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t0`.`value` " +
            "FROM `sample` AS `t0`"
        )
    }

    func testSelectField() throws {
        let subject = try Transaction {
            From(Sample.self) { sample in
                Select { sample.id }
            }
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `sample` AS `t0`"
        )
    }

    func testSelectWhereBooleanLiteral() throws {
        let subject = try Transaction {
            From(Place.self) { t0 in
                Select { t0.id }
                Where { t0.$verified == true }
            }
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `place` AS `t0` " +
            "WHERE `t0`.`verified` == ?"
        )
    }

    func testSelectWhereString() throws {
        let subject = try Transaction {
            From(Place.self) { t0 in
                Select { t0.id }
                Where { t0.$name == "Spain" }
            }
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `place` AS `t0` " +
            "WHERE `t0`.`name` == ?"
        )

    }

    func testSelectComplexWhere() throws {
        let subject = try Transaction {
            From(Place.self) { t0 in
                Select {
                    t0.id
                }
                Where {
                    (t0.$verified == true) && (t0.$name == "Spain")
                }
            }
        }
        let result = subject.sql()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `place` AS `t0` " +
            "WHERE `t0`.`verified` == ? AND `t0`.`name` == ?"
        )
    }

    /*

    func testSelectOrderBy() throws {
        let subject = From(User.self) { user in
            Select {
                user.id
            }
            OrderBy {
                users.username.ascending
            }
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
        let subject = From(User.self) { user in
            Select {
                user.id
            }
            OrderBy {
                user.active.descending
                user.username.ascending
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

        /*

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
         */

    func testSelectJoin() throws {
        let subject = From(Photo.self) { photo in
            Join(User.self, on: photo.userId) { user in
                Select() {
                    (photo.id, user.id)
                }
            }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t1`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id`"
        )
    }

    func testSelectTwoJoins() throws {
        let subject = From(Photo.self) { t0 in
            Join(User.self, on: t0.userId) { t1 in
                Join(Place.self, on: t0.placeId) { t2 in
                    Select() {
                        (t0.id, t1.id, t2.id)
                    }
                }
            }
        }
        let result = subject.string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t1`.`id`, `t2`.`id` " +
            "FROM `photos` AS `t0` " +
            "JOIN `users` AS `t1` ON `t0`.`user_id` == `t1`.`id` " +
            "JOIN `places` AS `t2` ON `t0`.`place_id` == `t2`.`id`"
        )
    }

    func testSelectJoinMultiple() throws {
        let subject = From(Photo.self) { t0 in
            Join(User.self, photo.userId) { t1 in
                Join(Place.self, t1.placeId) { t2 in
                    Join(Place.self, t0.placeId) { t3 in
                        Select {
                            (t0.id, t1.id, t2.id, t3.id)
                        }
                    }
                }
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
            "`t0`.`id`, `t1`.`id`, `t2`.`id`, `t3`.`id` " +
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
