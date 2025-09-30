//
//  XLBuilderTests.swift
//  
//
//  Created by Luke Van In on 2023/08/10.
//

/*
import XCTest
import SwiftQL


final class XLFunctionalQueryTests: XCTestCase {
    
    var schema: XLSchema!
    
    var encoder: XLiteEncoder!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        encoder = XLiteEncoder(formatter: formatter)
        schema = XLSchema()
        let _ = TestTable.MetaTable(context: SQLTableMetaContext(qualifiedName: XLQualifiedTableName(name: XLName("Test")), alias: XLName("test")))
        let _ = TestColumns.MetaResult { _ in
            TestColumns(id: "", value: nil)
        }
    }
    
    override func tearDown() {
        encoder = nil
        schema = nil
    }
    
    
    func testSelect() {
        let t0 = TestTable.asTable(alias: "t0")
        let expression = schema.select(t0).from(t0)
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0`")
    }
    
    
    func testSelectJoin() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asTable(alias: "t1")
        let expression = schema
            .select(t0)
            .from(t0)
            .innerJoin(t1, on: t1.id == t0.id)
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` INNER JOIN `TestTable` AS `t1` ON (`t1`.`id` == `t0`.`id`)")
    }
    
    
    func testSelectJoinJoin() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asTable(alias: "t1")
        let t2 = TestTable.asTable(alias: "t2")
        let expression = schema
            .select(t0)
            .from(t0)
            .innerJoin(t1, on: t1.id == t0.id)
            .innerJoin(t2, on: t2.id == t1.id)
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` INNER JOIN `TestTable` AS `t1` ON (`t1`.`id` == `t0`.`id`) INNER JOIN `TestTable` AS `t2` ON (`t2`.`id` == `t1`.`id`)")
    }
    
    
    func testSelectWhere() {
        let t0 = TestTable.asTable(alias: "t0")
        let expression = schema
            .select(t0)
            .from(t0)
            .where(t0.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` WHERE (`t0`.`id` == 'foo')")
    }
    
    
    func testSelectJoinWhere() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asTable(alias: "t1")
        let expression = schema
            .select(t0)
            .from(t0)
            .innerJoin(t1, on: t1.id == t0.id)
            .where(t0.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` INNER JOIN `TestTable` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t0`.`id` == 'foo')")
    }
    
    
    func testPartialQuery() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asTable(alias: "t1")
        let partialExpression = schema
            .select(t0)
            .from(t0)
            .innerJoin(t1, on: t1.id == t0.id)
        let expression = partialExpression
            .where(t0.id == "foo")
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` INNER JOIN `TestTable` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t0`.`id` == 'foo')")
    }
    
    
    func testReusedfPartialQueries() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asTable(alias: "t1")
        let partialExpression = schema
            .select(t0)
            .from(t0)
        let expression0 = partialExpression
            .innerJoin(t1, on: t1.id == t0.id)
            .where(t0.id == "foo")
        let expression1 = partialExpression
            .where(t0.id == "bar")
        XCTAssertEqual(encoder.makeSQL(expression0), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` INNER JOIN `TestTable` AS `t1` ON (`t1`.`id` == `t0`.`id`) WHERE (`t0`.`id` == 'foo')")
        XCTAssertEqual(encoder.makeSQL(expression1), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` WHERE (`t0`.`id` == 'bar')")
    }
    
    
    func testSelectCommonTable() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asCommonTable(alias: "t1") {
            let t2 = TestTable.asTable(alias: "t2")
            return schema
                .select(t2)
                .from(t2)
        }
        let expression = schema
            .with(t1)
            .select(t0)
            .from(t0)
        XCTAssertEqual(encoder.makeSQL(expression), "WITH `t1` (SELECT `t2`.`id` AS `c0`, `t2`.`value` AS `c1` FROM `TestTable` AS `t2`) SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0`")
    }
    
    
    func testSelectSubquery() {
        let t0 = TestTable.asTable(alias: "t0")
        let t1 = TestTable.asTable(alias: "t1")
        let r = TestColumns.asResult {
            TestColumns(
                id: $0.column { t0.id },
                value: $0.subquery(
                    self.schema
                        .select(t1.value.sum())
                        .from(t1)
                )
            )
        }
        let expression = schema
            .select(r)
            .from(t0)
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, (SELECT SUM(`t1`.`value`) FROM `TestTable` AS `t1`) AS `c1` FROM `TestTable` AS `t0`")
    }
    
    
    func testSelectWhereBoolean() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let t0 = TestTable.asTable(alias: "t0")
        let expression = schema
            .select(t0)
            .from(t0)
            .where(
                x == true
            )
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` WHERE (:x == 1)")
    }
    
    
    func testSelectWhereOptionalBoolean() {
        let x = XLNamedBindingReference<Optional<Bool>>(name: "x")
        let t0 = TestTable.asTable(alias: "t0")
        let expression = schema
            .select(t0)
            .from(t0)
            .where(x == true)
        XCTAssertEqual(encoder.makeSQL(expression), "SELECT `t0`.`id` AS `c0`, `t0`.`value` AS `c1` FROM `TestTable` AS `t0` WHERE (:x IS 1)")
    }
}
*/
