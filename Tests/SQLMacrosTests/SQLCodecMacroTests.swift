//
//  SQLCodecMacroTests.swift
//  SwiftQL
//
//  Tests for the `@SQLCodec` property attribute macro (issue #66): syntactic diagnostics for a
//  malformed or conflicting selector, and the codec metadata/convenience declarations that
//  `SQLTableMacro`/`SQLResultMacro` generate for an annotated property. `@SQLCodec` itself expands
//  to nothing (see `SQLCodecMacro`); every observable effect comes from `MetaBuilder` reading the
//  attribute while it walks the struct's members, so most of these tests exercise `MetaBuilder`
//  directly -- the same style already used for `makeStaticRowLayoutFunction()` above.
//

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SQLMacros


private func makeTestMacros() -> [String: Macro.Type] {
    [
        "SQLTable": SQLTableMacro.self,
        "SQLResult": SQLResultMacro.self,
        "SQLCodec": SQLCodecMacro.self,
    ]
}


/// Wrapper which isolates the generated `_swiftQLPropertyCodecKeys` declaration (the fourth
/// member `SQLTableMacro`/`SQLResultMacro` emit, after the initializer, `columns()`, and
/// `staticRowLayout(using:...)`) for a focused expansion snapshot.
private struct SQLTableCodecKeysMemberMacro: MemberMacro {

    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        Array(
            try SQLTableMacro.expansion(
                of: node,
                providingMembersOf: declaration,
                in: context
            ).dropFirst(3).prefix(1)
        )
    }
}

private func makeCodecKeysMemberTestMacros() -> [String: Macro.Type] {
    [
        "SQLTable": SQLTableCodecKeysMemberMacro.self,
        "SQLCodec": SQLCodecMacro.self,
    ]
}


/// Wrapper which isolates every generated `staticResultField(_:...)` convenience -- everything
/// after the initializer, `columns()`, `staticRowLayout(using:...)`, and
/// `_swiftQLPropertyCodecKeys` -- for a focused expansion snapshot.
private struct SQLTableCodecResultFieldsMemberMacro: MemberMacro {

    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        Array(
            try SQLTableMacro.expansion(
                of: node,
                providingMembersOf: declaration,
                in: context
            ).dropFirst(4)
        )
    }
}

private func makeCodecResultFieldsMemberTestMacros() -> [String: Macro.Type] {
    [
        "SQLTable": SQLTableCodecResultFieldsMemberMacro.self,
        "SQLCodec": SQLCodecMacro.self,
    ]
}


// MARK: - Diagnostics


final class SQLCodecMacroDiagnosticTests: XCTestCase {

    func test_labeledArgument_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var id: Int
                @SQLCodec(key: XLValueCodecKey(id: "sample.badge", version: 1))
                var badge: String
            }
            """,
            expandedSource: """
            struct Sample {
                var id: Int
                var badge: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLCodec' requires exactly one unlabeled argument naming a durable 'XLValueCodecKey'.",
                    line: 4,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_zeroArguments_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var id: Int
                @SQLCodec()
                var badge: String
            }
            """,
            expandedSource: """
            struct Sample {
                var id: Int
                var badge: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLCodec' requires exactly one unlabeled argument naming a durable 'XLValueCodecKey'.",
                    line: 4,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_conflictingSelectors_emitsErrorForEachExtra() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var id: Int
                @SQLCodec(FirstCodecs.badge)
                @SQLCodec(SecondCodecs.badge)
                var badge: String
            }
            """,
            expandedSource: """
            struct Sample {
                var id: Int
                var badge: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property has more than one '@SQLCodec' attribute. A property may select at most one explicit codec.",
                    line: 5,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_sharedBindingDeclaration_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var id: Int
                @SQLCodec(Codecs.shared)
                var a, b: Int
            }
            """,
            expandedSource: """
            struct Sample {
                var id: Int
                var a, b: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLCodec' cannot be shared by several bindings in one declaration. Declare the annotated property in its own 'var'/'let' statement.",
                    line: 4,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_validSelector_emitsNoDiagnostics() {
        assertMacroExpansion(
            """
            @SQLCodec(Codecs.badge)
            var badge: String
            """,
            expandedSource: """
            var badge: String
            """,
            macros: ["SQLCodec": SQLCodecMacro.self]
        )
    }

    // Round-1 Copilot review on issue #66's PR: a property literally named
    // `staticResultField` would otherwise compile alongside the macro's own generated
    // `staticResultField(_:...)` convenience (an instance property and a static function sharing
    // one base name are not, by themselves, a Swift redeclaration error), but the resulting call
    // site is genuinely confusing to read, and whether the macro even emits that static overload
    // depends on unrelated `@SQLCodec` usage elsewhere on the same type. The name is reserved
    // unconditionally so this is always one focused diagnostic instead of a conditional trap.
    func test_propertyNamedStaticResultField_isReserved() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var staticResultField: String
            }
            """,
            expandedSource: """
            struct Sample {
                var staticResultField: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property name 'staticResultField' conflicts with a member generated by the macro. Rename the property.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }
}


