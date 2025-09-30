//
//  Created by Luke Van In on 2023/08/10.
//

import XCTest
import SwiftQL


final class XLQueryTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        encoder = XLiteEncoder(formatter: formatter)
//        let _ = TestTable.MetaTable(context: SQLTableMetaContext(qualifiedName: XLQualifiedTableName(name: XLName("Test")), alias: XLName("test")))
//        let _ = TestColumns.MetaResult { _ in
//            TestColumns(id: "", value: nil)
//        }
    }
    
    override func tearDown() {
        encoder = nil
    }
    
    
    func testSelect() {
        let schema = XLSchema()
        let t0 = schema.table(TestTable.self)
        let expression = select(t0).from(t0)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`")
    }
    
    
    func testSelectJoin() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let t1 = s.table(TestTable.self)
        let expression = select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id )
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t1`.`id` AS `id`, `t1`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `Test` AS `t1` ON (`t1`.`id` == `t0`.`id`)")
    }
    

    func testSelectJoinJoin() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let t1 = s.table(TestTable.self)
        let t2 = s.table(TestTable.self)
        let expression = select(t2).from(t0).innerJoin(t1, on: t1.id == t0.id).innerJoin(t2, on: t2.id == t1.id)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t2`.`id` AS `id`, `t2`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `Test` AS `t1` ON (`t1`.`id` == `t0`.`id`) INNER JOIN `Test` AS `t2` ON (`t2`.`id` == `t1`.`id`)")
    }
    
    
    func testSelectWhere() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let expression = select(t0).from(t0).where(t0.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (`t0`.`id` == 'foo')")
    }
    
    
    func testSelectWhere_ExcludedJoin() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let t1 = s.table(TestTable.self)
        let expression = select(t0).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t0.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `Test` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t0`.`id` == 'foo')")
    }

    
    func testSelectJoinWhere() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let t1 = s.table(TestTable.self)
        let expression = select(t0).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t1.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `Test` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t1`.`id` == 'foo')")
    }
    
    
    func testPartialQuery() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let t1 = s.table(TestTable.self)
        let partialExpression = select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id)
        let expression = partialExpression.where(t0.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t1`.`id` AS `id`, `t1`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `Test` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t0`.`id` == 'foo')")
    }
    
    
    func testReusedfPartialQueries() {
        let s = XLSchema()
        let t0 = s.table(TestTable.self)
        let t1 = s.table(TestTable.self)
        let expression0 = select(t0).from(t0).where(t0.id == "foo")
        let expression1 = select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t0.id == "bar")
        XCTAssertEqual(encoder.makeSQL(expression0).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (`t0`.`id` == 'foo')")
        XCTAssertEqual(encoder.makeSQL(expression1).sql, "SELECT `t1`.`id` AS `id`, `t1`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `Test` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t0`.`id` == 'bar')")
    }
    
    
    func testSelectCommonTable() {
        let s = XLSchema()
        let ct0 = s.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t = s.table(ct0)
        let expression = with(ct0).select(t).from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `cte0` AS `t0`")
    }
    
    func testSelectWhereCommonTable() {
        let s = XLSchema()
        let ct0 = s.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t = s.table(ct0)
        let expression = with(ct0).select(t).from(t).where(t.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `cte0` AS `t0` WHERE (`t0`.`id` == 'foo')")
    }
    
    func testSelect_JoinCommonTable() {
        let s = XLSchema()
        let ct0 = s.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t0 = s.table(TestTable.self)
        let t1 = s.table(ct0)
        let expression = with(ct0).select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) SELECT `t1`.`id` AS `id`, `t1`.`value` AS `value` FROM `Test` AS `t0` INNER JOIN `cte0` AS `t1` ON (`t1`.`id` == `t0`.`id`)")
    }
    
    func testSelect_LeftJoinNullableCommonTable() {
        let s = XLSchema()
        let ct0 = s.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t0 = s.table(TestTable.self)
        let t1 = s.nullableTable(ct0)
        let expression = with(ct0).select(t1).from(t0).leftJoin(t1, on: t1.id == t0.id)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH `cte0` AS (SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0`) SELECT `t1`.`id` AS `id`, `t1`.`value` AS `value` FROM `Test` AS `t0` LEFT JOIN `cte0` AS `t1` ON (`t1`.`id` IS `t0`.`id`)")
    }

    
//    func testSelectFromCommonTable() {
//        let ct0 = with(as: "ct0") { query in
//            let t2 = from(TestTable.self, as: "t2")
//            return select(t2)
//        }
//        let t0 = from(ct0, as: "t0")
//        let expression = select(t0)
//        XCTAssertEqual(encoder.makeSQL(expression), "WITH `ct0` (SELECT `t2`.`id` AS `c0`, `t2`.`value` AS `c1` FROM `Test` AS `t2`) SELECT `t0`.`c0` AS `c0`, `t0`.`c1` AS `c1` FROM `ct0` AS `t0`")
//    }

    
//    func testSelectSubquery() {
//        let t0 = from(TestTable.self, as: "t0")
//        let r0 = result {
//            TestColumns(
//                id: $0.column { t0.id },
//                value: $0.subquery { query in
//                    let t1 = query.from(TestTable.self, as: "t1")
//                    return query.select(t1.value.sum())
//                }
//            )
//        }
//        let expression = select(r0)
//        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, (SELECT SUM(`t1`.`value`) FROM `Test` AS `t1`) AS `c1` FROM `Test` AS `t0`")
//    }
    
    func testSelectWhereBoolean() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let s = XLSchema()
        let t = s.table(TestTable.self, as: "t0")
        let expression = select(t).from(t).where(x == true)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (:x == 1)")
    }
    
    
    func testSelectWhereImplicitBoolean() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let s = XLSchema()
        let t = s.table(TestTable.self, as: "t0")
        let expression = select(t).from(t).where(x)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE :x")
    }

    
    func testSelectWhereOptionalBoolean_equalTo_true() {
        let x = XLNamedBindingReference<Optional<Bool>>(name: "x")
        let s = XLSchema()
        let t = s.table(TestTable.self)
        let expression = select(t).from(t).where(x == true)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (:x IS 1)")
    }
    
    
    func testSelectWhereOptionalBoolean_equalTo_false() {
        let x = XLNamedBindingReference<Optional<Bool>>(name: "x")
        let s = XLSchema()
        let t = s.table(TestTable.self)
        let expression = select(t).from(t).where(x == false)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (:x IS 0)")
    }
    
    
    func testSelectWhereOptionalBoolean_is_null() {
        let x = XLNamedBindingReference<Optional<Bool>>(name: "x")
        let s = XLSchema()
        let t = s.table(TestTable.self)
        let expression = select(t).from(t).where(x.isNull())
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT `t0`.`id` AS `id`, `t0`.`value` AS `value` FROM `Test` AS `t0` WHERE (:x ISNULL)")
    }
}
