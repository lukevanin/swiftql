//
//  XLSyntaxTests.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import XCTest
import SwiftQL


final class XLSyntaxTests: XCTestCase {
    
    
    var encoder: XLiteEncoder!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .noEscape
        )
        encoder = XLiteEncoder(formatter: formatter)
    }
    
    override func tearDown() {
        encoder = nil
    }
    
    
    // MARK: - Literal
    
    
    func test_Boolean_True() {
        let expression: Bool = true
        XCTAssertEqual(encoder.makeSQL(expression).sql, "1")
    }
    
    
    func test_Boolean_False() {
        let expression: Bool = false
        XCTAssertEqual(encoder.makeSQL(expression).sql, "0")
    }
    
    
    func test_IntegerLiteral() {
        let expression: Int = 12
        XCTAssertEqual(encoder.makeSQL(expression).sql, "12")
    }
    
    
    func test_RealLiteral() {
        let expression: Double = 17.4
        XCTAssertEqual(encoder.makeSQL(expression).sql, "17.4")
    }
    
    
    func test_TextLiteral() {
        let expression: String = "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "'foo'")
    }
    
    
    func test_BlobLiteral() {
        let expression: Data = Data([0x01])
        XCTAssertEqual(encoder.makeSQL(expression).sql, "x'01'")
    }
    
    
    
    // MARK: - Column reference
    
    
#warning("TODO: Test column reference")
    
    
    // MARK: - Function
    
    
#warning("TODO: Test function")
    
    
    // MARK: - Bind parameter
    
    
#warning("TODO: Test bind parameters")
    
    
    // MARK: - Integer unary opperator
    
    
    func testPlusOperator_IntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = +x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "+:x")
    }
    
    
    func testNegateOperator_IntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = -x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "-:x")
    }
    
    
#warning("TODO: Test bitwise negate")
    
    
    // MARK: - Integer binary operator
    
    
    func test_IntegerReference_Plus_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x + :y)")
    }
    
    
    func test_IntegerReference_Minus_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x - y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x - :y)")
    }
    
    
    func test_IntegerReference_Plus_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x + 7
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x + 7)")
    }
    
    
    func test_IntegerReference_Minus_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x - 7
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x - 7)")
    }
    
    
    func test_Integer_Plus_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = 7 + x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(7 + :x)")
    }
    
    
    // MARK: - Optional integer binary operator
    
    
    func test_OptionalIntegerReference_Plus_OptionalIntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x + :y)")
    }
    
    
    func test_OptionalIntegerReference_Plus_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x + 7
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x + 7)")
    }
    
    func test_Integer_Plus_OptionalIntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = 7 + x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(7 + :x)")
    }
    
    
    func test_OptionalIntegerReference_Plus_IntegerReference() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x + :y)")
    }
    
    
    func test_IntegerReference_Plus_OptionalIntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Optional<Int>>(name: "y")
        let expression = x + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x + :y)")
    }
    
    
#warning("TODO: Test -, *, /, and %")
    
    
    // MARK: - Unary boolean
    
    
