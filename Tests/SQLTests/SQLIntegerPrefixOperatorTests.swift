//
//  SQLIntegerPrefixOperatorTests.swift
//
//  A prefix `-`, `+`, or `~` on a plain `Int` keeps the standard library
//  operator inside a file that imports SwiftQL.
//
//  `Int` conforms to `XLExpression`, so SwiftQL's generic prefix operators over
//  `any XLExpression<T>` also match an `Int` operand. Swift 6.3 preferred those
//  operators, and ordinary code such as `let x = -someInt` stopped compiling for
//  every client of the library (issue #771). Each test below binds the result
//  without a type annotation and then uses it as an `Int`, so this file fails to
//  compile if the expression operator wins again.
//

import XCTest
import SwiftQL


final class XLIntegerPrefixOperatorTests: XLSyntaxTestCase {

    // MARK: - Plain integer operand


    func testNegate_IntegerConstant_IsInt() {
        let operand = 7
        let result = -operand
        assertInt(result, equals: -7)
    }


    func testNegate_IntegerVariable_IsInt() {
        var operand = 3
        operand += 1
        let result = -operand
        assertInt(result, equals: -4)
    }


    func testNegate_IntegerParameter_IsInt() {
        assertInt(negated(5), equals: -5)
        assertInt(negated(-5), equals: 5)
        assertInt(negated(0), equals: 0)
    }


    func testUnaryPlus_IntegerConstant_IsInt() {
        let operand = 7
        let result = +operand
        assertInt(result, equals: 7)
    }


    func testUnaryPlus_IntegerParameter_IsInt() {
        assertInt(unaryPlus(-5), equals: -5)
    }


    func testBitwiseNot_IntegerConstant_IsInt() {
        let operand = 7
        let result = ~operand
        assertInt(result, equals: -8)
    }


    func testBitwiseNot_IntegerParameter_IsInt() {
        assertInt(bitwiseNot(0), equals: -1)
        assertInt(bitwiseNot(-1), equals: 0)
    }


    func testNegate_IntegerBounds_MatchStandardLibrary() {
        let operand = Int.max
        let result = -operand
        assertInt(result, equals: Int.min + 1)
    }


    // MARK: - SwiftQL expression operand


    func testPrefixOperators_IntegerExpression_StillRenderSQL() {
        let x = XLNamedBindingReference<Int>(name: "x")
        assertRenders(-x, as: "-(:x)")
        assertRenders(+x, as: "+(:x)")
        assertRenders(~x, as: "~(:x)")
        assertRenders(-(-x), as: "-(-(:x))")
    }


    func testPrefixOperators_OptionalIntegerExpression_StillRenderSQL() {
        let x = XLNamedBindingReference<Optional<Int>>(name: "x")
        assertRenders(-x, as: "-(:x)")
        assertRenders(+x, as: "+(:x)")
        assertRenders(~x, as: "~(:x)")
    }


    func testPrefixOperators_IntegerLiteralExpression_StillRenderSQL() {
        let operand: any XLExpression<Int> = 12
        assertRenders(-operand, as: "-(12)")
        assertRenders(+operand, as: "+(12)")
        assertRenders(~operand, as: "~(12)")
    }


    // MARK: - Helpers


    /// Each helper binds the operator result with no type annotation, the shape
    /// that issue #771 reported, and returns it where `Int` is required.
    private func negated(_ operand: Int) -> Int {
        let result = -operand
        return result
    }


    private func unaryPlus(_ operand: Int) -> Int {
        let result = +operand
        return result
    }


    private func bitwiseNot(_ operand: Int) -> Int {
        let result = ~operand
        return result
    }


    /// The `Int` parameter is the compile-time assertion. The value comparison
    /// shows that the overload also computes what the standard library computes.
    private func assertInt(
        _ value: Int,
        equals expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value, expected, file: file, line: line)
    }
}
