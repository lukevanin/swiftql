//
//  SQLSyntaxExpressionTests.swift
//
//  Rendering of the composite expressions: concatenation, BETWEEN, CASE, IN,
//  the date and UUID families, and scalar and aggregate function calls.
//
//  Split from SQLSyntaxTests.swift (issue #567).
//

import XCTest
import SwiftQL


final class XLSyntaxExpressionTests: XLSyntaxTestCase {

    // MARK: - Text concatenation
    
    func test_TextBinding_Plus_String() {
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x + "foo"
        assertRenders(expression, as: "(:x || 'foo')")
    }
    
    func test_TextBinding_Plus_TextBinding() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + y
        assertRenders(expression, as: "(:x || :y)")
    }
    
    func test_TextBinding_Plus_String_Plus_TextBinding() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + "foo" + y
        assertRenders(expression, as: "((:x || 'foo') || :y)")
    }
    
    func test_OptionalTextBinding_Plus_Text() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x + "foo"
        assertRenders(expression, as: "(:x || 'foo')")
    }

    func test_TextConcatenation_NestedOnLeftOfEquality() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = (x + y) == "foobar"
        assertRenders(expression, as: "((:x || :y) == 'foobar')")
    }

    func test_TextConcatenation_NestedOnRightOfEquality() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = "foobar" == (x + y)
        assertRenders(expression, as: "('foobar' == (:x || :y))")
    }

    func test_TextConcatenation_CollatesCompleteResult() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = (x + y).collate(.nocase)
        assertRenders(expression, as: "((:x || :y) COLLATE NOCASE)")
    }

    func test_TextConcatenation_PreservesCollatedLeftOperandGrouping() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x.collate(.nocase) + y
        assertRenders(expression, as: "((:x COLLATE NOCASE) || :y)")
    }

    /// Built-in collations stay bare grammar tokens; a registered name is
    /// rendered as a quoted identifier so caller-supplied text cannot become
    /// SQL. This encoder uses `.noEscape`, which is why the identifier appears
    /// unquoted here — the point is that it goes through the identifier path
    /// rather than being concatenated into the keyword.
    func test_CustomCollation_RendersThroughTheIdentifierPath() {
        let x = XLNamedBindingReference<String>(name: "x")
        assertRenders(
            x.collate(.nocase),
            as: "(:x COLLATE NOCASE)"
        )
        assertRenders(
            x.collate(XLCollation(rawValue: "myCollation")),
            as: "(:x COLLATE myCollation)"
        )
    }

    /// The same custom collation under an escaping formatter. A name carrying a
    /// double quote must be escaped rather than closing the identifier and
    /// injecting trailing SQL.
    func test_CustomCollation_EscapesQuotesInTheName() {
        let escaping = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .sqlite)
        )
        let x = XLNamedBindingReference<String>(name: "x")
        XCTAssertEqual(
            escaping.makeSQL(x.collate(XLCollation(rawValue: "myCollation"))).sql,
            "(:x COLLATE \"myCollation\")"
        )
        XCTAssertEqual(
            escaping.makeSQL(
                x.collate(XLCollation(rawValue: "evil\" OR 1=1 --"))
            ).sql,
            "(:x COLLATE \"evil\"\" OR 1=1 --\")"
        )
    }

    func test_TextConcatenation_PreservesCollatedOperandGrouping() {
        let x = XLNamedBindingReference<String>(name: "x")
        let y = XLNamedBindingReference<String>(name: "y")
        let expression = x + y.collate(.nocase)
        assertRenders(expression, as: "(:x || (:y COLLATE NOCASE))")
    }
    
    
    // MARK: - Between


    func testBetweenOperatorSupportsLiteralBounds() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let expression = value.isBetween(7, 12)
        let _: any XLExpression<Bool> = expression

        assertRenders(
            expression,
            as: "(:value BETWEEN 7 AND 12)"
        )
    }


    func testNotBetweenOperatorSupportsBindingBounds() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let minimum = XLNamedBindingReference<Int>(name: "minimum")
        let maximum = XLNamedBindingReference<Int>(name: "maximum")
        let expression = value.isNotBetween(minimum, maximum)
        let _: any XLExpression<Bool> = expression

        assertRenders(
            expression,
            as: "(:value NOT BETWEEN :minimum AND :maximum)"
        )
    }


    func testBetweenOperatorPreservesNestedBooleanAndComparisonPrecedence() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let other = XLNamedBindingReference<Int>(name: "other")
        let expression = value.isBetween(7, 12) && other > 0

        assertRenders(
            expression,
            as: "((:value BETWEEN 7 AND 12) AND (:other > 0))"
        )
        assertRenders(
            value.isBetween(7, 12) == true,
            as: "((:value BETWEEN 7 AND 12) == 1)"
        )
    }


    func testBetweenOperatorPreservesNullableResultType() {
        let value = XLNamedBindingReference<Optional<Int>>(name: "value")
        let expression = value.isBetween(7, 12)
        let _: any XLExpression<Optional<Bool>> = expression

        assertRenders(
            expression,
            as: "(:value BETWEEN 7 AND 12)"
        )
    }
    
    
    // MARK: -  Case expression
    
    
    func test_SimpleCaseWhenThen_StringResult() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let expression = switchCase(value).when(1, then: "one")
        let _: any XLExpression<String?> = expression
        assertRenders(
            expression,
            as: "(CASE :value WHEN 1 THEN 'one' END)"
        )
    }


    func test_SimpleCaseWhenThenElse_StringResult() {
        let value = XLNamedBindingReference<Int>(name: "value")
        let expression = switchCase(value)
            .when(1, then: "one")
            .when(2, then: "two")
            .else("other")
        let _: any XLExpression<String> = expression
        assertRenders(
            expression,
            as: "(CASE :value WHEN 1 THEN 'one' WHEN 2 THEN 'two' ELSE 'other' END)"
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
        assertRenders(expression, as: "(CASE WHEN (:x == 12) THEN 42 END)")
    }


    func test_SearchedCaseWhenThenElse_IntegerResult() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = when(x == 12, then: 42).else(7)
        let _: any XLExpression<Int> = expression
        assertRenders(expression, as: "(CASE WHEN (:x == 12) THEN 42 ELSE 7 END)")
    }

    
    // MARK: - IN
    
    
    func test_TextBinding_In_Subquery() {
        let schema = XLSchema()
        let x = XLNamedBindingReference<String>(name: "x")
        let expression = x.in {
            let t = schema.table(EmployeeTable.self)
            return select(t.id).from(t).where(t.managerEmployeeId.isNull())
        }
        assertRenders(expression, as: "(:x IN (SELECT t0.id FROM Employee AS t0 WHERE (t0.managerEmployeeId ISNULL)))")
    }
    
    
    func test_OptionalTextBinding_In_Subquery() {
        let schema = XLSchema()
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.in {
            let t = schema.table(EmployeeTable.self, as: "t")
            return select(t.id).from(t)
        }
        assertRenders(expression, as: "(:x IN (SELECT t.id FROM Employee AS t))")
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
        assertRenders(expression, as: "ABS(:x)")
    }
    
    func testMinFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.min(12)
        assertRenders(expression, as: "MIN(:x, 12)")
    }

    func testMaxFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.max(12)
        assertRenders(expression, as: "MAX(:x, 12)")
    }

    func testMinMaxFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.max(0).min(1)
        assertRenders(expression, as: "MIN(MAX(:x, 0), 1)")
    }
    
    
    // MARK: - Aggregate function
    
    func testAverageFunction() {
        let x = XLNamedBindingReference<Double>(name: "x")
        let expression = x.averageOrNull()
        assertRenders(expression, as: "AVG(:x)")
    }
    
    //    func testAverageFunctionArithmetic() {
    //        let x = XLNamedBindingReference<Int>(name: "x")
    //        let expression = x.average() * 10
    //        XCTAssertEqual(encoder.makeSQL(expression), "(AVG(t.value) * 10.0)")
    //    }
    
    func testCountFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.count()
        assertRenders(expression, as: "COUNT(:x)")
    }
    
    func testCountDistinctFunction() {
        let x = XLNamedBindingReference<Int>(name: "x")
        let expression = x.count(distinct: true)
        assertRenders(expression, as: "COUNT(DISTINCT :x)")
    }


    func testGroupConcatFunction() {
        let expression = sqlQuery { schema in
            let company = schema.table(CompanyTable.self)
            return select(company.name.groupConcatOrNull()).from(company)
        }
        assertRenders(expression, as: "SELECT GROUP_CONCAT(t0.name) FROM Company AS t0")
    }


    func testGroupConcatDistinctFunction() {
        let expression = sqlQuery { schema in
            let company = schema.table(CompanyTable.self)
            return select(company.name.groupConcatOrNull(distinct: true)).from(company)
        }
        assertRenders(expression, as: "SELECT GROUP_CONCAT(DISTINCT t0.name) FROM Company AS t0")
    }


    func testGroupConcatSeparatorFunction() {
        let expression = sqlQuery { schema in
            let company = schema.table(CompanyTable.self)
            return select(company.name.groupConcatOrNull(separator: "|")).from(company)
        }
        assertRenders(expression, as: "SELECT GROUP_CONCAT(t0.name, '|') FROM Company AS t0")
    }
    
    //    func testCountFunctionArithmetic() {
    //        let x = XLIntegerColumnReference(table: SQLTableAlias(table: SQLTableReference(name: "MyTable"), as: "t"), name: "value")
    //        let expression = x.count() * 2
    //        XCTAssertEqual(encoder.makeSQL(expression), "(COUNT(t.value) * 2)")
    //    }
}