#warning("TODO: Test unary boolean")
    
    func test_Not_BooleanReference() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let expression = !x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(NOT :x)")
    }
    
    
    // MARK: - Integer operators
    
    func test_TextBindingReference_EqualTo_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x == 12
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x == 12)")
    }
    
    func test_IntegerBindingReference_GreaterThan_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x > 7
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x > 7)")
    }
    
    //    func test_IntegerBindingReference_LessThan_Integer() {
    //        let x = XLNamedBindingReference<Int>(name: "x")
    //        let expression = x < 7
    //        XCTAssertEqual(encoder.makeSQL(expression), "(:x < 7)")
    //    }
    
    //    func testGreaterThanOrEqualToBinaryBooleanOperator_NumericExpression() {
    //        let x = XLIntegerBindingReference(name: "x")
    //        let expression = x >= 7
    //        XCTAssertEqual(encoder.makeSQL(expression), "(:x >= 7)")
    //    }
    
    //    func testLessThanOrEqualToBinaryBooleanOperator_NumericExpression() {
    //        let x = XLIntegerBindingReference(name: "x")
    //        let expression = x <= 7
    //        XCTAssertEqual(encoder.makeSQL(expression), "(:x <= 7)")
    //    }
    
    // MARK: - Binary operators
    
    func testAndBinaryBooleanOperator_BooleanExpression() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let y = XLNamedBindingReference<Bool>(name: "y")
        let expression = x && y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x AND :y)")
    }
    
    func testOrBinaryBooleanOperator_BooleanExpression() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let y = XLNamedBindingReference<Bool>(name: "y")
        let expression = x || y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x OR :y)")
    }
    
    func testAndBinaryBooleanOperator_NumericExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = (x > 7) && (x < 12)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "((:x > 7) AND (:x < 12))")
    }
    
    func testOrBinaryBooleanOperator_NumericExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = (x > 7) || (x == 12)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "((:x > 7) OR (:x == 12))")
    }
    
    
    // MARK: - Text operators
    
    
    func test_TextBindingReference_EqualTo_String() {
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x == "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x == 'foo')")
    }
    
    
    func test_TextBindingReference_Plus_String() {
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x + "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, ":x || 'foo'")
    }
    
    
    // MARK: - Null
    
    
    func testIsNull_OptionalNumericExpression() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x.isNull()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x ISNULL)")
    }
    
    func testIsNotNull_OptionalNumericExpression() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x.notNull()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x NOTNULL)")
    }
    
    
    func testIsNull_OptionalTextExpression() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.isNull()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x ISNULL)")
    }
    
    func testIsNotNull_OptionalTextExpression() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.notNull()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x NOTNULL)")
    }
    
    
    // MARK: - Null coalesce
    
    
    func test_OptionalIntegerBinding_Coalesce_Integer() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x.coalesce(7)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "COALESCE(:x, 7)")
    }
    
    
    func test_OptionalIntegerBinding_CoalescingOperator_Integer() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x ?? 7
        XCTAssertEqual(encoder.makeSQL(expression).sql, "COALESCE(:x, 7)")
    }
    
    
    // MARK: - Text concatenation
    
    func test_TextBinding_Plus_String() {
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x + "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, ":x || 'foo'")
    }
    
    func test_TextBinding_Plus_TextBinding() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, ":x || :y")
    }
    
    func test_TextBinding_Plus_String_Plus_TextBinding() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + "foo" + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, ":x || 'foo' || :y")
    }
    
    func test_OptionalTextBinding_Plus_Text() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x + "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, ":x || 'foo'")
    }
    
    
    // MARK: - Between
    
    
#warning("TODO: Test between")
    
    //    func testBetweenOperator_NumericExpression() {
    //        let x = XLIntegerBindingReference(name: "x")
    //        let expression = x.isBetween(7, 12)
    //        XCTAssertEqual(encoder.makeSQL(expression), ":x BETWEEN 7 AND 12")
    //    }
    
    
    // MARK: -  Case expression
    
    
