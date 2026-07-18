//
//  SQLTests.swift
//  SwiftQL
//
//  Tests for the `SQLTable` and `SQLResult` macros: property classification, diagnostics for
//  unsupported property shapes, and expansion of the generated memberwise initializer.
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
    ]
}


///
/// Wrapper which exposes only the generated initializer so existing expansion tests stay focused
/// on that declaration.
///
private struct SQLTableInitializerMacro: MemberMacro {

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
            ).prefix(1)
        )
    }
}

private func makeMemberTestMacros() -> [String: Macro.Type] {
    [
        "SQLTable": SQLTableInitializerMacro.self,
    ]
}


/// Wrapper which isolates the generated projection factory for a focused regression test.
private struct SQLResultColumnsMemberMacro: MemberMacro {

    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        Array(
            try SQLResultMacro.expansion(
                of: node,
                providingMembersOf: declaration,
                in: context
            ).dropFirst().prefix(1)
        )
    }
}

private func makeColumnsMemberTestMacros() -> [String: Macro.Type] {
    [
        "SQLResult": SQLResultColumnsMemberMacro.self,
    ]
}


final class SQLMacroDiagnosticTests: XCTestCase {

    func test_missingTypeAnnotation_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var count = 0
            }
            """,
            expandedSource: """
            struct Sample {
                var count = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'count' needs an explicit type annotation to be used as a column. The type of the initial value cannot be inferred by the macro.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_computedProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var id: Int
                var display: String {
                    "sample"
                }
            }
            """,
            expandedSource: """
            struct Sample {
                var id: Int
                var display: String {
                    "sample"
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Computed properties cannot be used as columns. Move the property to an extension of the type to exclude it from the generated columns.",
                    line: 4,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_staticProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var id: Int
                static var shared: Int = 0
            }
            """,
            expandedSource: """
            struct Sample {
                var id: Int
                static var shared: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'static' properties cannot be used as columns. Move the property to an extension of the type to exclude it from the generated columns.",
                    line: 4,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_lazyProperty_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                lazy var value: Int = 0
            }
            """,
            expandedSource: """
            struct Sample {
                lazy var value: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'lazy' properties cannot be used as columns. Use a plain stored property instead.",
                    line: 3,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_letWithInitialValue_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                let id: Int = 0
            }
            """,
            expandedSource: """
            struct Sample {
                let id: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "A 'let' property with an initial value cannot be assigned by the generated initializer. Use 'var', or remove the initial value.",
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
            @SQLTable
            struct Sample {
                var (x, y): (Int, Int)
            }
            """,
            expandedSource: """
            struct Sample {
                var (x, y): (Int, Int)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Pattern '(x, y)' cannot be used as a column. Declare each column as a separate property with its own name and type.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_unsupportedColumnType_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var callback: (Int) -> Int
            }
            """,
            expandedSource: """
            struct Sample {
                var callback: (Int) -> Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Type '(Int) -> Int' cannot be used as a column type.",
                    line: 3,
                    column: 19
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_reservedPropertyName_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var _namespace: Int
            }
            """,
            expandedSource: """
            struct Sample {
                var _namespace: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property name '_namespace' conflicts with a member generated by the macro. Rename the property.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_interpolatedNameArgument_emitsError() {
        assertMacroExpansion(
            #"""
            @SQLTable(name: "tbl_\(1)")
            struct Sample {
                var id: Int
            }
            """#,
            expandedSource: """
            struct Sample {
                var id: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "The 'name' argument must be a simple string literal without interpolation. Remove the interpolation, or omit the argument to use the name of the struct.",
                    line: 1,
                    column: 17
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_nonStructDeclaration_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            class Sample {
            }
            """,
            expandedSource: """
            class Sample {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLTable' and '@SQLResult' can only be applied to a struct.",
                    line: 1,
                    column: 1
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_sqlResult_missingTypeAnnotation_emitsError() {
        assertMacroExpansion(
            """
            @SQLResult
            struct Sample {
                var count = 0
            }
            """,
            expandedSource: """
            struct Sample {
                var count = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'count' needs an explicit type annotation to be used as a column. The type of the initial value cannot be inferred by the macro.",
                    line: 3,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_multipleUnsupportedBindings_emitsErrorForEach() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var a = 0, b = 1
            }
            """,
            expandedSource: """
            struct Sample {
                var a = 0, b = 1
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'a' needs an explicit type annotation to be used as a column. The type of the initial value cannot be inferred by the macro.",
                    line: 3,
                    column: 9
                ),
                DiagnosticSpec(
                    message: "Property 'b' needs an explicit type annotation to be used as a column. The type of the initial value cannot be inferred by the macro.",
                    line: 3,
                    column: 16
                ),
            ],
            macros: makeTestMacros()
        )
    }

    func test_sharedUnsupportedTypeAnnotation_emitsSingleError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var a, b: (Int) -> Int
            }
            """,
            expandedSource: """
            struct Sample {
                var a, b: (Int) -> Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Type '(Int) -> Int' cannot be used as a column type.",
                    line: 3,
                    column: 15
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_multipleUnsupportedProperties_emitsErrorForEach() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var count = 0
                static var shared: Int = 0
            }
            """,
            expandedSource: """
            struct Sample {
                var count = 0
                static var shared: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property 'count' needs an explicit type annotation to be used as a column. The type of the initial value cannot be inferred by the macro.",
                    line: 3,
                    column: 9
                ),
                DiagnosticSpec(
                    message: "'static' properties cannot be used as columns. Move the property to an extension of the type to exclude it from the generated columns.",
                    line: 4,
                    column: 5
                ),
            ],
            macros: makeTestMacros()
        )
    }
}


final class SQLMacroExpansionTests: XCTestCase {

    func test_columnsIsGeneratedAsANominalMemberForSwift59Lookup() {
        assertMacroExpansion(
            """
            @SQLResult
            struct Projection {
                let id: Int
                let name: String?
            }
            """,
            expandedSource: """
            struct Projection {
                let id: Int
                let name: String?

                public static func columns(id: any SwiftQL.XLExpression<Int>, name: any SwiftQL.XLExpression<String?>) -> MetaResult {
                        return Self.makeSQLAnonymousResult(
                            namespace: XLNamespace.table(),
                            dependency: XLSelectResultDependency(),
                            iterator: Self.SQLReader(
                                id: id,
                                name: name
                            ).readRow
                        )
                  }
            }
            """,
            macros: makeColumnsMemberTestMacros()
        )
    }

    func test_memberwiseInitializer() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Person {
                var id: Int
                var name: String?
            }
            """,
            expandedSource: """
            struct Person {
                var id: Int
                var name: String?

                public init(id: Int, name: String?) {
                        self.id = id
                        self.name = name
                  }
            }
            """,
            macros: makeMemberTestMacros()
        )
    }

    func test_memberwiseInitializer_multipleBindings() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Point {
                var x: Int, y: String
            }
            """,
            expandedSource: """
            struct Point {
                var x: Int, y: String

                public init(x: Int, y: String) {
                        self.x = x
                        self.y = y
                  }
            }
            """,
            macros: makeMemberTestMacros()
        )
    }

    func test_memberwiseInitializer_backtickedName() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var `index`: Int
            }
            """,
            expandedSource: """
            struct Sample {
                var `index`: Int

                public init(`index`: Int) {
                        self.`index` = `index`
                  }
            }
            """,
            macros: makeMemberTestMacros()
        )
    }
}


final class MetaBuilderTests: XCTestCase {

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

    func test_multipleBindings_collectsEachProperty() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var x: Int, y: String
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 2)
        XCTAssertEqual(builder.properties[0].name, "x")
        XCTAssertEqual(builder.properties[0].type, "Int")
        XCTAssertEqual(builder.properties[1].name, "y")
        XCTAssertEqual(builder.properties[1].type, "String")
    }

    func test_sharedTypeAnnotation_appliesToAllBindings() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                let a, b: Int
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 2)
        XCTAssertEqual(builder.properties[0].name, "a")
        XCTAssertEqual(builder.properties[0].type, "Int")
        XCTAssertEqual(builder.properties[0].mutability, .immutable)
        XCTAssertEqual(builder.properties[1].name, "b")
        XCTAssertEqual(builder.properties[1].type, "Int")
    }

    func test_optionalSugar_isEquivalentToOptionalType() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var a: Optional<Int>
                var b: Int?
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 2)
        XCTAssertEqual(builder.properties[0].type, "Int")
        XCTAssertTrue(builder.properties[0].optional)
        XCTAssertEqual(builder.properties[0].qualifiedType, "Int?")
        XCTAssertEqual(builder.properties[1].type, "Int")
        XCTAssertTrue(builder.properties[1].optional)
    }

    func test_genericType_keepsGenericArguments() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var a: Array<Int>
                var b: [Int]
                var c: Optional<Array<Int>>
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 3)
        XCTAssertEqual(builder.properties[0].type, "Array<Int>")
        XCTAssertFalse(builder.properties[0].optional)
        XCTAssertEqual(builder.properties[1].type, "[Int]")
        XCTAssertEqual(builder.properties[2].type, "Array<Int>")
        XCTAssertTrue(builder.properties[2].optional)
    }

    func test_memberType_keepsQualifiedName() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var date: Foundation.Date
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 1)
        XCTAssertEqual(builder.properties[0].type, "Foundation.Date")
    }

    func test_qualifiedOptionalSugar_isEquivalentToOptionalType() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var value: Swift.Optional<Int>
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 1)
        XCTAssertEqual(builder.properties[0].type, "Int")
        XCTAssertTrue(builder.properties[0].optional)
        XCTAssertEqual(builder.properties[0].qualifiedType, "Int?")
    }

    func test_backtickedName_stripsBackticksFromColumnName() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var `index`: Int
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 1)
        XCTAssertEqual(builder.properties[0].name, "`index`")
        XCTAssertEqual(builder.properties[0].alias, "index")
        // The generated SQL never contains a backtick.
        XCTAssertFalse(builder.makeMetaTableExtension().contains("\"`"))
        XCTAssertTrue(builder.makeMetaTableExtension().contains("XLName(\"index\")"))
    }

    func test_varWithDefaultValue_isSupported() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var count: Int = 0
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 1)
        XCTAssertEqual(builder.properties[0].name, "count")
        XCTAssertEqual(builder.properties[0].type, "Int")
    }

    func test_propertyObservers_areSupported() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var count: Int {
                    didSet {
                        print(count)
                    }
                }
            }
            """
        )
        XCTAssertEqual(builder.properties.count, 1)
        XCTAssertEqual(builder.properties[0].name, "count")
    }

    func test_nonPropertyMembers_areNotColumns() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var id: Int
                func compute() -> Int {
                    0
                }
                init(id: Int) {
                    self.id = id
                }
                struct Nested {
                }
            }
            """
        )
        XCTAssertEqual(builder.properties.map(\.name), ["id"])
    }

    func test_computedBindingInMultiBindingDeclaration_reportsEveryProblem() throws {
        // A declaration which mixes a computed binding with another invalid binding reports a
        // diagnostic for each binding instead of stopping at the first.
        XCTAssertThrowsError(
            try makeBuilder(
                """
                @SQLTable
                struct Sample {
                    var a: Int {
                        0
                    }, b = 1
                }
                """
            )
        ) { error in
            guard let diagnosticsError = error as? DiagnosticsError else {
                return XCTFail("Expected DiagnosticsError, got \(error)")
            }
            let messages = diagnosticsError.diagnostics.map(\.message)
            XCTAssertEqual(messages.count, 2)
            XCTAssertTrue(messages[0].contains("Computed properties cannot be used as columns"))
            XCTAssertTrue(messages[1].contains("Property 'b' needs an explicit type annotation"))
        }
    }

    func test_nameArgument_isUsedAsTableName() throws {
        let builder = try makeBuilder(
            """
            @SQLTable(name: "custom_table")
            struct Sample {
                var id: Int
            }
            """
        )
        XCTAssertEqual(builder.tableName, "custom_table")
    }

    func test_noNameArgument_usesStructName() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var id: Int
            }
            """
        )
        XCTAssertEqual(builder.tableName, "Sample")
    }

    func test_emptyStruct_generatesSingleParameterlessInitializerPerType() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
            }
            """
        )
        let source = builder.makeMetaTableExtension()
        // MetaInsert, MetaUpdate and UpdateRequest each declare exactly one parameterless
        // initializer. Before the fix, MetaUpdate declared a duplicate `init()`.
        let count = source.components(separatedBy: "public init()").count - 1
        XCTAssertEqual(count, 3)
    }

    func test_columnsBuildsResultWithoutDeprecatedHelper() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct Projection {
                let id: String
                let result: Int
            }
            """
        )
        let source = builder.makeColumnsFunction()
        let extensionSource = builder.makeMetaResultExtension(table: false)

        XCTAssertTrue(source.contains("public static func columns(id: any SwiftQL.XLExpression<String>, result: any SwiftQL.XLExpression<Int>) -> MetaResult"))
        XCTAssertTrue(source.contains("return Self.makeSQLAnonymousResult("))
        XCTAssertTrue(source.contains("namespace: XLNamespace.table(),"))
        XCTAssertTrue(source.contains("dependency: XLSelectResultDependency(),"))
        XCTAssertTrue(source.contains("iterator: Self.SQLReader("))
        XCTAssertTrue(source.contains("id: id,"))
        XCTAssertTrue(source.contains("result: result"))
        XCTAssertTrue(source.contains(").readRow"))
        XCTAssertFalse(source.contains("result {"))
        XCTAssertFalse(extensionSource.contains("static func columns"))
    }

    func test_emptyResultColumnsGenerationIsValid() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct Projection {
            }
            """
        )
        let source = builder.makeColumnsFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("public static func columns() -> MetaResult"))
        XCTAssertTrue(source.contains("iterator: Self.SQLReader("))
        XCTAssertTrue(source.contains(").readRow"))
    }

    func test_staticRowLayoutGenerationCoversTypedOptionalQualifiedGenericAndBacktickedFields() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct Projection<Element> {
                let `switch`: Swift.Optional<Element>
                let values: Array<Element>
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("public static func staticRowLayout<_SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("some SwiftQL.XLStaticSelectFieldProtocol<Element?, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("some SwiftQL.XLStaticSelectFieldProtocol<Array<Element>, _SwiftQLStaticDialect>"))
        XCTAssertFalse(source.contains("_SwiftQLStaticStorage"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = `switch`.positioned(at: 0, alias: \"switch\")"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = values.positioned(at: 1, alias: \"values\")"))
        XCTAssertTrue(source.contains("try _swiftQLStaticField0.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(source.contains("try _swiftQLStaticField1.encode(_swiftQLStaticRow.values)"))
        XCTAssertTrue(source.contains("try _swiftQLStaticField0.erased()"))
    }

    func test_staticRowLayoutGenerationAvoidsReaderAndRowPropertyCollisions() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct Projection {
                let reader: String
                let row: Int
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()
        let metaSource = builder.makeMetaResultExtension(table: false)

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = reader.positioned"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = row.positioned"))
        XCTAssertTrue(source.contains("decode: { _swiftQLStaticReader in"))
        XCTAssertTrue(source.contains("reader: try _swiftQLStaticField0.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(source.contains("encode: { _swiftQLStaticRow in"))
        XCTAssertTrue(source.contains("try _swiftQLStaticField1.encode(_swiftQLStaticRow.row)"))
        XCTAssertFalse(source.contains("decode: { reader in"))
        XCTAssertFalse(source.contains("encode: { row in"))
        XCTAssertTrue(metaSource.contains("readRow(reader _swiftQLRowReader: XLRowReader)"))
        XCTAssertTrue(metaSource.contains("reader: try _swiftQLRowReader.staticColumn(reader"))
        XCTAssertTrue(metaSource.contains("row: try _swiftQLRowReader.staticColumn(row"))
    }

    func test_staticRowLayoutGenerationAllocatesCollisionFreeIdentifiers() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct Projection<
                Dialect,
                _SwiftQLStaticDialect,
                _SwiftQLStaticStorage0
            > {
                let dialect: Dialect
                let staticDialect: _SwiftQLStaticDialect
                let storage: _SwiftQLStaticStorage0
                let _swiftQLStaticField0: String
                let _swiftQLStaticReader: String
                let _swiftQLStaticRow: String
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("staticRowLayout<_SwiftQLStaticDialect_1>"))
        XCTAssertTrue(source.contains("XLStaticSelectFieldProtocol<Dialect, _SwiftQLStaticDialect_1>"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0_1 = dialect.positioned"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField3 = _swiftQLStaticField0.positioned"))
        XCTAssertTrue(source.contains("decode: { _swiftQLStaticReader_1 in"))
        XCTAssertTrue(source.contains("encode: { _swiftQLStaticRow_1 in"))
        XCTAssertFalse(source.contains("staticRowLayout<Dialect>"))
    }

    func test_generatedAllocatorsReserveNominalAndPropertyTypeIdentifiers() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct _swiftQLRowReader {
                let direct: _SwiftQLStaticDialect
                let nested: Box<Array<_SwiftQLStaticDialect?>>
            }
            """
        )
        let staticSource = builder.makeStaticRowLayoutFunction()
        let metaSource = builder.makeMetaResultExtension(table: false)

        XCTAssertFalse(Parser.parse(source: staticSource).hasError)
        XCTAssertTrue(
            staticSource.contains(
                "staticRowLayout<_SwiftQLStaticDialect_1>"
            )
        )
        XCTAssertTrue(
            staticSource.contains(
                "XLStaticSelectFieldProtocol<_SwiftQLStaticDialect, _SwiftQLStaticDialect_1>"
            )
        )
        XCTAssertTrue(
            staticSource.contains(
                "XLStaticSelectFieldProtocol<Box<Array<_SwiftQLStaticDialect?>>, _SwiftQLStaticDialect_1>"
            )
        )
        XCTAssertTrue(
            metaSource.contains(
                "readRow(reader _swiftQLRowReader_1: XLRowReader) throws -> _swiftQLRowReader"
            )
        )
    }

    func test_emptyStaticRowLayoutGenerationDefersInitializerToDecodeClosure() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct EmptyProjection {
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("fields: ["))
        XCTAssertTrue(source.contains("decode: { _swiftQLStaticReader in"))
        XCTAssertTrue(source.contains("Self"))
        XCTAssertTrue(source.contains("encode: { _swiftQLStaticRow in"))
        XCTAssertFalse(source.contains("sqlDefault"))
        XCTAssertFalse(source.contains("SQLReader"))
    }

    func test_immutableTableUpdateRequestAvoidsUnusedTemporaries() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct ImmutableRow {
                let id: Int
            }
            """
        )
        let source = builder.makeMetaTableExtension()

        XCTAssertTrue(source.contains("public func apply(to entity: Row) -> Row"))
        XCTAssertTrue(source.contains("return entity"))
        XCTAssertTrue(source.contains("public func makeUpdate() -> MetaUpdate"))
        XCTAssertTrue(source.contains("return MetaUpdate()"))
        XCTAssertFalse(source.contains("var output = entity"))
        XCTAssertFalse(source.contains("var output = MetaUpdate()"))
    }

    func test_mutableTableUpdateRequestStillAppliesValues() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct MutableRow {
                var id: Int
            }
            """
        )
        let source = builder.makeMetaTableExtension()

        XCTAssertTrue(source.contains("var output = entity"))
        XCTAssertTrue(source.contains("output.id = value"))
        XCTAssertTrue(source.contains("var output = MetaUpdate()"))
        XCTAssertTrue(source.contains("output.id = SwiftQL._xlLegacyValueExpression(value)"))
    }
}