// MARK: - `MetaBuilder` property collection


final class SQLCodecPropertyCollectionTests: XCTestCase {

    private func makeBuilder(_ source: String) throws -> MetaBuilder {
        let file = Parser.parse(source: source)
        let structDecl = file.statements
            .compactMap { $0.item.as(StructDeclSyntax.self) }
            .first
        let attribute = structDecl?.attributes
            .compactMap { element -> AttributeSyntax? in
                if case let .attribute(attribute) = element {
                    return attribute
                }
                return nil
            }
            .first
        guard let structDecl, let attribute else {
            throw SQLMacroError.unsupportedType
        }
        return try MetaBuilder(node: attribute, declaration: structDecl)
    }

    func test_annotatedProperty_capturesTrimmedCodecKeyExpression() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.badge)
                var badge: String
                var plain: Int
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 2)
        XCTAssertEqual(builder.properties[0].name, "badge")
        XCTAssertEqual(builder.properties[0].codecKeyExpression, "Codecs.badge")
        XCTAssertEqual(builder.properties[1].name, "plain")
        XCTAssertNil(builder.properties[1].codecKeyExpression)
    }

    func test_multiLineCodecKeyExpression_isTrimmedOfIndentation() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(XLValueCodecKey(id: "sample.badge", version: 1))
                var badge: String
            }
            """
        )
        XCTAssertEqual(
            builder.properties[0].codecKeyExpression,
            "XLValueCodecKey(id: \"sample.badge\", version: 1)"
        )
    }
}


// MARK: - Generated codec-key metadata


final class SQLCodecKeysDeclarationTests: XCTestCase {

    private func makeBuilder(_ source: String) throws -> MetaBuilder {
        let file = Parser.parse(source: source)
        let structDecl = file.statements
            .compactMap { $0.item.as(StructDeclSyntax.self) }
            .first
        let attribute = structDecl?.attributes
            .compactMap { element -> AttributeSyntax? in
                if case let .attribute(attribute) = element {
                    return attribute
                }
                return nil
            }
            .first
        guard let structDecl, let attribute else {
            throw SQLMacroError.unsupportedType
        }
        return try MetaBuilder(node: attribute, declaration: structDecl)
    }

    func test_noAnnotations_generatesEmptyDictionary() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var id: Int
            }
            """
        )
        let source = builder.makeCodecKeysDeclaration()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(
            source.contains(
                "public static var _swiftQLPropertyCodecKeys: [String: SwiftQL.XLValueCodecKey]"
            )
        )
        XCTAssertTrue(source.contains("[:]"))
        XCTAssertFalse(source.contains("\"id\""))
    }

    func test_mixedAnnotations_includesOnlyAnnotatedPropertiesKeyedByAlias() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.badge)
                var badge: String
                var plain: Int
                @SQLCodec(Codecs.escapedNote)
                var `class`: String
            }
            """
        )
        let source = builder.makeCodecKeysDeclaration()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("\"badge\": Codecs.badge,"))
        XCTAssertTrue(source.contains("\"class\": Codecs.escapedNote,"))
        XCTAssertFalse(source.contains("\"plain\""))
    }

    // Isolated, exact-match snapshot of the generated declaration as it appears in the fully
    // expanded struct (issue #66 "Done when": macro-expansion snapshot test).
    func test_generatedDeclaration_exactExpansionSnapshot() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.badge)
                var badge: String
                var plain: Int
            }
            """,
            expandedSource: """
            struct Sample {
                var badge: String
                var plain: Int

                public static var _swiftQLPropertyCodecKeys: [String: SwiftQL.XLValueCodecKey] {
                        [
                            "badge": Codecs.badge,
                        ]
                  }
            }
            """,
            macros: makeCodecKeysMemberTestMacros()
        )
    }
}


// MARK: - Generated `staticResultField(_:...)` convenience


final class SQLCodecResultFieldFunctionTests: XCTestCase {

    private func makeBuilder(_ source: String) throws -> MetaBuilder {
        let file = Parser.parse(source: source)
        let structDecl = file.statements
            .compactMap { $0.item.as(StructDeclSyntax.self) }
            .first
        let attribute = structDecl?.attributes
            .compactMap { element -> AttributeSyntax? in
                if case let .attribute(attribute) = element {
                    return attribute
                }
                return nil
            }
            .first
        guard let structDecl, let attribute else {
            throw SQLMacroError.unsupportedType
        }
        return try MetaBuilder(node: attribute, declaration: structDecl)
    }