#warning("TODO: Support CASE x WHEN y THEN z END")
    
    //    func testCaseWhenThen() {
    //        let x = XLNamedBindingReference<Int>(name: "x")
    //        let expression = Case {
    //            When { x == 12 }
    //            Then { "blue" }
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "CASE WHEN (:x == 12) THEN 'blue' END")
    //    }
    
    
    //    func testCaseWhenThenElse() {
    //        let x = XLNamedBindingReference<Int>(name: "x")
    //        let expression = Case {
    //            When { x == 12 }
    //            Then { "blue" }
    //            Else { "red" }
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "CASE WHEN (:x == 12) THEN 'blue' ELSE 'red' END")
    //    }
    
    
    // MARK: - IN
    
    
    func test_TextBinding_In_Subquery() {
        let schema = XLSchema()
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x.in {
            let t = schema.table(EmployeeTable.self)
            return select(t.id).from(t).where(t.managerEmployeeId.isNull())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x IN (SELECT t0.id FROM Employee AS t0 WHERE (t0.managerEmployeeId ISNULL)))")
    }
    
    
    func test_OptionalTextBinding_In_Subquery() {
        let schema = XLSchema()
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.in {
            let t = schema.table(EmployeeTable.self, as: "t")
            return select(t.id).from(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x IN (SELECT t.id FROM Employee AS t))")
    }
    
    
    // MARK: - Timestamp
    
    
    //    func test_TimeInterval() {
    //        let expression = XLTimeInterval(Date(timeIntervalSince1970: 0))
    //        XCTAssertEqual(encoder.makeSQL(expression), "0.0")
    //    }
    //
    //
    //    func test_TimeInterval_EqualTo_TimeInterval() {
    //        let a = XLTimeInterval(Date(timeIntervalSince1970: 0))
    //        let b = XLTimeInterval(Date(timeIntervalSince1970: 1))
    //        let expression = a == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(0.0 == 1.0)")
    //    }
    //
    //
    //    func test_TimeInterval_toISO8601Date() {
    //        let a = XLTimeInterval(Date(timeIntervalSince1970: 0))
    //        let expression = a.toISO8601Date()
    //        XCTAssertEqual(encoder.makeSQL(expression), "0.0")
    //    }
    //
    //
    //    func test_TimeInterval_toISO8601Date_equalTo_ISO8601Date() {
    //        let a = XLTimeInterval(Date(timeIntervalSince1970: 0))
    //        let b = XLISO8601Date(Date(timeIntervalSince1970: 1))
    //        let expression = a.toISO8601Date() == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(0.0 == unixepoch('1970-01-01T00:00:01.000Z', 'subsec'))")
    //    }
    
    
    // MARK: - ISO8601Date
    
    
    //    func test_ISO8601Date() {
    //        let expression = XLISO8601Date(Date(timeIntervalSince1970: 0))
    //        XCTAssertEqual(encoder.makeSQL(expression), "unixepoch('1970-01-01T00:00:00.000Z', 'subsec')")
    //    }
    //
    //
    //    func test_ISO8601Date_equalTo_ISO8601Date() {
    //        let a = XLISO8601Date(Date(timeIntervalSince1970: 0))
    //        let b = XLISO8601Date(Date(timeIntervalSince1970: 1))
    //        let expression = a == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(unixepoch('1970-01-01T00:00:00.000Z', 'subsec') == unixepoch('1970-01-01T00:00:01.000Z', 'subsec'))")
    //    }
    //
    //
    //    func test_ISO8601Date_toTimeInterval() {
    //        let a = XLISO8601Date(Date(timeIntervalSince1970: 0))
    //        let expression = a.toTimeInterval()
    //        XCTAssertEqual(encoder.makeSQL(expression), "unixepoch('1970-01-01T00:00:00.000Z', 'subsec')")
    //    }
    //
    //
    //    func test_ISO8601Date_toTimeInterval_equalTo_TimeInterval() {
    //        let a = XLISO8601Date(Date(timeIntervalSince1970: 0))
    //        let b = XLTimeInterval(Date(timeIntervalSince1970: 0))
    //        let expression = a.toTimeInterval() == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(unixepoch('1970-01-01T00:00:00.000Z', 'subsec') == 0.0)")
    //    }
    
    
    // MARK: - UUIDString
    
    
    //    func test_UUIDString() {
    //        let expression = XLUUIDString(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        XCTAssertEqual(encoder.makeSQL(expression), "'00000000-0000-0000-0000-000000000000'")
    //    }
    //
    //
    //    func test_UUIDString_EqualTo_UUIDString() {
    //        let a = XLUUIDString(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        let b = XLUUIDString(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    //        let expression = a == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "('00000000-0000-0000-0000-000000000000' == '00000000-0000-0000-0000-000000000001')")
    //    }
    //
    //
    //    func test_UUIDString_toUUID() {
    //        let a = XLUUIDString(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        let expression = a.toUUID()
    //        XCTAssertEqual(encoder.makeSQL(expression), "uuid_blob('00000000-0000-0000-0000-000000000000')")
    //    }
    //
    //
    //    func test_UUIDString_toUUID_equalTo_UUID() {
    //        let a = XLUUIDString(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        let b = XLUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    //        let expression = a.toUUID() == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(uuid_blob('00000000-0000-0000-0000-000000000000') == x'00000000000000000000000000000001')")
    //    }
    //
    
    // MARK: - UUID
    
    //    func test_UUIDBlob() {
    //        let expression = XLUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        XCTAssertEqual(encoder.makeSQL(expression), "x'00000000000000000000000000000000'")
    //    }
    //
    //
    //    func test_UUIDBlob_EqualTo_UUIDBlob() {
    //        let a = XLUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        let b = XLUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    //        let expression = a == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(x'00000000000000000000000000000000' == x'00000000000000000000000000000001')")
    //    }
    //
    //
    //    func test_UUIDBlob_toUUIDString() {
    //        let a = XLUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        let expression = a.toUUIDString()
    //        XCTAssertEqual(encoder.makeSQL(expression), "uuid_str(x'00000000000000000000000000000000')")
    //    }
    //
    //
    //    func test_UUIDBlob_toUUIDString_equalTo_UUIDString() {
    //        let a = XLUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    //        let b = XLUUIDString(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    //        let expression = a.toUUIDString() == b
    //        XCTAssertEqual(encoder.makeSQL(expression), "(uuid_str(x'00000000000000000000000000000000') == '00000000-0000-0000-0000-000000000001')")
    //    }
    
    
    // MARK: - Scalar functions
    
#warning("TODO: Test all scalar functions")
    
    func testAbsFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.abs()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "ABS(:x)")
    }
    
    func testMinFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = min(x, 12)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "MIN(:x, 12)")
    }
    
    func testMaxFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = max(x, 12)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "MAX(:x, 12)")
    }
    
    func testMinMaxFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = min(max(x, 0), 1)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "MIN(MAX(:x, 0), 1)")
    }
    
    
    // MARK: - Aggregate function
    
