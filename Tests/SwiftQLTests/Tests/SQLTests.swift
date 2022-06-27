import XCTest

@testable import SwiftQL

final class SQLTests: BaseTestCase {

//    override func setUpWithError() throws {
//        try setupDatabase()
//    }
//
//    override func tearDownWithError() throws {
//        teardownDatabase()
//    }

    func testCreate() throws {
        let db = MyDatabase.Schema()
        let subject = Create(db.users)
        let result = subject.sql().string()
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
        let db = MyDatabase.Schema()
        let subject = Insert(db.samples, Sample(id: PrimaryKey(), value: 7))
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "INSERT INTO `sample` " +
            "( `id`, `value` ) " +
            "VALUES ( ?, ? )"
        )
    }

    func testUpdate() throws {
        let key = PrimaryKey()
        let db = MyDatabase.Schema()
        let subject = Update(db.samples) { sample in
            Set {
                sample.value = 49
            }
            Where {
                sample.$id == key
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "UPDATE `sample` AS `t0` " +
            "SET `t0`.`value` = ? " +
            "WHERE `t0`.`id` = ?"
        )
    }

    func testSelectRow() throws {
        let database = MyDatabase.Schema()
        let subject = From(database.samples) { sample in
            Select<Sample>(sample)
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t0`.`value` " +
            "FROM `sample` AS `t0`"
        )
    }

    func testSelectField() throws {
        let database = MyDatabase.Schema()
        let subject = From(database.samples) { sample in
            Select { sample.id }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `sample` AS `t0`"
        )
    }

    func testSelectWhereBooleanLiteral() throws {
        let database = MyDatabase.Schema()
        let subject = From(database.samples) { t0 in
            Select { t0.id }
            Where { t0.$value == 49 }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `sample` AS `t0` " +
            "WHERE `t0`.`value` = ?"
        )
    }

    func testSelectWhereString() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.places) { t0 in
            Select { t0.id }
            Where { t0.$name == "Spain" }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `place` AS `t0` " +
            "WHERE `t0`.`name` = ?"
        )
    }

    func testSelectComplexWhere() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.places) { t0 in
            Select {
                t0.id
            }
            Where {
                (t0.$verified == true) && (t0.$name == "Spain")
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `place` AS `t0` " +
            "WHERE `t0`.`verified` = ? AND `t0`.`name` = ?"
        )
    }

    func testSelectOrderBy() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.users) { t0 in
            Select {
                t0.id
            }
            OrderBy {
                t0.$username.ascending
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `user` AS `t0` " +
            "ORDER BY `t0`.`username` ASC"
        )
    }

    func testSelectOrderByTerms() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.users) { t0 in
            Select {
                t0.id
            }
            OrderBy {
                t0.$active.descending
                t0.$username.ascending
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `user` AS `t0` " +
            "ORDER BY " +
            "`t0`.`active` DESC, " +
            "`t0`.`username` ASC"
        )
    }

    func testSelectWhereOrderBy() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Select {
                t0.id
            }
            Where {
                t0.$published == true
            }
            OrderBy {
                t0.$imageURL.ascending
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photo` AS `t0` " +
            "WHERE `t0`.`published` = ? " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoin() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Select {
                    (t0.id, t1.id)
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t1`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id`"
        )
    }

    func testSelectTwoJoins() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Join(db.places, on: t0.$placeId) { t2 in
                    Select() {
                        (t0.id, t1.id, t2.id)
                    }
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id`, `t1`.`id`, `t2`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "JOIN `place` AS `t2` ON `t2`.`id` = `t0`.`place_id`"
        )
    }

    func testSelectJoinMultiple() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Join(db.places, on: t1.$placeId) { t2 in
                    Join(db.places, on: t0.$placeId) { t3 in
                        Select {
                            (t0.id, t1.id, t2.id, t3.id)
                        }
                    }
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT " +
            "`t0`.`id`, `t1`.`id`, `t2`.`id`, `t3`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "JOIN `place` AS `t2` ON `t2`.`id` = `t1`.`place_id` " +
            "JOIN `place` AS `t3` ON `t3`.`id` = `t0`.`place_id`"
        )
    }

    func testSelectJoinWhere() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Select {
                    t0.id
                }
                Where {
                    t1.$active == true
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "WHERE `t1`.`active` = ?"
        )
    }

    func testSelectJoinOrderBy() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Select {
                    t1.username
                }
                OrderBy {
                    t0.$imageURL.ascending
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t1`.`username` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoinOrderByTerms() throws {
        let db = MyDatabase.Schema()
        let subject =  From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Select {
                    t0.id
                }
                OrderBy {
                    t0.$id.ascending
                    t1.$username.descending
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "ORDER BY " +
            "`t0`.`id` ASC, " +
            "`t1`.`username` DESC"
        )
    }

    func testSelectJoinWhereOrderBy() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Select {
                    t0.id
                }
                Where {
                    t1.$active == true
                }
                OrderBy {
                    t0.$imageURL.ascending
                }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "WHERE `t1`.`active` = ? " +
            "ORDER BY `t0`.`image_url` ASC"
        )
    }

    func testSelectJoinCompoundWhere() throws {
        let db = MyDatabase.Schema()
        let subject = From(db.photos) { t0 in
            Join(db.users, on: t0.$userId) { t1 in
                Select { t0.id }
                Where { t1.$active == true && t0.$published == true }
            }
        }
        let result = subject.sql().string()
        XCTAssertEqual(
            result,
            "SELECT `t0`.`id` " +
            "FROM `photo` AS `t0` " +
            "JOIN `user` AS `t1` ON `t1`.`id` = `t0`.`user_id` " +
            "WHERE `t1`.`active` = ? AND `t0`.`published` = ?"
        )
    }
}
