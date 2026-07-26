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
                    message: "Type '(Int) -> Int' cannot be used as a column type. Use a named type that conforms to 'XLLiteral' for a scalar column, or a nested '@SQLTable'/'@SQLResult' type for a composite column selection.",
                    line: 3,
                    column: 19
                )
            ],
            macros: makeTestMacros()
        )
    }

    // A property type the macro cannot resolve as either a scalar `XLLiteral`
    // column or a nested `@SQLTable`/`@SQLResult` composite (here, a tuple
    // type -- the shape someone reaching for issue #6's composite selection
    // might mistakenly try) is rejected at expansion time with a message
    // naming both supported shapes, rather than compiling into generated
    // code that only fails downstream with an opaque protocol-conformance
    // error.
    func test_unresolvableAsScalarOrComposite_emitsActionableDiagnostic() {
        assertMacroExpansion(
            """
            @SQLResult
            struct EmployeeCompany {
                let pair: (Employee, Company)
            }
            """,
            expandedSource: """
            struct EmployeeCompany {
                let pair: (Employee, Company)
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Type '(Employee, Company)' cannot be used as a column type. Use a named type that conforms to 'XLLiteral' for a scalar column, or a nested '@SQLTable'/'@SQLResult' type for a composite column selection.",
                    line: 3,
                    column: 15
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
                    message: "Type '(Int) -> Int' cannot be used as a column type. Use a named type that conforms to 'XLLiteral' for a scalar column, or a nested '@SQLTable'/'@SQLResult' type for a composite column selection.",
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

    // MARK: - #256 regression corpus: additional malformed shapes and
    // reserved-name collisions
    //
    // Case shapes below are inspired by the kind of awkward declarations
    // mature Swift code-generation test suites (e.g. `@Observable`/`Codable`
    // synthesis, popular SQLite/ORM macro libraries) commonly exercise --
    // doubly-wrapped optionals, and every one of the macro's own reserved
    // generated-member names, not only one representative. No upstream code
    // is copied; only the shape of the case is adapted. See
    // `MacroRegressionCorpus.json` (case IDs `macro.malformed.double-
    // optional-column-type` and `macro.reserved-names.*`) for the
    // provenance record.

    // A doubly-wrapped optional (`Int??`) is a shape a plain `T?` property
    // could plausibly be mistyped as, and is a case mature codegen test
    // suites (e.g. Codable synthesis) commonly probe. `resolveColumnType`
    // only unwraps one level of `Optional`, so this is rejected with the
    // same actionable diagnostic as any other type it cannot resolve as a
    // scalar or composite column, rather than silently double-unwrapping or
    // producing a confusing generic-substitution failure downstream.
    func test_doublyWrappedOptionalColumnType_emitsError() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var count: Int??
            }
            """,
            expandedSource: """
            struct Sample {
                var count: Int??
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Type 'Int??' cannot be used as a column type. Use a named type that conforms to 'XLLiteral' for a scalar column, or a nested '@SQLTable'/'@SQLResult' type for a composite column selection.",
                    line: 3,
                    column: 16
                )
            ],
            macros: makeTestMacros()
        )
    }

    // `_namespace` is only one of several property names the macro reserves
    // for its own generated members (see `MetaBuilder.reservedPropertyNames`
    // and the nominal `Nullable`/`Row`/`RowIterator`/`Dependency`/`Basis`
    // types every expansion declares). Every reserved name must be reported,
    // not only the first one covered by `test_reservedPropertyName_emitsError`
    // above, so a future change that narrows the check to a single literal
    // name would be caught here.
    func test_everyReservedPropertyName_emitsErrorForEach() {
        assertMacroExpansion(
            """
            @SQLResult
            struct Sample {
                var Row: Int
                var RowIterator: Int
                var Dependency: Int
                var Basis: Int
                var Nullable: Int
            }
            """,
            expandedSource: """
            struct Sample {
                var Row: Int
                var RowIterator: Int
                var Dependency: Int
                var Basis: Int
                var Nullable: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Property name 'Row' conflicts with a member generated by the macro. Rename the property.",
                    line: 3,
                    column: 9
                ),
                DiagnosticSpec(
                    message: "Property name 'RowIterator' conflicts with a member generated by the macro. Rename the property.",
                    line: 4,
                    column: 9
                ),
                DiagnosticSpec(
                    message: "Property name 'Dependency' conflicts with a member generated by the macro. Rename the property.",
                    line: 5,
                    column: 9
                ),
                DiagnosticSpec(
                    message: "Property name 'Basis' conflicts with a member generated by the macro. Rename the property.",
                    line: 6,
                    column: 9
                ),
                DiagnosticSpec(
                    message: "Property name 'Nullable' conflicts with a member generated by the macro. Rename the property.",
                    line: 7,
                    column: 9
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

    // MARK: - #256 regression corpus: identifier shapes
    //
    // See `MacroRegressionCorpus.json` for the provenance record backing
    // each case below. Case shapes are inspired by the kind of awkward
    // identifiers mature Swift code-generation test suites commonly probe
    // (Unicode identifiers, and Swift-legal names that collide with SQL
    // keywords); no code is copied from any upstream source.

    // A property name using non-ASCII Unicode letters is a legal Swift
    // identifier and requires no special handling: the macro treats every
    // property name as an opaque token copied verbatim into the generated
    // initializer and SQL alias, so a Unicode name exercises exactly the
    // same code path as an ASCII one. This pins that no ASCII-only
    // assumption (e.g. accidental byte-length or ASCII-range validation)
    // has crept into name handling.
    func test_memberwiseInitializer_unicodePropertyName() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var café: String
                var 名前: String
            }
            """,
            expandedSource: """
            struct Sample {
                var café: String
                var 名前: String

                public init(café: String, 名前: String) {
                        self.café = café
                        self.名前 = 名前
                  }
            }
            """,
            macros: makeMemberTestMacros()
        )
    }

    // `order`, `group`, and `select` are reserved words in SQL but ordinary,
    // unreserved identifiers in Swift, so they need no backtick escaping as
    // property names. Every SQL identifier SwiftQL renders is always
    // double-quoted (`XLSQLiteDialect.formatIdentifier`), so these are never
    // actually ambiguous at the SQL level either; this test only pins that
    // the macro does not mistakenly require (or reject) backticks for a
    // Swift-legal name just because it reads like a SQL keyword.
    func test_memberwiseInitializer_sqlKeywordLikePropertyNames() {
        assertMacroExpansion(
            """
            @SQLTable
            struct Sample {
                var order: Int
                var group: String
                var select: Bool
            }
            """,
            expandedSource: """
            struct Sample {
                var order: Int
                var group: String
                var select: Bool

                public init(order: Int, group: String, select: Bool) {
                        self.order = order
                        self.group = group
                        self.select = select
                  }
            }
            """,
            macros: makeMemberTestMacros()
        )
    }

    // Explicit access-control modifiers (`public`, `private`, `fileprivate`)
    // on individual stored properties are not among the modifiers
    // `MetaBuilder` inspects (only `static`/`class`, `lazy`, and
    // `weak`/`unowned` affect column classification), so a property keeps
    // its own declared visibility and still becomes a column. This pins
    // that mixing access levels within one declaration does not trip a
    // false-positive diagnostic or silently drop a property from the
    // generated initializer.
    func test_memberwiseInitializer_explicitAccessControlModifiersAreIgnored() {
        assertMacroExpansion(
            """
            @SQLTable
            public struct Sample {
                public var id: Int
                private var secret: String
                fileprivate var note: String
            }
            """,
            expandedSource: """
            public struct Sample {
                public var id: Int
                private var secret: String
                fileprivate var note: String

                public init(id: Int, secret: String, note: String) {
                        self.id = id
                        self.secret = secret
                        self.note = note
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
        XCTAssertTrue(source.contains("some SwiftQL.XLStaticRowFieldSource<Element?, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("some SwiftQL.XLStaticRowFieldSource<Array<Element>, _SwiftQLStaticDialect>"))
        XCTAssertFalse(source.contains("_SwiftQLStaticStorage"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = try `switch`.grouped(at: 0, alias: \"switch\")"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = try values.grouped(at: _swiftQLStaticOffset, alias: \"values\")"))
        XCTAssertTrue(source.contains("try _swiftQLStaticField0.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(
            source.contains(
                "try [_swiftQLStaticField0.encode(_swiftQLStaticRow.`switch`), _swiftQLStaticField1.encode(_swiftQLStaticRow.values)].flatMap { $0 }"
            )
        )
        XCTAssertTrue(source.contains("fields: [_swiftQLStaticField0.fields, _swiftQLStaticField1.fields].flatMap { $0 },"))
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
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = try reader.grouped"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = try row.grouped"))
        XCTAssertTrue(source.contains("decode: { _swiftQLStaticReader in"))
        XCTAssertTrue(source.contains("reader: try _swiftQLStaticField0.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(source.contains("encode: { _swiftQLStaticRow in"))
        XCTAssertTrue(
            source.contains(
                "try [_swiftQLStaticField0.encode(_swiftQLStaticRow.reader), _swiftQLStaticField1.encode(_swiftQLStaticRow.row)].flatMap { $0 }"
            )
        )
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
        XCTAssertTrue(source.contains("XLStaticRowFieldSource<Dialect, _SwiftQLStaticDialect_1>"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0_1 = try dialect.grouped"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField3 = try _swiftQLStaticField0.grouped"))
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
                "XLStaticRowFieldSource<_SwiftQLStaticDialect, _SwiftQLStaticDialect_1>"
            )
        )
        XCTAssertTrue(
            staticSource.contains(
                "XLStaticRowFieldSource<Box<Array<_SwiftQLStaticDialect?>>, _SwiftQLStaticDialect_1>"
            )
        )
        XCTAssertTrue(
            metaSource.contains(
                "readRow(reader _swiftQLRowReader_1: XLRowReader) throws -> _swiftQLRowReader"
            )
        )
    }

    // MARK: - Composite (nested `@SQLTable`/`@SQLResult`) properties
    //
    // A stored property whose type is itself a generated `@SQLTable`/
    // `@SQLResult` type is, from `MetaBuilder`'s point of view, syntactically
    // indistinguishable from any other nominal-type property: the macro has
    // no semantic access to the property type's own declaration (it may not
    // even be in the same file), so it cannot tell "nested composite" apart
    // from "scalar `XLLiteral`" at expansion time. Composite support is
    // therefore uniform code generation, not macro-side detection: every
    // property -- scalar or composite -- goes through the same
    // `some SwiftQL.XLStaticRowFieldSource<Type, Dialect>` parameter and the
    // same `.grouped(at:alias:)` / running-offset accumulation. Whether a
    // given call site actually supplies a scalar field or a nested
    // `XLStaticRowLayout` is resolved later, by Swift's own conformance
    // checking. These tests pin the exact generated shape for the
    // property-count patterns issue #6 calls out; `StaticRowLayoutGRDBTests`
    // exercises the same generated code with a real nested composite value
    // and a real SQLite database.

    func test_staticRowLayoutGeneration_singleCompositeProperty() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct EmployeeOnly {
                let employee: Employee
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("some SwiftQL.XLStaticRowFieldSource<Employee, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = try employee.grouped(at: 0, alias: \"employee\")"))
        XCTAssertFalse(source.contains("_swiftQLStaticOffset"))
        XCTAssertTrue(source.contains("fields: [_swiftQLStaticField0.fields].flatMap { $0 },"))
        XCTAssertTrue(source.contains("employee: try _swiftQLStaticField0.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(source.contains("encode: { _swiftQLStaticRow in"))
        XCTAssertTrue(source.contains("try _swiftQLStaticField0.encode(_swiftQLStaticRow.employee)"))
    }

    func test_staticRowLayoutGeneration_multipleCompositeProperties() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct EmployeeCompany {
                let employee: Employee
                let company: Company
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("employee: some SwiftQL.XLStaticRowFieldSource<Employee, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("company: some SwiftQL.XLStaticRowFieldSource<Company, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = try employee.grouped(at: 0, alias: \"employee\")"))
        XCTAssertTrue(source.contains("_swiftQLStaticOffset = _swiftQLStaticField0.count"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = try company.grouped(at: _swiftQLStaticOffset, alias: \"company\")"))
        XCTAssertTrue(source.contains("fields: [_swiftQLStaticField0.fields, _swiftQLStaticField1.fields].flatMap { $0 },"))
        XCTAssertTrue(source.contains("employee: try _swiftQLStaticField0.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(source.contains("company: try _swiftQLStaticField1.read(from: _swiftQLStaticReader)"))
        XCTAssertTrue(
            source.contains(
                "try [_swiftQLStaticField0.encode(_swiftQLStaticRow.employee), _swiftQLStaticField1.encode(_swiftQLStaticRow.company)].flatMap { $0 }"
            )
        )
    }

    func test_staticRowLayoutGeneration_mixOfScalarAndCompositeProperties() throws {
        let builder = try makeBuilder(
            """
            @SQLResult
            struct EmployeeWithBadge {
                let badgeNumber: Int
                let employee: Employee
                let company: Company
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        // Every property -- scalar or composite -- gets the identical
        // parameter shape; there is no macro-side branch between them.
        XCTAssertTrue(source.contains("badgeNumber: some SwiftQL.XLStaticRowFieldSource<Int, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("employee: some SwiftQL.XLStaticRowFieldSource<Employee, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("company: some SwiftQL.XLStaticRowFieldSource<Company, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = try badgeNumber.grouped(at: 0, alias: \"badgeNumber\")"))
        // A third property means the running offset is genuinely
        // reassigned, so it is generated as `var`.
        XCTAssertTrue(source.contains("var _swiftQLStaticOffset = _swiftQLStaticField0.count"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = try employee.grouped(at: _swiftQLStaticOffset, alias: \"employee\")"))
        XCTAssertTrue(source.contains("_swiftQLStaticOffset += _swiftQLStaticField1.count"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField2 = try company.grouped(at: _swiftQLStaticOffset, alias: \"company\")"))
        XCTAssertTrue(
            source.contains(
                "fields: [_swiftQLStaticField0.fields, _swiftQLStaticField1.fields, _swiftQLStaticField2.fields].flatMap { $0 },"
            )
        )
    }

    func test_staticRowLayoutGeneration_nestedInsideNestedComposite() throws {
        // `Department` is itself a composite result nesting `Employee` and
        // `Company` (mirroring `EmployeeCompany` above); `DepartmentReport`
        // then nests `Department` a further level deep alongside a scalar
        // property. `MetaBuilder` only ever sees `DepartmentReport`'s own
        // declared properties, so the generated code is identical in shape
        // to any other single-composite-plus-scalar case -- depth is
        // handled entirely by `XLStaticRowLayout.grouped(at:alias:)`
        // recursing through however many nested layouts are passed to it at
        // the call site, not by anything the macro generates differently
        // here. `StaticRowLayoutGRDBTests` proves the recursive flattening
        // actually works end to end against a real database.
        let builder = try makeBuilder(
            """
            @SQLResult
            struct DepartmentReport {
                let headcount: Int
                let department: Department
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertTrue(source.contains("headcount: some SwiftQL.XLStaticRowFieldSource<Int, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("department: some SwiftQL.XLStaticRowFieldSource<Department, _SwiftQLStaticDialect>"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField0 = try headcount.grouped(at: 0, alias: \"headcount\")"))
        XCTAssertTrue(source.contains("let _swiftQLStaticField1 = try department.grouped(at: _swiftQLStaticOffset, alias: \"department\")"))
        XCTAssertTrue(source.contains("fields: [_swiftQLStaticField0.fields, _swiftQLStaticField1.fields].flatMap { $0 },"))
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

    // MARK: - #256 regression corpus: builder-level shape checks
    //
    // See `MacroRegressionCorpus.json` for the provenance record backing
    // each case below.

    // A backticked Swift-reserved keyword must have its backticks stripped
    // from every generated *SQL* alias, not only the memberwise initializer
    // covered by `test_memberwiseInitializer_backtickedName` above -- the
    // full `@SQLTable` extension declares several independent generated
    // members (`MetaWritableTable`, `MetaInsert`, `MetaUpdate`, `SQLReader`,
    // `MetaCreate`) that each re-derive their own column name from the same
    // property, so a regression that only fixed one of them would still
    // ship a `"class"` column at the SQL level.
    func test_metaTableExtension_backtickedReservedKeywordStripsBackticksAcrossEveryGeneratedMember() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var `class`: Int
            }
            """
        )
        let source = builder.makeMetaTableExtension()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        // MetaInsert / MetaUpdate / SQLReader-facing column name literal.
        XCTAssertTrue(source.contains("XLName(\"class\")"))
        // MetaCreate's rendered column definition.
        XCTAssertTrue(source.contains("column(name: XLName(\"class\"), nullable: false)"))
        // The Swift-side property name keeps its backticks everywhere it is
        // referenced as an identifier.
        XCTAssertTrue(source.contains("`class`"))
        XCTAssertFalse(source.contains("XLName(\"`class`\")"))
    }

    // A struct member that is never a column at all -- a subscript, a
    // nested type declaration, and an ordinary method -- must be silently
    // skipped rather than diagnosed or accidentally collected, alongside one
    // genuine stored property. `collectProperties` only iterates
    // `VariableDeclSyntax` members, so this pins that the filter continues
    // to hold as the struct grows other kinds of members.
    func test_nonPropertyMembersAreIgnoredNotCollectedAsColumns() throws {
        let builder = try makeBuilder(
            """
            @SQLTable
            struct Sample {
                var id: Int

                subscript(index: Int) -> Int { index }

                struct Nested {
                    var value: Int
                }

                func describe() -> String { "sample" }
            }
            """
        )

        XCTAssertEqual(builder.properties.count, 1)
        XCTAssertEqual(builder.properties[0].name, "id")
    }

    // A wide row (more properties than any existing fixture) exercises the
    // running-offset accumulation in `makeStaticRowLayoutFunction()` at a
    // scale closer to a real denormalized table than the two- and
    // three-property cases already covered by the composite-property tests
    // above, and pins that every property -- not just the first and last --
    // is threaded through `fields`, `decode`, and `encode`.
    func test_staticRowLayoutGeneration_manyStoredPropertiesAccumulateSequentialOffsets() throws {
        let propertyCount = 12
        let declarations = (0..<propertyCount).map { "    var field\($0): Int" }.joined(separator: "\n")
        let builder = try makeBuilder(
            """
            @SQLResult
            struct WideRow {
            \(declarations)
            }
            """
        )
        let source = builder.makeStaticRowLayoutFunction()

        XCTAssertFalse(Parser.parse(source: source).hasError)
        XCTAssertEqual(builder.properties.count, propertyCount)
        for index in 0..<propertyCount {
            XCTAssertTrue(
                source.contains("field\(index): some SwiftQL.XLStaticRowFieldSource<Int, _SwiftQLStaticDialect>"),
                "missing parameter for field\(index)"
            )
            XCTAssertTrue(
                source.contains("field\(index): try _swiftQLStaticField\(index).read(from: _swiftQLStaticReader)"),
                "missing decode line for field\(index)"
            )
        }
        // The offset is reassigned for every property after the first, so
        // it must be a `var`, and every field group after the first
        // contributes to it.
        XCTAssertTrue(source.contains("var _swiftQLStaticOffset = _swiftQLStaticField0.count"))
        for index in 1..<(propertyCount - 1) {
            XCTAssertTrue(
                source.contains("_swiftQLStaticOffset += _swiftQLStaticField\(index).count"),
                "missing offset accumulation after field\(index)"
            )
        }
        let expectedFieldsExpression = (0..<propertyCount)
            .map { "_swiftQLStaticField\($0).fields" }
            .joined(separator: ", ")
        XCTAssertTrue(source.contains("fields: [\(expectedFieldsExpression)].flatMap { $0 },"))
    }
}
