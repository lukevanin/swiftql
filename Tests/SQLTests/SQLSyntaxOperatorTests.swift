//
//  SQLSyntaxOperatorTests.swift
//
//  Rendering of unary and binary operators, over integers, booleans, text, and
//  nullable operands.
//
//  Split from SQLSyntaxTests.swift (issue #567).
//

import XCTest
import SwiftQL


final class XLSyntaxOperatorTests: XLSyntaxTestCase {

    // MARK: - Integer unary opperator
    
    
    func testPlusOperator_IntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = +x
        assertRenders(expression, as: "+(:x)")
    }
    
    
    func testNegateOperator_IntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = -x
        assertRenders(expression, as: "-(:x)")
    }
    
    
    func testBitwiseNotOperator_IntegerBindingExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = ~x
        assertRenders(expression, as: "~(:x)")
    }


    func testBitwiseNotOperator_IntegerLiteralExpression() {
        let operand: any XLExpression<Int> = 12
        let expression = ~operand
        assertRenders(expression, as: "~(12)")
    }


    func testBitwiseNotOperator_IntegerColumnExpression() {
        let table = XLSchema().table(TestTable.self, as: "sample")
        let expression = ~table.value
        assertRenders(expression, as: "~(sample.value)")
    }


    func testBitwiseNotOperator_ComposedIntegerExpression() {
        let a = XLNamedBindingReference<Int>(name: "a")
        let b = XLNamedBindingReference<Int>(name: "b")
        let expression = ~(a + b)
        assertRenders(expression, as: "~((:a + :b))")
    }


    func testBitwiseNotOperator_OptionalIntegerExpression() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = ~x
        assertRenders(expression, as: "~(:x)")
    }


    func testNegateOperator_NestedIntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = -(-x)
        let sql = encoder.makeSQL(expression).sql
        XCTAssertEqual(sql, "-(-(:x))")
        XCTAssertFalse(sql.contains("--"))
    }


    func testNegateOperator_CompoundIntegerExpression() {
        let a = XLNamedBindingReference<Int>(name: "a")
        let b = XLNamedBindingReference<Int>(name: "b")
        let expression = -(a + b)
        assertRenders(expression, as: "-((:a + :b))")
    }
    
    
    // MARK: - Integer binary operator
    
    
    func test_IntegerReference_Plus_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x + y
        assertRenders(expression, as: "(:x + :y)")
    }
    
    
    func test_IntegerReference_Minus_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x - y
        assertRenders(expression, as: "(:x - :y)")
    }
    
    
    func test_IntegerReference_Plus_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x + 7
        assertRenders(expression, as: "(:x + 7)")
    }
    
    
    func test_IntegerReference_Minus_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x - 7
        assertRenders(expression, as: "(:x - 7)")
    }
    
    
    func test_Integer_Plus_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = 7 + x
        assertRenders(expression, as: "(7 + :x)")
    }
    
    
    // MARK: - Optional integer binary operator
    
    
    func test_OptionalIntegerReference_Plus_OptionalIntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x + y
        assertRenders(expression, as: "(:x + :y)")
    }
    
    
    func test_OptionalIntegerReference_Plus_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x + 7
        assertRenders(expression, as: "(:x + 7)")
    }
    
    func test_Integer_Plus_OptionalIntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = 7 + x
        assertRenders(expression, as: "(7 + :x)")
    }
    
    
    func test_OptionalIntegerReference_Plus_IntegerReference() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        let expression = x + y
        assertRenders(expression, as: "(:x + :y)")
    }
    
    
    func test_IntegerReference_Plus_OptionalIntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Optional<Int>>(name: "y")
        let expression = x + y
        assertRenders(expression, as: "(:x + :y)")
    }
    
    
    func test_IntegerReference_MultipliedBy_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        assertRenders(x * y, as: "(:x * :y)")
    }


    func test_IntegerReference_DividedBy_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        assertRenders(x / y, as: "(:x / :y)")
    }


    func test_IntegerReference_Remainder_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        assertRenders(x % y, as: "(:x % :y)")
    }
    
    
    // MARK: - Unary boolean
    
    
    func test_Not_BooleanReference() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let expression = !x
        assertRenders(expression, as: "(NOT :x)")
    }
    
    
    // MARK: - Integer operators
    
    func test_TextBindingReference_EqualTo_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x == 12
        assertRenders(expression, as: "(:x == 12)")
    }
    
    func test_IntegerBindingReference_GreaterThan_Integer() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x > 7
        assertRenders(expression, as: "(:x > 7)")
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
        assertRenders(expression, as: "(:x AND :y)")
    }
    
    func testOrBinaryBooleanOperator_BooleanExpression() {
        let x = XLNamedBindingReference<Bool>(name: "x")
        let y = XLNamedBindingReference<Bool>(name: "y")
        let expression = x || y
        assertRenders(expression, as: "(:x OR :y)")
    }
    
    func testAndBinaryBooleanOperator_NumericExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = (x > 7) && (x < 12)
        assertRenders(expression, as: "((:x > 7) AND (:x < 12))")
    }
    
    func testOrBinaryBooleanOperator_NumericExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = (x > 7) || (x == 12)
        assertRenders(expression, as: "((:x > 7) OR (:x == 12))")
    }
    
    
    // MARK: - Text operators
    
    
    func test_TextBindingReference_EqualTo_String() {
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x == "foo"
        assertRenders(expression, as: "(:x == 'foo')")
    }
    
    
    func test_TextBindingReference_Plus_String() {
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x + "foo"
        assertRenders(expression, as: "(:x || 'foo')")
    }
    
    
    // MARK: - Null
    
    
    func testIsNull_OptionalNumericExpression() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x.isNull()
        assertRenders(expression, as: "(:x ISNULL)")
    }
    
    func testIsNotNull_OptionalNumericExpression() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x.notNull()
        assertRenders(expression, as: "(:x NOTNULL)")
    }
    
    
    func testIsNull_OptionalTextExpression() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.isNull()
        assertRenders(expression, as: "(:x ISNULL)")
    }
    
    func testIsNotNull_OptionalTextExpression() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.notNull()
        assertRenders(expression, as: "(:x NOTNULL)")
    }
    
    
    // MARK: - Null coalesce
    
    
    func test_OptionalIntegerBinding_Coalesce_Integer() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x.coalesce(7)
        assertRenders(expression, as: "COALESCE(:x, 7)")
    }
    
    
    func test_OptionalIntegerBinding_CoalescingOperator_Integer() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = x ?? 7
        assertRenders(expression, as: "COALESCE(:x, 7)")
    }


    /// Issue #7: chaining two optional fallbacks composes by nesting one
    /// `coalesce`/`??` inside another, rather than needing a dedicated
    /// optional-rhs overload — `x.coalesce(y.coalesce(7))` and its `??`
    /// equivalent both render as SQLite's own variadic `COALESCE`.
    func test_TwoOptionalIntegerBindings_Coalesce_Integer() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let y = XLNamedBindingReference<Optional<Int>>(name: "y")
        let expression = x.coalesce(y.coalesce(7))
        assertRenders(expression, as: "COALESCE(:x, COALESCE(:y, 7))")
    }


    func test_TwoOptionalIntegerBindings_CoalescingOperator_Integer() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let y = XLNamedBindingReference<Optional<Int>>(name: "y")
        // `??` is right-associative, so this parses as `x ?? (y ?? 7)`.
        let expression = x ?? y ?? 7
        assertRenders(expression, as: "COALESCE(:x, COALESCE(:y, 7))")
    }
}
