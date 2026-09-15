//
//  SQLBindingsMacroTests.swift
//  SwiftQL
//
//  Tests for the `@SQLBindings` member macro (issue #663): one typed binding
//  reference per stored property, the packet builders, and diagnostics for
//  property shapes that cannot be a named binding.
//

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SQLMacros


private func makeTestMacros() -> [String: Macro.Type] {
    ["SQLBindings": SQLBindingsMacro.self]
}


final class SQLBindingsMacroExpansionTests: XCTestCase {

    func test_properties_generateTypedReferencesAndPacketBuilders() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct PersonBindings {
                var name: String
                var age: Int?
            }
            """,
            expandedSource: """
            struct PersonBindings {
                var name: String
                var age: Int?

                static var name: XLNamedBindingReference<String> {
                    XLNamedBindingReference<String>(name: "name")
                }

                static var age: XLNamedBindingReference<Int?> {
                    XLNamedBindingReference<Int?>(name: "age")
                }

                func bindings(in __xlLayout: XLParameterLayout) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(self.name, named: "name", in: __xlLayout),
                            try _xlQueryParameterBinding(self.age, named: "age", in: __xlLayout),
                        ]
                    ).validatingComplete()
                }

                func bindings<__XLRequest: XLRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }

                func bindings<__XLRequest: XLWriteRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    /// A public struct's generated members are public, so a statement and a
    /// packet in another module can use them.
    func test_publicStruct_generatesPublicMembers() {
        assertMacroExpansion(
            """
            @SQLBindings
            public struct IDBindings {
                public var id: String
            }
            """,
            expandedSource: """
            public struct IDBindings {
                public var id: String

                public static var id: XLNamedBindingReference<String> {
                    XLNamedBindingReference<String>(name: "id")
                }

                public func bindings(in __xlLayout: XLParameterLayout) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(self.id, named: "id", in: __xlLayout),
                        ]
                    ).validatingComplete()
                }

                public func bindings<__XLRequest: XLRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }

                public func bindings<__XLRequest: XLWriteRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    /// A private struct already limits its members. Private members would be
    /// unreachable from the rest of the file, so they take the default level.
    func test_privateStruct_generatesMembersWithoutAccessModifier() {
        assertMacroExpansion(
            """
            @SQLBindings
            private struct IDBindings {
                var id: String
            }
            """,
            expandedSource: """
            private struct IDBindings {
                var id: String

                static var id: XLNamedBindingReference<String> {
                    XLNamedBindingReference<String>(name: "id")
                }

                func bindings(in __xlLayout: XLParameterLayout) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(self.id, named: "id", in: __xlLayout),
                        ]
                    ).validatingComplete()
                }

                func bindings<__XLRequest: XLRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }

                func bindings<__XLRequest: XLWriteRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    /// An escaped property keeps its backticks in Swift and loses them in the
    /// placeholder name.
    func test_escapedPropertyName_usesUnescapedPlaceholderName() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct KeywordBindings {
                var `default`: String
            }
            """,
            expandedSource: """
            struct KeywordBindings {
                var `default`: String

                static var `default`: XLNamedBindingReference<String> {
                    XLNamedBindingReference<String>(name: "default")
                }

                func bindings(in __xlLayout: XLParameterLayout) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(self.`default`, named: "default", in: __xlLayout),
                        ]
                    ).validatingComplete()
                }

                func bindings<__XLRequest: XLRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }

                func bindings<__XLRequest: XLWriteRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    /// Methods, initializers, and nested types are not bindings.
    func test_emptyStruct_generatesEmptyPacket() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct NoBindings {
                func describe() -> String { "" }
            }
            """,
            expandedSource: """
            struct NoBindings {
                func describe() -> String { "" }

                func bindings(in __xlLayout: XLParameterLayout) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()
                }

                func bindings<__XLRequest: XLRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }

                func bindings<__XLRequest: XLWriteRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
                    try self.bindings(in: __xlRequest.parameterLayout)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }
}


final class SQLBindingsMacroDiagnosticTests: XCTestCase {

    func test_nonStructDeclaration_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            enum Sample {
            }
            """,
            expandedSource: """
            enum Sample {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLBindings' can only be applied to a struct.",
                    line: 1,
                    column: 1
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_staticProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                static var id: String = ""
            }
            """,
            expandedSource: """
            struct Sample {
                static var id: String = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'static' properties cannot be used as named bindings. Move the property to an extension of the type to exclude it from the generated binding packet.",
                    line: 3,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_computedProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                var id: String { "" }
            }
            """,
            expandedSource: """
            struct Sample {
                var id: String { "" }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Computed properties cannot be used as named bindings. Move the property to an extension of the type to exclude it from the generated binding packet.",
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
            @SQLBindings
            struct Sample {
                var id = ""
            }
            """,
            expandedSource: """
            struct Sample {
                var id = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'id' needs an explicit type annotation to be used as a named binding. The type declares the value type of the binding.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_tuplePattern_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                var (id, name): (String, String)
            }
            """,
            expandedSource: """
            struct Sample {
                var (id, name): (String, String)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Pattern '(id, name)' cannot be used as a named binding. Declare each binding as a separate property with its own name and type.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    /// An initial value would give the memberwise-initializer argument a
    /// default, so `Sample()` would compile and bind the initial value.
    func test_propertyWithInitialValue_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                var id: String = ""
            }
            """,
            expandedSource: """
            struct Sample {
                var id: String = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'id' cannot have an initial value when it is used as a named binding. The initial value makes the memberwise-initializer argument optional, so a call that leaves the value out would compile and bind the initial value. Remove the initial value.",
                    line: 3,
                    column: 20
                )
            ],
            macros: makeTestMacros()
        )
    }

    /// A `let` with an initial value is not an initializer argument at all.
    func test_letPropertyWithInitialValue_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                let id: String = ""
            }
            """,
            expandedSource: """
            struct Sample {
                let id: String = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'id' cannot have an initial value when it is used as a named binding. The initial value makes the memberwise-initializer argument optional, so a call that leaves the value out would compile and bind the initial value. Remove the initial value.",
                    line: 3,
                    column: 20
                )
            ],
            macros: makeTestMacros()
        )
    }

    /// A declared initializer can fill in a value, so it removes the
    /// guarantee that a missing value does not compile.
    func test_structWithInitializer_emitsError() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                var id: String
                init() {
                    self.id = ""
                }
            }
            """,
            expandedSource: """
            struct Sample {
                var id: String
                init() {
                    self.id = ""
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLBindings' cannot be applied to a struct that declares an initializer. The memberwise initializer is what makes a missing value a compile error. Remove the initializer, and build the values in a function that calls the memberwise initializer.",
                    line: 4,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    /// Every invalid property is reported in one pass, in source order.
    func test_severalInvalidProperties_reportEveryOne() {
        assertMacroExpansion(
            """
            @SQLBindings
            struct Sample {
                lazy var id: String = ""
                var name = ""
            }
            """,
            expandedSource: """
            struct Sample {
                lazy var id: String = ""
                var name = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'lazy' properties cannot be used as named bindings. Use a plain stored property instead.",
                    line: 3,
                    column: 5
                ),
                DiagnosticSpec(
                    message: "Property 'name' needs an explicit type annotation to be used as a named binding. The type declares the value type of the binding.",
                    line: 4,
                    column: 9
                ),
            ],
            macros: makeTestMacros()
        )
    }
}