    func test_noAnnotations_generatesNoFunctions() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var id: Int
            }
            """
        )
        XCTAssertTrue(builder.makeCodecResultFieldFunctions().isEmpty)
    }

    func test_requiredProperty_generatesNonOptionalConvenience() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.timestamp)
                var timestamp: Date
            }
            """
        )
        let functions = builder.makeCodecResultFieldFunctions()
        XCTAssertEqual(functions.count, 1)
        let source = functions[0]

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(
            source.contains(
                "public static func staticResultField<_SwiftQLCodecStorage>(timestamp expression: any SwiftQL.XLEncodable, storedAs storageType: _SwiftQLCodecStorage.Type, identifiedBy identity: SwiftQL.XLQuerySlotIdentity, using dialect: SwiftQL.XLSQLiteDialect, context: SwiftQL.XLValueCodingContext? = nil, configuration: SwiftQL.XLValueCodingConfiguration) throws -> SwiftQL.XLStaticSelectField<Date, _SwiftQLCodecStorage, SwiftQL.XLSQLiteDialect> where _SwiftQLCodecStorage: SwiftQL.XLLiteral"
            )
        )
        XCTAssertTrue(source.contains("Date.self,"))
        XCTAssertTrue(source.contains("selection: .explicit(Codecs.timestamp)"))
        // Trailing argument must not carry a trailing comma inside the call parenthesis.
        XCTAssertFalse(source.contains("selection: .explicit(Codecs.timestamp),"))
    }

    func test_optionalProperty_generatesOptionalConvenience() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.note)
                var note: Date?
            }
            """
        )
        let functions = builder.makeCodecResultFieldFunctions()
        XCTAssertEqual(functions.count, 1)
        let source = functions[0]

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("storedAs storageType: _SwiftQLCodecStorage?.Type"))
        XCTAssertTrue(
            source.contains(
                "SwiftQL.XLStaticSelectField<Date?, _SwiftQLCodecStorage?, SwiftQL.XLSQLiteDialect>"
            )
        )
        XCTAssertTrue(source.contains("Date?.self,"))
        XCTAssertTrue(source.contains("selection: .explicit(Codecs.note)"))
    }

    func test_onlyAnnotatedPropertiesGenerateFunctions() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.left)
                var left: String
                var plain: Int
                @SQLCodec(Codecs.right)
                var right: String
            }
            """
        )
        let functions = builder.makeCodecResultFieldFunctions()
        XCTAssertEqual(functions.count, 2)
        XCTAssertTrue(functions[0].contains("staticResultField<_SwiftQLCodecStorage>(left "))
        XCTAssertTrue(functions[1].contains("staticResultField<_SwiftQLCodecStorage_1>(right "))
    }

    func test_backtickedPropertyName_isPreservedAsArgumentLabel() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.escaped)
                var `class`: String
            }
            """
        )
        let functions = builder.makeCodecResultFieldFunctions()
        XCTAssertEqual(functions.count, 1)
        XCTAssertTrue(functions[0].contains("staticResultField<_SwiftQLCodecStorage>(`class` "))
    }

    // Isolated, exact-match snapshot of every generated convenience as they appear in the fully
    // expanded struct (issue #66 "Done when": macro-expansion snapshot test).
    func test_generatedFunctions_exactExpansionSnapshot() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                @SQLCodec(Codecs.badge)
                var badge: String
            }
            """,
            expandedSource: """
            struct Sample {
                var badge: String

                public static func staticResultField<_SwiftQLCodecStorage>(badge expression: any SwiftQL.XLEncodable, storedAs storageType: _SwiftQLCodecStorage.Type, identifiedBy identity: SwiftQL.XLQuerySlotIdentity, using dialect: SwiftQL.XLSQLiteDialect, context: SwiftQL.XLValueCodingContext? = nil, configuration: SwiftQL.XLValueCodingConfiguration) throws -> SwiftQL.XLStaticSelectField<String, _SwiftQLCodecStorage, SwiftQL.XLSQLiteDialect> where _SwiftQLCodecStorage: SwiftQL.XLLiteral {
                        return try configuration.staticResultField(
                            String.self,
                            selecting: expression,
                            storedAs: storageType,
                            identifiedBy: identity,
                            using: dialect,
                            context: context,
                            selection: .explicit(Codecs.badge)
                        )
                  }
            }
            """,
            macros: makeCodecResultFieldsMemberTestMacros()
        )
    }
}