#warning("TODO: Test all aggregate functions")
    
    func testAverageFunction() {
        let x = XLNamedBindingReference<Double>(name: "x")
        let expression = x.average()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "AVG(:x)")
    }
    
    //    func testAverageFunctionArithmetic() {
    //        let x = XLNamedBindingReference<Int>(name: "x")
    //        let expression = x.average() * 10
    //        XCTAssertEqual(encoder.makeSQL(expression), "(AVG(t.value) * 10.0)")
    //    }
    
    func testCountFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.count()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "COUNT(:x)")
    }
    
    func testCountDistinctFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.count(distinct: true)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "COUNT(DISTINCT :x)")
    }
    
    //    func testCountFunctionArithmetic() {
    //        let x = XLIntegerColumnReference(table: SQLTableAlias(table: SQLTableReference(name: "MyTable"), as: "t"), name: "value")
    //        let expression = x.count() * 2
    //        XCTAssertEqual(encoder.makeSQL(expression), "(COUNT(t.value) * 2)")
    //    }
    
    
    // MARK: - Select
    
    func testSelect() {
        let expression = sqlQuery { schema in
            let test = schema.table(TestTable.self)
            return select(test).from(test)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0")
    }
    
    func testSelectWhere() {
        let expression = sqlQuery { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t).where(t.value > 0)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value > 0)")
    }
    
    func testSelectWhereAnd() {
        let expression = sqlQuery { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t).where(t.value > 0 && t.value < 1)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.value > 0) AND (t0.value < 1))")
    }
    
    func testSelectWhereInArrayOfText() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.in(["foo", "bar"]))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id IN ('foo', 'bar'))")
    }
    
    func testSelectWhereInArrayOfInteger() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.value.in([9000, 42]))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value IN (9000, 42))")
    }
    
    //    func testSelectColumns() {
    //        let expression = sqlQuery {
    //            let t = from(TestTable.self)
    //            let columns = result {
    //                TestColumns(
    //                    id: $0.column(t.id + t.id),
    //                    value: $0.column(t.value + t.value)
    //                )
    //            }
    //            return select(columns)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t0.id || t0.id AS c0, (t0.value + t0.value) AS c1 FROM Test AS t0")
    //    }
    
    func testSelectJoin() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id)")
    }
    
    func testSelectJoinWhere() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t0.id == "foo")
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) WHERE (t0.id == 'foo')")
    }
    
    func testSelectJoinJoinWhere() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            let t2 = s.table(TestTable.self)
            return select(t2).from(t0).innerJoin(t1, on: t1.id == t0.id ).innerJoin(t2, on: t2.id == t1.id ).where(t0.id == "foo")
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t2.id AS id, t2.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) INNER JOIN Test AS t2 ON (t2.id == t1.id) WHERE (t0.id == 'foo')")
    }
    
    func testSelectOrder() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).orderBy(t.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 ORDER BY t0.id ASC")
    }
    
    func testSelectJoinOrder() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).orderBy(t0.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) ORDER BY t0.id ASC")
    }
    
    func testSelectWhereOrder() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id == "foo").orderBy(t.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id == 'foo') ORDER BY t0.id ASC")
    }
    
    func testSelectJoinWhereOrder() {
        let expression = sqlQuery { s in
            let t0 = s.table(TestTable.self)
            let t1 = s.table(TestTable.self)
            return select(t1).from(t0).innerJoin(t1, on: t1.id == t0.id).where(t0.id == "foo").orderBy(t0.id.ascending())
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t1.id AS id, t1.value AS value FROM Test AS t0 INNER JOIN Test AS t1 ON (t1.id == t0.id) WHERE (t0.id == 'foo') ORDER BY t0.id ASC")
    }
    
    func testSelectLimit() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).limit(10)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 LIMIT 10")
    }
    
    func testSelectLimitOffset() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).limit(10).offset(5)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 LIMIT 10 OFFSET 5")
    }
    
    //    func testSelectGroupBy() {
    //        let expression = sqlQuery {
    //            let t = from(TestTable.self)
    //            let result = result {
    //                TestColumns(
    //                    id: $0.column(t.id),
    //                    value: $0.column(t.value.sum())
    //                )
    //            }
    //            return select(result).groupBy(t.id)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t0.id AS c0, SUM(t0.value) AS c1 FROM Test AS t0 GROUP BY t0.id")
    //    }

    
    // MARK: Factored select (ie WITH common table expression)
    
    
    func testFactoredSelect() {
        let s = XLSchema()
        let foo = s.commonTable { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let t = s.table(foo)
        let expression = with(foo).select(t).from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0")
    }
    
    
    func testNestedFactoredSelect() {
        let s = XLSchema()
        let bar = s.commonTable { s in
            let foo = s.commonTable { s in
                let test = s.table(TestTable.self)
                return select(test).from(test)
            }
            let test = s.table(foo)
            return with(foo).select(test).from(test)
        }
        let t = s.table(bar)
        let expression = with(bar).select(t).from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0) SELECT t0.id AS id, t0.value AS value FROM cte0 AS t0")
    }
    
    
    func testScalarCommonTableExpression() {
        let s = XLSchema()
        let cte = s.commonTable { schema in
            let r = result {
                SQLScalarResult<Int>.SQLReader(
                    scalarValue: 1
                )
            }
            return select(r)
        }
        let t = s.table(cte)
        let expression = with(cte)
            .select(t)
            .from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (SELECT 1 AS scalarValue) SELECT t0.scalarValue AS scalarValue FROM cte0 AS t0")
    }
    
    
    func testScalarResultCommonTableExpression() {
        let s = XLSchema()
        let cte = s.commonTable { schema in
            let r = result {
                SQLScalarResult<Int>.SQLReader(
                    scalarValue: 1
                )
            }
            return select(r)
        }
        let t = s.table(cte)
        let r = result {
            TestTable.SQLReader(
                id: "foo",
                value: t.scalarValue
            )
        }
        let expression = with(cte)
            .select(r)
            .from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "WITH cte0 AS (SELECT 1 AS scalarValue) SELECT 'foo' AS id, t0.scalarValue AS value FROM cte0 AS t0")
    }
    
    
    // MARK: Union
    
    func testUnion() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = result {
            FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
        }
        let dadRow = result {
            FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
        }
        let expression = select(momRow).from(familyMom).union {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    func testUnionAll() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = result {
            FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
        }
        let dadRow = result {
            FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
        }
        let expression = select(momRow).from(familyMom).unionAll {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION ALL SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    func testIntersect() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = result {
            FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
        }
        let dadRow = result {
            FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
        }
        let expression = select(momRow).from(familyMom).intersect {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 INTERSECT SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    func testExcept() {
        let schema = XLSchema()
        let familyMom = schema.table(Family.self)
        let familyDad = schema.table(Family.self)
        let momRow = result {
            FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
        }
        let dadRow = result {
            FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
        }
        let expression = select(momRow).from(familyMom).except {
            select(dadRow).from(familyDad)
        }
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 EXCEPT SELECT t1.name AS name, t1.dad AS parent FROM Family AS t1")
    }
    
    
    // MARK: Recursion
    
    func testScalarRecursiveCommonTableExpression() {
        
        //WITH RECURSIVE
        //  works_for_alice(n) AS (
        //    VALUES('Alice')
        //    UNION
        //    SELECT name FROM org JOIN works_for_alice
        //     WHERE org.boss=works_for_alice.n
        //  )
        //SELECT name FROM org
        // WHERE org.name IN works_for_alice;
        typealias Scalar = SQLScalarResult<String?>
        let schema = XLSchema()
        let cte = schema.recursiveCommonTable(Scalar.self) { schema, this in
            let org = schema.table(Org.self)
            
            let initialResult = result {
                Scalar.SQLReader(scalarValue: "Alice".toNullable())
            }
            return select(initialResult).union {
                select(result { Scalar.SQLReader(scalarValue: org.name) })
                    .from(org)
                    .crossJoin(this)
                    .where(org.boss == this.scalarValue)
            }
        }
        
        let org = schema.table(Org.self)
        let expression = with(cte)
            .select(org.name)
            .from(org)
            .where(
                org.name.in(cte)
            )
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT 'Alice' AS scalarValue UNION SELECT t0.name AS scalarValue FROM Org AS t0 CROSS JOIN cte0 AS t0 WHERE (t0.boss IS t0.scalarValue)) SELECT t1.name FROM Org AS t1 WHERE (t1.name IN cte0)")
    }
    
    
    func testRecursiveCommonTableExpression() {

        //WITH RECURSIVE
        //  parent_of(name, parent) AS
        //    (SELECT name, mom FROM family UNION SELECT name, dad FROM family),
        //  ancestor_of_alice(name) AS
        //    (SELECT parent FROM parent_of WHERE name='Alice'
        //     UNION ALL
        //     SELECT parent FROM parent_of JOIN ancestor_of_alice USING(name))
        //SELECT family.name FROM ancestor_of_alice, family
        // WHERE ancestor_of_alice.name=family.name
        //   AND died IS NULL
        // ORDER BY born;
        typealias Scalar = SQLScalarResult<String?>
        let schema = XLSchema()
        
        let parentOfCommonTable = schema.commonTable { schema in
            let family = schema.table(Family.self)
            let momRow = result {
                FamilyMemberParent.SQLReader(name: family.name, parent: family.mom)
            }
            let dadRow = result {
                FamilyMemberParent.SQLReader(name: family.name, parent: family.dad)
            }
            return select(momRow).from(family).union {
                select(dadRow).from(family)
            }
        }
        
        let ancestorOfAliceCommonTable = schema.recursiveCommonTable(Scalar.self) { schema, this in
            let parentOf = schema.table(parentOfCommonTable)
            return select(result { Scalar.SQLReader(scalarValue: parentOf.parent) })
                .from(parentOf)
                .where(parentOf.name == "Alice".toNullable())
                .unionAll {
                    select(result { Scalar.SQLReader(scalarValue: parentOf.parent) })
                        .from(parentOf)
                        .innerJoin(this, on: this.scalarValue == parentOf.name)
                }
        }
        
        let ancestorOfAlice = schema.table(ancestorOfAliceCommonTable)
        let family = schema.table(Family.self)
        let expression = with(parentOfCommonTable, ancestorOfAliceCommonTable)
            .select(family.name)
            .from(ancestorOfAlice)
            .crossJoin(family)
            .where(ancestorOfAlice.scalarValue == family.name && family.died.isNull())
            .orderBy(family.born.ascending())
        
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t0.name AS name, t0.dad AS parent FROM Family AS t0), cte1 AS (SELECT t0.parent AS scalarValue FROM cte0 AS t0 WHERE (t0.name IS 'Alice') UNION ALL SELECT t0.parent AS scalarValue FROM cte0 AS t0 INNER JOIN cte1 AS t0 ON (t0.scalarValue IS t0.name)) SELECT t2.name FROM cte1 AS t1 CROSS JOIN Family AS t2 WHERE ((t1.scalarValue IS t2.name) AND (julianday(t2.died) ISNULL)) ORDER BY julianday(t2.born) ASC")
    }
    
    
    // MARK: Subquery
    
    
    func testSubquery() {
        let t = subquery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.value > 10)
        }
        let expression = select(t).from(t).where(t.value < 10)
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "SELECT t0.id AS id, t0.value AS value FROM (SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.value > 10)) AS t0 WHERE (t0.value < 10)"
        )
    }
    
    
    // MARK: - Scalar subquery
    
    func testScalarSelectConstant() {
        let expression = select(1)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT 1")
    }
    
    func testScalarSelect() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t.id).from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id FROM Test AS t0")
    }
    
    func testSelectSubqueryAggregate() {
        let s = XLSchema()
        let t = s.table(TestTable.self)
        let r = result {
            TestColumns.SQLReader(
                id: t.id,
                value: subquery {
                    let t = s.table(TestTable.self)
                    return select(t.value.sum()).from(t)
                }
            )
        }
        let expression = select(r).from(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, (SELECT SUM(t1.value) FROM Test AS t1) AS value FROM Test AS t0")
    }
    
    func testScalarSelectWhereIn() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t)
            .from(t)
            .where(
                t.id.in {
                    select(t.id).from(t)
                }
            )
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id IN (SELECT t0.id FROM Test AS t0))")
    }
    
    
    // MARK: - Variable parameter bindings
    
    
    func testVariableBinding() {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t).from(t).where(t.id == idParameter)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id == :id)")
    }
    
    
    //    func testScalarSelectWhere() {
    //        let expression = sqlQuery { db in
    //            let t = db.from(Test.self, as: "t")
    //            Where { t.value > 0 }
    //            SelectColumn(t.id)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t.id AS c0 FROM Test AS t WHERE (t.value > 0)")
    //    }
    
    //    func testScalarSelectWhere_ReferenceSelect() {
    //        let expression = sqlQuery { db in
    //            let t = db.from(Test.self, as: "t")
    //            Where { t.id == "foo" }
    //            SelectColumn(column)
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t.id AS c0 FROM Test AS t WHERE (c0 == 'foo')")
    //    }
    
    
    //    func testSelectColumnExpressionWhere() {
    //        let expression = sqlQuery { db in
    //            let test = db.from(Test.self, as: "test")
    //            let columns = db.columns { row in
    //                Result(
    //                    id: row { test.id },
    //                    value: row { test.value * 2 }
    //                )
    //            }
    //            Select(columns)
    //            Where { columns.value > 2 }
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT test.id AS c0, (test.value * 2) AS c1 FROM Test AS test")
    //    }
    
    //    func testSelectAverage() {
    //        let expression = sqlQuery { db in
    //            let t = db.from(Test.self, as: "t")
    //            #warning("TODO: Error or warning when using aggregate without group by")
    ////            Group(by: t.id)
    //            Select { columns in
    //                TestResult(
    //                    id: columns { t.id },
    //                    total: columns { Sum(t.value) }
    //                )
    //            }
    //        }
    //        XCTAssertEqual(encoder.makeSQL(expression), "SELECT t.id AS c0, SUM(t.value) AS c1 FROM Test AS t")
    //    }
    
    
    // MARK: - Insert
    
    func testInsertDiscreteParameters() {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        let valueParameter = XLNamedBindingReference<Int>(name: "value")
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t).values(
            TestTable.MetaInsert(
                id: idParameter,
                value: valueParameter
            )
        )
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "INSERT INTO Test AS t0 (id,value) VALUES (:id,:value)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testInsertInstanceParameter() {
        let instance = TestTable(id: "foo", value: 42)
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t).values(TestTable.MetaInsert(instance))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testInsertImplicitInstanceParameter() {
        let instance = TestTable(id: "foo", value: 42)
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = insert(t).values(instance)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "INSERT INTO Test AS t0 (id,value) VALUES ('foo',42)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testInsertSelect() {
        let schema = XLSchema()
        let t = schema.table(Temp.self)
        let e = schema.table(EmployeeTable.self)
        let r = result {
            Temp.SQLReader(
                id: e.id,
                value: e.name
            )
        }
        let expression = insert(t).select(r).from(e)
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM Employee AS t1")
        XCTAssertTrue(finalResult.entities.contains("Temp"))
    }
    
    func testInsertSelectWithCommonTableExpression() {
        let schema = XLSchema()
        let cte = schema.commonTable { schema in
            let t = schema.table(CompanyTable.self)
            return select(t).from(t)
        }
        let t = schema.table(Temp.self)
        let e = schema.table(cte)
        let r = result {
            Temp.SQLReader(
                id: e.id,
                value: e.name
            )
        }
        let expression = with(cte).insert(t).select(r).from(e)
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM cte0 AS t1")
        XCTAssertTrue(finalResult.entities.contains("Temp"))
    }
    
    
    // MARK: - Update
    
    func testUpdate() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = update(t, set: TestTable.MetaUpdate(
            value: t.value + 1
        ))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Test AS t0 SET value = (t0.value + 1)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testUpdateDecimal() {
        let schema = XLSchema()
        let t = schema.into(DoubleTest.self)
        let expression = update(t, set: DoubleTest.MetaUpdate(
            value: 1234.56
        ))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE DoubleTest AS t0 SET value = 1234.56")
        XCTAssertTrue(result.entities.contains("DoubleTest"))
    }
    
    func testUpdateFractional() {
        let schema = XLSchema()
        let t = schema.into(DoubleTest.self)
        let expression = update(t, set: DoubleTest.MetaUpdate(
            value: 0.56
        ))
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE DoubleTest AS t0 SET value = 0.56")
        XCTAssertTrue(result.entities.contains("DoubleTest"))
    }
    
    func testUpdateWhere() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = update(t) 
            .set { row in
                row.value = t.value + 1
            }
            .where(t.id == "foo")
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Test AS t0 SET value = (t0.value + 1) WHERE (t0.id == 'foo')")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testUpdateFrom() {
        let schema = XLSchema()
        let t = schema.into(Temp.self)
        let s = schema.from { schema in
            let t = schema.table(CompanyTable.self)
            return select(t).from(t)
        }
        let expression = update(t)
            .set { row in
                row.value = t.value + " " + s.name
            }
            .from(s)
            .where(t.id == s.id)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "UPDATE Temp AS t0 SET value = t0.value || ' ' || t1.name FROM (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) AS t1 WHERE (t0.id == t1.id)")
        XCTAssertTrue(result.entities.contains("Temp"))
    }
    
    
    // MARK: - Create
    
    func testCreateTable() {
        let schema = XLSchema()
        let t = schema.create(TestTable.self)
        let expression = create(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Test (id NOT NULL, value NOT NULL)")
    }
    
    func testCreateNullablesTable() {
        let schema = XLSchema()
        let t = schema.create(TestNullablesTable.self)
        let expression = create(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS TestNullables (id NOT NULL, value)")
    }
    
    func testCreateGenericValueTable() {
        let schema = XLSchema()
        let t = schema.create(GenericTable<String>.self)
        let expression = create(t)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Generic (id NOT NULL, value NOT NULL)")
    }
    
    
    // MARK: Create ... Select
    
    func testCreateTableUsingSelect() {
        
        let schema = XLSchema()
        let t = schema.create(Temp.self)
        let expression = create(t).as { schema in
            let t = schema.table(EmployeeTable.self)
            let r = result {
                Temp.SQLReader(
                    id: t.id,
                    value: t.name
                )
            }
            return select(r).from(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Temp AS SELECT t0.id AS id, t0.name AS value FROM Employee AS t0")
    }
    
    func testCreateTableUsingSelectWithCommonTable() {
        
        let schema = XLSchema()
        let t = schema.create(Temp.self)
        let expression = create(t).as { schema in
            
            let cte = schema.commonTable { schema in
                let t = schema.table(EmployeeTable.self)
                return select(t).from(t)
            }
            
            let t = schema.table(cte)
            let r = result {
                Temp.SQLReader(
                    id: t.id,
                    value: t.name
                )
            }
            return with(cte).select(r).from(t)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Temp AS WITH cte0 AS (SELECT t0.id AS id, t0.name AS name, t0.companyId AS companyId, t0.managerEmployeeId AS managerEmployeeId FROM Employee AS t0) SELECT t0.id AS id, t0.name AS value FROM cte0 AS t0")
    }
    
    
    // MARK: - Delete
    
    func testDelete() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = delete(t)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "DELETE FROM Test AS t0")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testDeleteWhere() {
        let schema = XLSchema()
        let t = schema.into(TestTable.self)
        let expression = delete(t).where(t.value == 42)
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "DELETE FROM Test AS t0 WHERE (t0.value == 42)")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testDeleteWithCommonTableExpression() {
        let schema = XLSchema()
        let cte = schema.commonTable { schema in
            let t = schema.table(TestTable.self)
            return select(t).from(t)
        }
        let t0 = schema.table(cte)
        let t1 = schema.into(TestTable.self)
        let expression = with(cte)
            .delete(t1)
            .where(
                t1.id.in {
                    select(t0.id).from(t0)
                }
            )
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "WITH cte0 AS (SELECT t0.id AS id, t0.value AS value FROM Test AS t0) DELETE FROM Test AS t1 WHERE (t1.id IN (SELECT t0.id FROM cte0 AS t0))")
        XCTAssertTrue(result.entities.contains("Test"))
    }
    
    func testDeleteWithSubquery() {
        let schema = XLSchema()
        let t0 = schema.into(TestTable.self)
        let expression = delete(t0)
            .where(
                t0.id.in {
                    let t1 = schema.table(TestTable.self)
                    return select(t1.id).from(t1)
                }
            )
        let result = encoder.makeSQL(expression)
        XCTAssertEqual(result.sql, "DELETE FROM Test AS t0 WHERE (t0.id IN (SELECT t1.id FROM Test AS t1))")
        XCTAssertTrue(result.entities.contains("Test"))
    }
}
