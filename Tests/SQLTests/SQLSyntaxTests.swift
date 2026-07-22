//
//  SQLSyntaxTests.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import XCTest
import SwiftQL


private struct RawRealRenderingProbe: XLEncodable {
    let value: Double

    func makeSQL(context: inout XLBuilder) {
        context.real(value)
    }
}


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


    func test_IntegerLiteral_Int64Max() {
        let expression: Int = Int(Int64.max)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "9223372036854775807")
    }


    func test_IntegerLiteral_Int64Min() {
        let expression: Int = Int(Int64.min)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "-9223372036854775808")
    }


    func test_IntegerLiteral_MillisecondEpochTimestamp() {
        let expression: Int = 1_752_000_000_000
        XCTAssertEqual(encoder.makeSQL(expression).sql, "1752000000000")
    }

    
    func test_RealLiteral() {
        let expression: Double = 17.4
        XCTAssertEqual(encoder.makeSQL(expression).sql, "17.4")
    }


    func test_NonFiniteRealLiteralsFailWithoutRenderingBareTokens() {
        let cases: [(Double, XLNonFiniteRealValue)] = [
            (.nan, .notANumber),
            (.infinity, .positiveInfinity),
            (-.infinity, .negativeInfinity),
        ]

        for (value, classified) in cases {
            let encoding = encoder.makeSQL(value)
            let loweredSQL = encoding.sql.lowercased()

            XCTAssertFalse(loweredSQL.contains("nan"))
            XCTAssertFalse(loweredSQL.contains("inf"))
            XCTAssertEqual(
                encoding.valueEncodingError,
                .nonFiniteRealLiteral(
                    value: classified,
                    expressionType: String(reflecting: Double.self)
                )
            )
            XCTAssertThrowsError(try encoder.makeValidatedSQL(value)) { error in
                XCTAssertEqual(
                    error as? XLSQLValueEncodingError,
                    encoding.valueEncodingError
                )
            }
            XCTAssertThrowsError(
                try XLStaticStatementDefinition(validating: encoding)
            ) { error in
                XCTAssertEqual(
                    error as? XLSQLValueEncodingError,
                    encoding.valueEncodingError
                )
            }
        }
    }


    func test_FormatterNeverReturnsInvalidNonFiniteRealTokens() {
        let formatter = XLiteFormatter()
        for value in [Double.nan, .infinity, -.infinity] {
            let token = formatter.real(value).lowercased()
            XCTAssertFalse(token.contains("nan"))
            XCTAssertFalse(token.contains("inf"))
        }
    }


    func test_BuilderRejectsNonFiniteRealFromCustomExpression() {
        XCTAssertThrowsError(
            try encoder.makeValidatedSQL(
                RawRealRenderingProbe(value: .infinity)
            )
        ) { error in
            XCTAssertEqual(
                error as? XLSQLValueEncodingError,
                .nonFiniteRealLiteral(
                    value: .positiveInfinity,
                    expressionType: String(reflecting: Double.self)
                )
            )
        }
    }


    func test_FiniteRealEdgeLiteralsRemainRenderable() throws {
        for value in [
            Double.greatestFiniteMagnitude,
            -Double.greatestFiniteMagnitude,
            Double.leastNonzeroMagnitude,
            -Double.leastNonzeroMagnitude,
            -0.0,
        ] {
            let encoding = try encoder.makeValidatedSQL(value)
            XCTAssertNil(encoding.valueEncodingError)
            XCTAssertFalse(encoding.sql.isEmpty)
        }
    }
    
    
    func test_TextLiteral() {
        let expression: String = "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "'foo'")
    }


    func test_TextLiteral_EscapesSingleQuote() {
        let expression: String = "O'Brien"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "'O''Brien'")
    }


    func test_TextLiteral_EscapesInjectionAttempt() {
        let expression: String = "x' OR '1'='1"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "'x'' OR ''1''=''1'")
    }


    func test_TextLiteral_PreservesCommentSequence() {
        let expression: String = "a--b"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "'a--b'")
    }


    func test_TextLiteral_EmptyString() {
        let expression: String = ""
        XCTAssertEqual(encoder.makeSQL(expression).sql, "''")
    }


    func test_TextLiteral_EmbeddedNulCharacter() {
        // A NUL cannot be escaped inside a SQL string literal. Verify the
        // quotes remain balanced so the value cannot break out of the literal.
        let expression: String = "a\0b"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "'a\0b'")
    }


    func test_TextLiteral_StaticString_EscapesSingleQuote() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .noEscape)
        let literal: StaticString = "O'Brien"
        XCTAssertEqual(formatter.text(literal), "'O''Brien'")
    }
    
    
    func test_BlobLiteral() {
        let expression: Data = Data([0x01])
        XCTAssertEqual(encoder.makeSQL(expression).sql, "x'01'")
    }


    // MARK: - Type cast


    func test_Text_ToData_CastsToBlob() {
        let expression = "abc".toData()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CAST('abc' AS BLOB)")
    }


    func test_OptionalTextReference_ToData_CastsToBlob() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.toData()
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CAST(:x AS BLOB)")
    }



    // MARK: - Column reference
    
    
    func test_ColumnReference() {
        let table = XLSchema().table(TestTable.self, as: "sample")
        XCTAssertEqual(encoder.makeSQL(table.value).sql, "sample.value")
    }


    func test_SQLResultColumns_AreAvailableAcrossFilesOnSwift59() {
        let row = Swift59ColumnsLookupProjection.columns(value: 1)
        XCTAssertEqual(encoder.makeSQL(select(row)).sql, "SELECT 1 AS value")
    }
    
    
    // MARK: - Function
    
    
    func test_Function() {
        let parameter = XLNamedBindingReference<Int>(name: "value")
        let function = XLFunction<Int>(
            name: "CUSTOM",
            distinct: true,
            parameters: [parameter, 1]
        )
        XCTAssertEqual(encoder.makeSQL(function).sql, "CUSTOM(DISTINCT :value, 1)")
    }
    
    
    // MARK: - Bind parameter
    
    
    func test_SchemaBinding_UsesRequestedName() {
        let binding = XLSchema().binding(of: Int.self, as: "value")
        XCTAssertEqual(encoder.makeSQL(binding).sql, ":value")
    }
    
    
    // MARK: - Integer unary opperator
    
    
    func testPlusOperator_IntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = +x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "+(:x)")
    }
    
    
    func testNegateOperator_IntegerExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = -x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "-(:x)")
    }
    
    
    func testBitwiseNotOperator_IntegerBindingExpression() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = ~x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "~(:x)")
    }


    func testBitwiseNotOperator_IntegerLiteralExpression() {
        let operand: any XLExpression<Int> = 12
        let expression = ~operand
        XCTAssertEqual(encoder.makeSQL(expression).sql, "~(12)")
    }


    func testBitwiseNotOperator_IntegerColumnExpression() {
        let table = XLSchema().table(TestTable.self, as: "sample")
        let expression = ~table.value
        XCTAssertEqual(encoder.makeSQL(expression).sql, "~(sample.value)")
    }


    func testBitwiseNotOperator_ComposedIntegerExpression() {
        let a = XLNamedBindingReference<Int>(name: "a")
        let b = XLNamedBindingReference<Int>(name: "b")
        let expression = ~(a + b)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "~((:a + :b))")
    }


    func testBitwiseNotOperator_OptionalIntegerExpression() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        let expression = ~x
        XCTAssertEqual(encoder.makeSQL(expression).sql, "~(:x)")
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
        XCTAssertEqual(encoder.makeSQL(expression).sql, "-((:a + :b))")
    }
    
    
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
    
    
    func test_IntegerReference_MultipliedBy_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        XCTAssertEqual(encoder.makeSQL(x * y).sql, "(:x * :y)")
    }


    func test_IntegerReference_DividedBy_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        XCTAssertEqual(encoder.makeSQL(x / y).sql, "(:x / :y)")
    }


    func test_IntegerReference_Remainder_IntegerReference() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let y = XLNamedBindingReference<Int>(name: "y")
        XCTAssertEqual(encoder.makeSQL(x % y).sql, "(:x % :y)")
    }
    
    
    // MARK: - Unary boolean
    
    
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
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x || 'foo')")
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
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x || 'foo')")
    }
    
    func test_TextBinding_Plus_TextBinding() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x || :y)")
    }
    
    func test_TextBinding_Plus_String_Plus_TextBinding() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + "foo" + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "((:x || 'foo') || :y)")
    }
    
    func test_OptionalTextBinding_Plus_Text() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x + "foo"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x || 'foo')")
    }

    func test_TextConcatenation_NestedOnLeftOfEquality() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = (x + y) == "foobar"
        XCTAssertEqual(encoder.makeSQL(expression).sql, "((:x || :y) == 'foobar')")
    }

    func test_TextConcatenation_NestedOnRightOfEquality() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = "foobar" == (x + y)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "('foobar' == (:x || :y))")
    }

    func test_TextConcatenation_CollatesCompleteResult() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = (x + y).collate(.nocase)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "((:x || :y) COLLATE NOCASE)")
    }

    func test_TextConcatenation_PreservesCollatedLeftOperandGrouping() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x.collate(.nocase) + y
        XCTAssertEqual(encoder.makeSQL(expression).sql, "((:x COLLATE NOCASE) || :y)")
    }

    func test_TextConcatenation_PreservesCollatedOperandGrouping() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + y.collate(.nocase)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(:x || (:y COLLATE NOCASE))")
    }
    
    
    // MARK: - Between


    func testBetweenOperatorSupportsLiteralBounds() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let expression = value.isBetween(7, 12)
        let _: any XLExpression<Bool> = expression

        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "(:value BETWEEN 7 AND 12)"
        )
    }


    func testNotBetweenOperatorSupportsBindingBounds() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let minimum = XLNamedBindingReference<Int>(name: "minimum")
        let maximum = XLNamedBindingReference<Int>(name: "maximum")
        let expression = value.isNotBetween(minimum, maximum)
        let _: any XLExpression<Bool> = expression

        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "(:value NOT BETWEEN :minimum AND :maximum)"
        )
    }


    func testBetweenOperatorPreservesNestedBooleanAndComparisonPrecedence() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let other = XLNamedBindingReference<Int>(name: "other")
        let expression = value.isBetween(7, 12) && other > 0

        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "((:value BETWEEN 7 AND 12) AND (:other > 0))"
        )
        XCTAssertEqual(
            encoder.makeSQL(value.isBetween(7, 12) == true).sql,
            "((:value BETWEEN 7 AND 12) == 1)"
        )
    }


    func testBetweenOperatorPreservesNullableResultType() {
        let value = XLNamedBindingReference<Optional<Int>>(name: "value")
        let expression = value.isBetween(7, 12)
        let _: any XLExpression<Optional<Bool>> = expression

        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "(:value BETWEEN 7 AND 12)"
        )
    }
    
    
    // MARK: -  Case expression
    
    
    func test_SimpleCaseWhenThen_StringResult() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let expression = switchCase(value).when(1, then: "one")
        let _: any XLExpression<String?> = expression
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "(CASE :value WHEN 1 THEN 'one' END)"
        )
    }


    func test_SimpleCaseWhenThenElse_StringResult() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let expression = switchCase(value)
            .when(1, then: "one")
            .when(2, then: "two")
            .else("other")
        let _: any XLExpression<String> = expression
        XCTAssertEqual(
            encoder.makeSQL(expression).sql,
            "(CASE :value WHEN 1 THEN 'one' WHEN 2 THEN 'two' ELSE 'other' END)"
        )
    }
    
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


    func test_SearchedCaseWhenThen_IntegerResult() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = when(x == 12, then: 42)
        // A searched CASE without an ELSE evaluates to NULL when no condition
        // matches, so the expression type is the optional of the result type.
        let _: any XLExpression<Int?> = expression
        XCTAssertTrue(VariableCaseWhenThen<Int>.T.self == Int?.self)
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(CASE WHEN (:x == 12) THEN 42 END)")
    }


    func test_SearchedCaseWhenThenElse_IntegerResult() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = when(x == 12, then: 42).else(7)
        let _: any XLExpression<Int> = expression
        XCTAssertEqual(encoder.makeSQL(expression).sql, "(CASE WHEN (:x == 12) THEN 42 ELSE 7 END)")
    }

    
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
    
    func testAverageFunction() {
        let x = XLNamedBindingReference<Double>(name: "x")
        let expression = x.averageOrNull()
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


    func testGroupConcatFunction() {
        let expression = sqlQuery { schema in
            let company = schema.table(CompanyTable.self)
            return select(company.name.groupConcatOrNull()).from(company)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT GROUP_CONCAT(t0.name) FROM Company AS t0")
    }


    func testGroupConcatDistinctFunction() {
        let expression = sqlQuery { schema in
            let company = schema.table(CompanyTable.self)
            return select(company.name.groupConcatOrNull(distinct: true)).from(company)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT GROUP_CONCAT(DISTINCT t0.name) FROM Company AS t0")
    }


    func testGroupConcatSeparatorFunction() {
        let expression = sqlQuery { schema in
            let company = schema.table(CompanyTable.self)
            return select(company.name.groupConcatOrNull(separator: "|")).from(company)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT GROUP_CONCAT(t0.name, '|') FROM Company AS t0")
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
    
    func testSelectWhereNotInArrayOfText() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.notIn(["foo", "bar"]))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id NOT IN ('foo', 'bar'))")
    }

    func testSelectWhereInArrayContainingNull() {
        let expression = sqlQuery { s in
            let t = s.table(TestNullablesTable.self)
            return select(t).from(t).where(
                t.value.in([1, Optional<Int>.none])
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM TestNullables AS t0 WHERE (t0.value IN (1, NULL))")
    }

    func testSelectWhereNotInArrayContainingNull() {
        let expression = sqlQuery { s in
            let t = s.table(TestNullablesTable.self)
            return select(t).from(t).where(
                t.value.notIn([1, Optional<Int>.none])
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM TestNullables AS t0 WHERE (t0.value NOT IN (1, NULL))")
    }

    func testSelectWhereNotInEmptyArray() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.notIn([]))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id NOT IN ())")
    }

    func testScalarSelectWhereNotInSubquery() {
        let schema = XLSchema()
        let t = schema.table(TestTable.self)
        let expression = select(t)
            .from(t)
            .where(
                t.id.notIn {
                    select(t.id).from(t)
                }
            )
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id NOT IN (SELECT t0.id FROM Test AS t0))")
    }

    /// The negation belongs to the IN operator itself, not to a wrapping NOT,
    /// so it must not migrate outwards when the predicate is combined.
    func testSelectWhereNotInComposesWithoutMovingTheNegation() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(
                t.id.notIn(["foo"]) && t.id.in(["bar"])
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.id NOT IN ('foo')) AND (t0.id IN ('bar')))")
    }

    func testSelectWhereLikeWithEscape() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(t.id.like("100\\%", escape: "\\"))
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE (t0.id LIKE '100\\%' ESCAPE '\\')")
    }

    /// ESCAPE belongs to its own LIKE, so a second LIKE in the same predicate
    /// must not absorb it.
    func testSelectWhereLikeWithEscapeBindsToItsOwnLike() {
        let expression = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t).where(
                t.id.like("100\\%", escape: "\\") && t.id.like("b%")
            )
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t0.id AS id, t0.value AS value FROM Test AS t0 WHERE ((t0.id LIKE '100\\%' ESCAPE '\\') AND (t0.id LIKE 'b%'))")
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


    func testSelectJoinSkipsExplicitAliases() {
        let expression = sqlQuery { schema in
            let explicit0 = schema.table(TestTable.self, as: "T0")
            let explicit1 = schema.table(TestTable.self, as: "t1")
            let automatic = schema.table(TestTable.self)
            return select(automatic)
                .from(automatic)
                .innerJoin(explicit0, on: automatic.id == explicit0.id)
                .innerJoin(explicit1, on: automatic.id == explicit1.id)
        }
        XCTAssertEqual(encoder.makeSQL(expression).sql, "SELECT t2.id AS id, t2.value AS value FROM Test AS t2 INNER JOIN Test AS T0 ON (t2.id == T0.id) INNER JOIN Test AS t1 ON (t2.id == t1.id)")
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
            let r = SQLScalarResult<Int>.columns(scalarValue: 1)
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
            let r = SQLScalarResult<Int>.columns(scalarValue: 1)
            return select(r)
        }
        let t = s.table(cte)
        let r = TestTable.columns(id: "foo", value: t.scalarValue)
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
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
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
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
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
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
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
        let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)
        let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)
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
            
            let initialResult = Scalar.columns(scalarValue: "Alice".toNullable())
            return select(initialResult).union {
                select(Scalar.columns(scalarValue: org.name))
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
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT 'Alice' AS scalarValue UNION SELECT t1.name AS scalarValue FROM Org AS t1 CROSS JOIN cte0 AS t0 WHERE (t1.boss IS t0.scalarValue)) SELECT t0.name FROM Org AS t0 WHERE (t0.name IN cte0)")
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
            let momRow = FamilyMemberParent.columns(name: family.name, parent: family.mom)
            let dadRow = FamilyMemberParent.columns(name: family.name, parent: family.dad)
            return select(momRow).from(family).union {
                select(dadRow).from(family)
            }
        }
        
        let ancestorOfAliceCommonTable = schema.recursiveCommonTable(Scalar.self) { schema, this in
            let parentOf = schema.table(parentOfCommonTable)
            return select(Scalar.columns(scalarValue: parentOf.parent))
                .from(parentOf)
                .where(parentOf.name == "Alice".toNullable())
                .unionAll {
                    select(Scalar.columns(scalarValue: parentOf.parent))
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
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.name AS name, t0.mom AS parent FROM Family AS t0 UNION SELECT t0.name AS name, t0.dad AS parent FROM Family AS t0), cte1 AS (SELECT t1.parent AS scalarValue FROM cte0 AS t1 WHERE (t1.name IS 'Alice') UNION ALL SELECT t1.parent AS scalarValue FROM cte0 AS t1 INNER JOIN cte1 AS t0 ON (t0.scalarValue IS t1.name)) SELECT t1.name FROM cte1 AS t0 CROSS JOIN Family AS t1 WHERE ((t0.scalarValue IS t1.name) AND (julianday(t1.died) ISNULL)) ORDER BY julianday(t1.born) ASC")
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
        let r = TestColumns.columns(
            id: t.id,
            value: XLTypeAffinityExpression<Int?>(
                expression: subquery {
                    let t = s.table(TestTable.self)
                    return select(t.value.sumOrNull()).from(t)
                }
            )
        )
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
        let r = Temp.columns(id: e.id, value: e.name)
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
        let r = Temp.columns(id: e.id, value: e.name)
        let expression = with(cte).insert(t).select(r).from(e)
        let finalResult = encoder.makeSQL(expression)
        XCTAssertEqual(finalResult.sql, "WITH cte0 AS (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM cte0 AS t1")
        XCTAssertTrue(finalResult.entities.contains("Temp"))
    }

    func testInsertSelectFluentRemainingTransitions() {
        let schema = XLSchema()
        let temp = schema.table(Temp.self)
        let company = schema.table(CompanyTable.self)
        let employeeTable = schema.table(EmployeeTable.self)
        // Insert-select joins accept unnamed result metadata. Reuse the named
        // table dependency so every join keeps the deterministic t2 alias.
        let employee = EmployeeTable.makeSQLTable(
            namespace: employeeTable._namespace,
            dependency: employeeTable._dependency
        )
        let nullableEmployee = EmployeeTable.makeSQLNullableResult(
            namespace: employeeTable._namespace,
            dependency: employeeTable._dependency
        )
        let row = Temp.columns(id: company.id, value: company.name)
        let from = insert(temp).select(row).from(company)
        let filtered = from.where(company.name != "skip")
        let grouped = from.groupBy(company.id, company.name)
        let having = grouped.having(company.id.count() >= 1)
        let baseSQL = "INSERT INTO Temp AS t0 SELECT t1.id AS id, t1.name AS value FROM Company AS t1"
        let cases: [(String, any XLEncodable, String)] = [
            (
                "FROM to bare INNER JOIN",
                from.innerJoin(employee),
                " INNER JOIN Employee AS t2"
            ),
            (
                "FROM to CROSS JOIN",
                from.crossJoin(employee),
                " CROSS JOIN Employee AS t2"
            ),
            (
                "FROM to nullable LEFT JOIN",
                from.leftJoin(
                    nullableEmployee,
                    on: nullableEmployee.companyId == company.id
                ),
                " LEFT JOIN Employee AS t2 ON (t2.companyId IS t1.id)"
            ),
            (
                "FROM to GROUP BY",
                from.groupBy(company.id, company.name),
                " GROUP BY t1.id, t1.name"
            ),
            (
                "FROM to ORDER BY",
                from.orderBy(company.name.ascending()),
                " ORDER BY t1.name ASC"
            ),
            (
                "FROM to LIMIT",
                from.limit(1),
                " LIMIT 1"
            ),
            (
                "WHERE to ORDER BY",
                filtered.orderBy(company.name.ascending()),
                " WHERE (t1.name != 'skip') ORDER BY t1.name ASC"
            ),
            (
                "WHERE to LIMIT",
                filtered.limit(1),
                " WHERE (t1.name != 'skip') LIMIT 1"
            ),
            (
                "GROUP BY to ORDER BY",
                grouped.orderBy(company.name.ascending()),
                " GROUP BY t1.id, t1.name ORDER BY t1.name ASC"
            ),
            (
                "GROUP BY to LIMIT",
                grouped.limit(1),
                " GROUP BY t1.id, t1.name LIMIT 1"
            ),
            (
                "HAVING to LIMIT",
                having.limit(1),
                " GROUP BY t1.id, t1.name HAVING (COUNT(t1.id) >= 1) LIMIT 1"
            ),
        ]

        for (transition, statement, suffix) in cases {
            XCTAssertEqual(
                encoder.makeSQL(statement).sql,
                baseSQL + suffix,
                transition
            )
        }
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
        XCTAssertEqual(result.sql, "UPDATE Temp AS t0 SET value = ((t0.value || ' ') || t1.name) FROM (SELECT t0.id AS id, t0.name AS name FROM Company AS t0) AS t1 WHERE (t0.id == t1.id)")
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
        XCTAssertEqual(encoder.makeSQL(expression).sql, "CREATE TABLE IF NOT EXISTS Generic (id NOT NULL, type NOT NULL, value NOT NULL)")
    }
    
    
    // MARK: Create ... Select
    
    func testCreateTableUsingSelect() {
        
        let schema = XLSchema()
        let t = schema.create(Temp.self)
        let expression = create(t).as { schema in
            let t = schema.table(EmployeeTable.self)
            let r = Temp.columns(id: t.id, value: t.name)
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
            let r = Temp.columns(id: t.id, value: t.name)
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


    // Compile-only: the deprecated context verifies both retained v1 result helpers without adding
    // deprecation warnings to the warning-clean test build.
    @available(*, deprecated, message: "Exercises the source-compatible SwiftQL 1.x result helpers.")
    private func assertLegacyResultHelpersRemainSourceCompatible() {
        let _: SQLScalarResult<Int>.MetaResult = result {
            SQLScalarResult<Int>.SQLReader(scalarValue: 1)
        }
        let _: SQLScalarResult<Int>.MetaResult = result { reader in
            let scalarValue: Int = (try? reader.column(1, alias: "scalarValue")) ?? 0
            return SQLScalarResult(
                scalarValue: scalarValue
            )
        }
    }
}
