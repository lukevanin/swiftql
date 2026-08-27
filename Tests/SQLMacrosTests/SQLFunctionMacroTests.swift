//
//  SQLFunctionMacroTests.swift
//  SwiftQL
//
//  Tests for the `SQLFunction` macro: generation of the `definition` and `makeSQL(context:)`
//  members from a struct's stored properties, and diagnostics for unsupported declarations.
//

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SQLMacros


private func makeTestMacros() -> [String: Macro.Type] {
    ["SQLFunction": SQLFunctionMacro.self]
}


final class SQLFunctionMacroTests: XCTestCase {

    func test_zeroParameters_generatesDefinitionAndMakeSQL() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "now")
            struct NowFunction {
            }
            """,
            expandedSource: """
            struct NowFunction {

                public static let definition = XLCustomFunctionDefinition(name: "now", numberOfArguments: 0)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { _ in
                        }
                  }
            }
            """,
            macros: makeTestMacros()
        )
    }

    /// A raw string literal carries no escapes, so a `name:` written as one can
    /// hold a quote or a backslash that has to be put back when the name is
    /// emitted into generated source. Before issue #563 the name went between
    /// quotes unchanged, so this expanded to `name: "quote"inside"` and the
    /// annotated declaration failed to compile with errors pointing at code the
    /// author never wrote.
    func test_rawStringName_isEscapedInTheGeneratedDefinition() {
        assertMacroExpansion(
            #"""
            @SQLFunction(name: #"quote"inside"#)
            struct QuotedNameFunction {
            }
            """#,
            expandedSource: #"""
            struct QuotedNameFunction {

                public static let definition = XLCustomFunctionDefinition(name: "quote\"inside", numberOfArguments: 0)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { _ in
                        }
                  }
            }
            """#,
            macros: makeTestMacros()
        )
    }

    /// The same name written with an escape means the same thing, and produces
    /// the same generated source. It did not before: the escaped source text
    /// was carried through verbatim, so the SQL function name held a backslash
    /// that the author never wrote.
    func test_escapedStringName_producesTheSameGeneratedDefinition() {
        assertMacroExpansion(
            #"""
            @SQLFunction(name: "quote\"inside")
            struct QuotedNameFunction {
            }
            """#,
            expandedSource: #"""
            struct QuotedNameFunction {

                public static let definition = XLCustomFunctionDefinition(name: "quote\"inside", numberOfArguments: 0)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { _ in
                        }
                  }
            }
            """#,
            macros: makeTestMacros()
        )
    }

    func test_oneParameter_generatesDefinitionAndMakeSQL() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "columnReadInteger")
            struct ColumnReadIntegerFunction {
                private let value: any XLExpression<Int?>
            }
            """,
            expandedSource: """
            struct ColumnReadIntegerFunction {
                private let value: any XLExpression<Int?>

                public static let definition = XLCustomFunctionDefinition(name: "columnReadInteger", numberOfArguments: 1)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { context in
                            context.listItem(expression: value.makeSQL)
                        }
                  }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_manyParameters_generatesDefinitionAndMakeSQLInDeclarationOrder() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "haversineDistance")
            struct HaversineDistance {
                private let fromLatitude: any XLExpression<Double>
                private let fromLongitude: any XLExpression<Double>
                private let toLatitude: any XLExpression<Double>
                private let toLongitude: any XLExpression<Double>
            }
            """,
            expandedSource: """
            struct HaversineDistance {
                private let fromLatitude: any XLExpression<Double>
                private let fromLongitude: any XLExpression<Double>
                private let toLatitude: any XLExpression<Double>
                private let toLongitude: any XLExpression<Double>

                public static let definition = XLCustomFunctionDefinition(name: "haversineDistance", numberOfArguments: 4)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { context in
                            context.listItem(expression: fromLatitude.makeSQL)
                            context.listItem(expression: fromLongitude.makeSQL)
                            context.listItem(expression: toLatitude.makeSQL)
                            context.listItem(expression: toLongitude.makeSQL)
                        }
                  }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_defaultName_usesStructName() {
        assertMacroExpansion(
            """
            @SQLFunction
            struct MyFunction {
                private let value: any XLExpression<Int>
            }
            """,
            expandedSource: """
            struct MyFunction {
                private let value: any XLExpression<Int>

                public static let definition = XLCustomFunctionDefinition(name: "MyFunction", numberOfArguments: 1)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { context in
                            context.listItem(expression: value.makeSQL)
                        }
                  }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_someExpressionType_isAccepted() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "wrap")
            struct WrapFunction {
                let value: some XLExpression<Int>
            }
            """,
            expandedSource: """
            struct WrapFunction {
                let value: some XLExpression<Int>

                public static let definition = XLCustomFunctionDefinition(name: "wrap", numberOfArguments: 1)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { context in
                            context.listItem(expression: value.makeSQL)
                        }
                  }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_moduleQualifiedExpressionType_isAccepted() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "wrap")
            struct WrapFunction {
                let value: any SwiftQL.XLExpression<Int>
            }
            """,
            expandedSource: """
            struct WrapFunction {
                let value: any SwiftQL.XLExpression<Int>

                public static let definition = XLCustomFunctionDefinition(name: "wrap", numberOfArguments: 1)

                public func makeSQL(context: inout XLBuilder) {
                        context.simpleFunction(name: Self.definition.name) { context in
                            context.listItem(expression: value.makeSQL)
                        }
                  }
            }
            """,
            macros: makeTestMacros()
        )
    }

    // MARK: - Diagnostics

    func test_nonStructDeclaration_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction
            class Sample {
            }
            """,
            expandedSource: """
            class Sample {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLFunction' can only be applied to a struct.",
                    line: 1,
                    column: 1
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_nonExpressionStoredProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                let value: Int
            }
            """,
            expandedSource: """
            struct Sample {
                let value: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'value' must be typed as 'any XLExpression<...>' (or 'some XLExpression<...>') to be used as a function argument. Found 'Int'.",
                    line: 3,
                    column: 16
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_computedProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                var value: any XLExpression<Int> {
                    fatalError()
                }
            }
            """,
            expandedSource: """
            struct Sample {
                var value: any XLExpression<Int> {
                    fatalError()
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Computed properties cannot be used as function arguments. Move the property to an extension of the type to exclude it from the generated 'makeSQL' implementation.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_staticProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                static var shared: any XLExpression<Int> = XLLiteralValue(0)
            }
            """,
            expandedSource: """
            struct Sample {
                static var shared: any XLExpression<Int> = XLLiteralValue(0)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'static' properties cannot be used as function arguments. Move the property to an extension of the type to exclude it from the generated 'makeSQL' implementation.",
                    line: 3,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_lazyProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                lazy var value: any XLExpression<Int> = XLLiteralValue(0)
            }
            """,
            expandedSource: """
            struct Sample {
                lazy var value: any XLExpression<Int> = XLLiteralValue(0)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'lazy' properties cannot be used as function arguments. Use a plain stored property instead.",
                    line: 3,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_tuplePattern_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                var (x, y): (any XLExpression<Int>, any XLExpression<Int>)
            }
            """,
            expandedSource: """
            struct Sample {
                var (x, y): (any XLExpression<Int>, any XLExpression<Int>)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Pattern '(x, y)' cannot be used as a function argument. Declare each argument as a separate property with its own name and type.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_missingTypeAnnotation_emitsError() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                var value = XLLiteralValue(0)
            }
            """,
            expandedSource: """
            struct Sample {
                var value = XLLiteralValue(0)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'value' needs an explicit type annotation to be used as a function argument.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_invalidNameArgument_emitsError() {
        assertMacroExpansion(
            #"""
            @SQLFunction(name: "foo\(1)")
            struct Sample {
                let value: any XLExpression<Int>
            }
            """#,
            expandedSource: """
            struct Sample {
                let value: any XLExpression<Int>
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "The 'name' argument must be a simple string literal without interpolation. Remove the interpolation, or omit the argument to use the name of the struct.",
                    line: 1,
                    column: 20
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_multipleUnsupportedProperties_emitsAllDiagnostics() {
        assertMacroExpansion(
            """
            @SQLFunction(name: "foo")
            struct Sample {
                let a: Int
                let b: any XLExpression<Int>
                let c: String
            }
            """,
            expandedSource: """
            struct Sample {
                let a: Int
                let b: any XLExpression<Int>
                let c: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'a' must be typed as 'any XLExpression<...>' (or 'some XLExpression<...>') to be used as a function argument. Found 'Int'.",
                    line: 3,
                    column: 12
                ),
                DiagnosticSpec(
                    message: "Property 'c' must be typed as 'any XLExpression<...>' (or 'some XLExpression<...>') to be used as a function argument. Found 'String'.",
                    line: 5,
                    column: 12
                ),
            ],
            macros: makeTestMacros()
        )
    }
}
