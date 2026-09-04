//
//  SQLRowMacroTests.swift
//  SwiftQL
//
//  Macro-expansion tests for the `#row` freestanding expression macro: the supported one- through
//  six-column shapes, and the diagnostics for misuse.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SQLMacros


private func makeRowTestMacros() -> [String: Macro.Type] {
    ["row": SQLRowMacro.self]
}


final class SQLRowMacroExpansionTests: XCTestCase {

    func test_oneColumn_expandsToScalarResultColumns() {
        assertMacroExpansion(
            """
            let row = #row(person.id)
            """,
            expandedSource: """
            let row = SQLScalarResult.columns(scalarValue: person.id)
            """,
            macros: makeRowTestMacros()
        )
    }

    func test_twoColumns_expandsToSQLRow2Columns() {
        assertMacroExpansion(
            """
            let row = #row(person.id, person.name)
            """,
            expandedSource: """
            let row = SQLRow2.columns(_0: person.id, _1: person.name)
            """,
            macros: makeRowTestMacros()
        )
    }

    func test_threeColumns_expandsToSQLRow3Columns() {
        assertMacroExpansion(
            """
            let row = #row(person.id, person.name, person.age)
            """,
            expandedSource: """
            let row = SQLRow3.columns(_0: person.id, _1: person.name, _2: person.age)
            """,
            macros: makeRowTestMacros()
        )
    }

    func test_fourColumns_expandsToSQLRow4Columns() {
        assertMacroExpansion(
            """
            let row = #row(a, b, c, d)
            """,
            expandedSource: """
            let row = SQLRow4.columns(_0: a, _1: b, _2: c, _3: d)
            """,
            macros: makeRowTestMacros()
        )
    }

    func test_fiveColumns_expandsToSQLRow5Columns() {
        assertMacroExpansion(
            """
            let row = #row(a, b, c, d, e)
            """,
            expandedSource: """
            let row = SQLRow5.columns(_0: a, _1: b, _2: c, _3: d, _4: e)
            """,
            macros: makeRowTestMacros()
        )
    }

    func test_sixColumns_expandsToSQLRow6Columns() {
        assertMacroExpansion(
            """
            let row = #row(a, b, c, d, e, f)
            """,
            expandedSource: """
            let row = SQLRow6.columns(_0: a, _1: b, _2: c, _3: d, _4: e, _5: f)
            """,
            macros: makeRowTestMacros()
        )
    }

    func test_zeroColumns_emitsDiagnostic() {
        assertMacroExpansion(
            """
            let row = #row()
            """,
            expandedSource: """
            let row = ()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'#row' requires at least one column expression, such as '#row(person.id)'.",
                    line: 1,
                    column: 11
                )
            ],
            macros: makeRowTestMacros()
        )
    }

    func test_tooManyColumns_emitsDiagnostic() {
        assertMacroExpansion(
            """
            let row = #row(a, b, c, d, e, f, g)
            """,
            expandedSource: """
            let row = ()
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'#row' supports at most 6 columns; declare a named result with '@SQLResult' for wider projections.",
                    line: 1,
                    column: 11
                )
            ],
            macros: makeRowTestMacros()
        )
    }

    func test_labeledArgument_emitsDiagnostic() {
        assertMacroExpansion(
            """
            let row = #row(scalarValue: person.id)
            """,
            expandedSource: """
            let row = SQLScalarResult.columns(scalarValue: person.id)
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'#row' does not accept labeled arguments; pass column expressions positionally, such as '#row(person.id, person.name)'.",
                    line: 1,
                    column: 16
                )
            ],
            macros: makeRowTestMacros()
        )
    }
}
