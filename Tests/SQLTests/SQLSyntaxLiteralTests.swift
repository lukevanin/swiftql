//
//  SQLSyntaxLiteralTests.swift
//
//  Rendering of literals, casts, column references, function calls, and bound
//  parameters.
//
//  Split from SQLSyntaxTests.swift (issue #567), which was 2,042 lines and one
//  class, along its own `// MARK:` boundaries.
//

import XCTest
import SwiftQL


final class XLSyntaxLiteralTests: XLSyntaxTestCase {

    // MARK: - Literal
    
    
    func test_Boolean_True() {
        let expression: Bool = true
        assertRenders(expression, as: "1")
    }
    
    
    func test_Boolean_False() {
        let expression: Bool = false
        assertRenders(expression, as: "0")
    }
    
    
    func test_IntegerLiteral() {
        let expression: Int = 12
        assertRenders(expression, as: "12")
    }


    func test_IntegerLiteral_Int64Max() {
        let expression: Int = Int(Int64.max)
        assertRenders(expression, as: "9223372036854775807")
    }


    func test_IntegerLiteral_Int64Min() {
        let expression: Int = Int(Int64.min)
        assertRenders(expression, as: "-9223372036854775808")
    }


    func test_IntegerLiteral_MillisecondEpochTimestamp() {
        let expression: Int = 1_752_000_000_000
        assertRenders(expression, as: "1752000000000")
    }

    
    func test_RealLiteral() {
        let expression: Double = 17.4
        assertRenders(expression, as: "17.4")
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
        assertRenders(expression, as: "'foo'")
    }


    func test_TextLiteral_EscapesSingleQuote() {
        let expression: String = "O'Brien"
        assertRenders(expression, as: "'O''Brien'")
    }


    func test_TextLiteral_EscapesInjectionAttempt() {
        let expression: String = "x' OR '1'='1"
        assertRenders(expression, as: "'x'' OR ''1''=''1'")
    }


    func test_TextLiteral_PreservesCommentSequence() {
        let expression: String = "a--b"
        assertRenders(expression, as: "'a--b'")
    }


    func test_TextLiteral_EmptyString() {
        let expression: String = ""
        assertRenders(expression, as: "''")
    }


    func test_TextLiteral_EmbeddedNulCharacter() {
        // A NUL cannot be escaped inside a SQL string literal. Verify the
        // quotes remain balanced so the value cannot break out of the literal.
        let expression: String = "a\0b"
        assertRenders(expression, as: "'a\0b'")
    }


    func test_TextLiteral_StaticString_EscapesSingleQuote() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .noEscape)
        let literal: StaticString = "O'Brien"
        XCTAssertEqual(formatter.text(literal), "'O''Brien'")
    }
    
    
    func test_BlobLiteral() {
        let expression: Data = Data([0x01])
        assertRenders(expression, as: "x'01'")
    }


    // MARK: - Type cast


    func test_Text_ToData_CastsToBlob() {
        let expression = "abc".toData()
        assertRenders(expression, as: "CAST('abc' AS BLOB)")
    }


    func test_OptionalTextReference_ToData_CastsToBlob() {
        let x = XLNamedBindingReference<Optional<String>>(name: "x")
        let expression = x.toData()
        assertRenders(expression, as: "CAST(:x AS BLOB)")
    }



    // MARK: - Column reference
    
    
    func test_ColumnReference() {
        let table = XLSchema().table(TestTable.self, as: "sample")
        assertRenders(table.value, as: "sample.value")
    }


    func test_SQLResultColumns_AreAvailableAcrossFilesOnSwift59() {
        let row = Swift59ColumnsLookupProjection.columns(value: 1)
        assertRenders(select(row), as: "SELECT 1 AS value")
    }
    
    
    // MARK: - Function
    
    
    func test_Function() {
        let parameter = XLNamedBindingReference<Int>(name: "value")
        let function = XLFunction<Int>(
            name: "CUSTOM",
            distinct: true,
            parameters: [parameter, 1]
        )
        assertRenders(function, as: "CUSTOM(DISTINCT :value, 1)")
    }
    
    
    // MARK: - Bind parameter
    
    
    func test_SchemaBinding_UsesRequestedName() {
        let binding = XLSchema().binding(of: Int.self, as: "value")
        assertRenders(binding, as: ":value")
    }
}
