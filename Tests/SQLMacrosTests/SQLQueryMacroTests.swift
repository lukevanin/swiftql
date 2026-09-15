//
//  SQLQueryMacroTests.swift
//  SwiftQL
//
//  Tests for the `@SQLQuery` peer macro (issues #18/#26): signature-driven
//  body rewriting, executor generation, and diagnostics for unsupported
//  declaration shapes. Ported from the milestone #28 spike on
//  `experiment/sqlquery-peer-macro`, extended with the `.exactlyOne`
//  cardinality added for v1.5.1.
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
        "SQLQuery": SQLQueryMacro.self,
    ]
}


final class SQLQueryMacroExpansionTests: XCTestCase {

    func test_oneParameter_rewritesReferenceAndGeneratesExecutor() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }

                func personByNameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name"))
                    }
                }

                private static let __xlPersonByNameCache = XLRenderOnceCache<Person>()

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func preparePersonByName(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_twoParameters_rewritesEveryReferenceWithItsOwnType() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                public func peopleInCohort(name: String, minimumAge: Int) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name && person.age >= minimumAge)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                public func peopleInCohort(name: String, minimumAge: Int) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name && person.age >= minimumAge)
                    }
                }

                public func peopleInCohortStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name") && person.age >= XLNamedBindingReference<Int>(name: "minimumAge"))
                    }
                }

                private static let __xlPeopleInCohortCache = XLRenderOnceCache<Person>()

                public func fetchPeopleInCohort(name: String, minimumAge: Int) throws -> [Person] {
                    let __xlRequest = Self.__xlPeopleInCohortCache.request(for: self) {
                        peopleInCohortStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                            try _xlQueryParameterBinding(minimumAge, named: "minimumAge", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                public func preparePeopleInCohort(name: String, minimumAge: Int) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPeopleInCohortCache.request(for: self) {
                        peopleInCohortStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                            try _xlQueryParameterBinding(minimumAge, named: "minimumAge", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_optionalParameter_bindsThroughOptionalReference() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func peopleByNickname(nickname: String?) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.nickname == nickname)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func peopleByNickname(nickname: String?) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.nickname == nickname)
                    }
                }

                func peopleByNicknameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.nickname == XLNamedBindingReference<String?>(name: "nickname"))
                    }
                }

                private static let __xlPeopleByNicknameCache = XLRenderOnceCache<Person>()

                func fetchPeopleByNickname(nickname: String?) throws -> [Person] {
                    let __xlRequest = Self.__xlPeopleByNicknameCache.request(for: self) {
                        peopleByNicknameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(nickname, named: "nickname", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func preparePeopleByNickname(nickname: String?) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPeopleByNicknameCache.request(for: self) {
                        peopleByNicknameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(nickname, named: "nickname", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_memberNameMatchingParameterName_isNotRewritten() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name && name == person.name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name && name == person.name)
                    }
                }

                func personByNameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name") && XLNamedBindingReference<String>(name: "name") == person.name)
                    }
                }

                private static let __xlPersonByNameCache = XLRenderOnceCache<Person>()

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func preparePersonByName(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_backtickedParameter_stripsEscapingFromPlaceholderName() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func rowsForKind(`class`: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.kind == `class`)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func rowsForKind(`class`: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.kind == `class`)
                    }
                }

                func rowsForKindStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.kind == XLNamedBindingReference<String>(name: "class"))
                    }
                }

                private static let __xlRowsForKindCache = XLRenderOnceCache<Person>()

                func fetchRowsForKind(`class`: String) throws -> [Person] {
                    let __xlRequest = Self.__xlRowsForKindCache.request(for: self) {
                        rowsForKindStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(`class`, named: "class", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func prepareRowsForKind(`class`: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlRowsForKindCache.request(for: self) {
                        rowsForKindStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(`class`, named: "class", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    func test_zeroParameters_generatesEmptyPacketExecutor() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func allPeople() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func allPeople() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }

                func allPeopleStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }

                private static let __xlAllPeopleCache = XLRenderOnceCache<Person>()

                func fetchAllPeople() throws -> [Person] {
                    let __xlRequest = Self.__xlAllPeopleCache.request(for: self) {
                        allPeopleStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func prepareAllPeople() throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlAllPeopleCache.request(for: self) {
                        allPeopleStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    // MARK: - Direct-result signatures + return-shape dispatch

    ///
    /// A `[Row]` direct-result signature (no `XLQueryStatement` boilerplate)
    /// dispatches to `fetchAll`. The spec calls the trapping `sqlResult` entry
    /// point; the generated statement builder swaps it for the real `sql`
    /// builder and declares the value-free `any XLQueryStatement<Row>` result.
    ///
    func test_directResultArray_dispatchesFetchAll() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }

                func personByNameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name"))
                    }
                }

                private static let __xlPersonByNameCache = XLRenderOnceCache<Person>()

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func preparePersonByName(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    ///
    /// Issue #661: a parameter passed to a DSL matching method (`like`,
    /// `regexp`) or to a clause (`Limit`) is rewritten to its named binding
    /// like a comparison operand. The callees themselves — `Where`, `Limit`,
    /// and the member names `like` and `regexp` — are left unchanged, and a
    /// parameter called `limit` does not collide with the `Limit` clause.
    ///
    func test_matchingMethodAndClauseArguments_rewriteToNamedBindings() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func peopleMatching(pattern: String, expression: String, limit: Int) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name.like(pattern) || person.notes.regexp(expression))
                        Limit(limit)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func peopleMatching(pattern: String, expression: String, limit: Int) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name.like(pattern) || person.notes.regexp(expression))
                        Limit(limit)
                    }
                }

                func peopleMatchingStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name.like(XLNamedBindingReference<String>(name: "pattern")) || person.notes.regexp(XLNamedBindingReference<String>(name: "expression")))
                        Limit(XLNamedBindingReference<Int>(name: "limit"))
                    }
                }

                private static let __xlPeopleMatchingCache = XLRenderOnceCache<Person>()

                func fetchPeopleMatching(pattern: String, expression: String, limit: Int) throws -> [Person] {
                    let __xlRequest = Self.__xlPeopleMatchingCache.request(for: self) {
                        peopleMatchingStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(pattern, named: "pattern", in: __xlLayout),
                            try _xlQueryParameterBinding(expression, named: "expression", in: __xlLayout),
                            try _xlQueryParameterBinding(limit, named: "limit", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func preparePeopleMatching(pattern: String, expression: String, limit: Int) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPeopleMatchingCache.request(for: self) {
                        peopleMatchingStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(pattern, named: "pattern", in: __xlLayout),
                            try _xlQueryParameterBinding(expression, named: "expression", in: __xlLayout),
                            try _xlQueryParameterBinding(limit, named: "limit", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    ///
    /// Issue #661: a local binding initialized from a parameter and a nested
    /// closure that references one are both inside the rewrite's reach, so
    /// every reference becomes the named binding and the declaration expands.
    ///
    func test_localBindingAndNestedClosureReferences_rewriteToNamedBindings() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        let alias = name
                        Select(person)
                        From(person)
                        Where(person.name == alias && person.tags.contains { $0 == name })
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        let alias = name
                        Select(person)
                        From(person)
                        Where(person.name == alias && person.tags.contains { $0 == name })
                    }
                }

                func personByNameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        let alias = XLNamedBindingReference<String>(name: "name")
                        Select(person)
                        From(person)
                        Where(person.name == alias && person.tags.contains {
                                $0 == XLNamedBindingReference<String>(name: "name")
                            })
                    }
                }

                private static let __xlPersonByNameCache = XLRenderOnceCache<Person>()

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func preparePersonByName(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPersonByNameCache.request(for: self) {
                        personByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    ///
    /// The rewrite on its own leaves a key-path component and a plain callee
    /// unchanged, even where either shares a parameter's name. The guard
    /// reports both shapes before a declaration reaches the rewrite, so this
    /// pins the rewrite directly.
    ///
    func test_rewriter_leavesKeyPathComponentsAndCalleesUnchanged() {
        let parameters = [
            SQLQueryParameter(swiftName: "name", placeholderName: "name", type: "String"),
            SQLQueryParameter(swiftName: "From", placeholderName: "From", type: "Int"),
        ]
        let source = Parser.parse(source: #"From(\Person.name, name) + From<Int>(From)"#)
        let rewritten = SQLQueryParameterRewriter(parameters: parameters).visit(source)
        XCTAssertEqual(
            rewritten.description,
            #"From(\Person.name, XLNamedBindingReference<String>(name: "name")) + From<Int>(XLNamedBindingReference<Int>(name: "From"))"#
        )
    }

    ///
    /// Issue #660: the `prepare` peer must take the same render-once request
    /// and build the same binding packet as the executor, so an observed
    /// declared query can never bind differently from a called one. The two
    /// functions are compared line by line up to the point where the executor
    /// fetches and the prepare peer returns. A bare `Row` result is used
    /// because its fetch block is the longest.
    ///
    func test_prepareFunction_sharesPreparationLinesWithExecutor() throws {
        let source = Parser.parse(source: """
            func personNamed(name: String, minimumAge: Int?) -> Person {
                sqlResult { schema in
                    let person = schema.table(Person.self)
                    Select(person)
                    From(person)
                    Where(person.name == name && person.age >= minimumAge)
                }
            }
            """)
        let function = try XCTUnwrap(source.statements.first?.item.as(FunctionDeclSyntax.self))
        let builder = try SQLQueryBuilder(
            node: AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("SQLQuery"))),
            declaration: function
        )
        let executor = builder.makeExecutorFunction().components(separatedBy: "\n")
        let prepare = builder.makePrepareFunction().components(separatedBy: "\n")

        XCTAssertEqual(
            prepare.first,
            "func preparePersonNamed(name: String, minimumAge: Int?) throws -> XLPreparedQuery<Person> {"
        )
        XCTAssertEqual(prepare.suffix(2), [
            "    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)",
            "}",
        ])

        let sharedCount = prepare.count - 3
        let sharedPreparation = Array(prepare.dropFirst().prefix(sharedCount))
        XCTAssertEqual(Array(executor.dropFirst().prefix(sharedCount)), sharedPreparation)
        XCTAssertEqual(
            sharedPreparation.first,
            "    let __xlRequest = Self.__xlPersonNamedCache.request(for: self) {"
        )
        XCTAssertTrue(sharedPreparation.contains(
            "            try _xlQueryParameterBinding(minimumAge, named: \"minimumAge\", in: __xlLayout),"
        ))
        XCTAssertEqual(
            executor[sharedCount + 1],
            "    let __xlRows = try __xlRequest.fetchAtMost(2, bindings: __xlPacket)",
            "the executor must fetch immediately after the shared preparation lines"
        )
    }

    ///
    /// A `Row?` direct-result signature dispatches to `fetchOne` and returns an
    /// optional row. This is the only source of the cardinality — the return
    /// annotation — since the macro is declaration-local.
    ///
    func test_directResultOptional_dispatchesFetchOne() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByExactName(name: String) -> Person? {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByExactName(name: String) -> Person? {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }

                func personByExactNameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name"))
                    }
                }

                private static let __xlPersonByExactNameCache = XLRenderOnceCache<Person>()

                func fetchPersonByExactName(name: String) throws -> Person? {
                    let __xlRequest = Self.__xlPersonByExactNameCache.request(for: self) {
                        personByExactNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchOne(bindings: __xlPacket)
                }

                func preparePersonByExactName(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlPersonByExactNameCache.request(for: self) {
                        personByExactNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    ///
    /// A bare `Row` direct-result signature (v1.5.1 extension) dispatches to a
    /// fetch-all-then-validate-count executor that throws
    /// `XLQueryCardinalityError.noRowsMatched/.moreThanOneRowMatched` when the query does not
    /// match exactly one row.
    ///
    func test_directResultBareRow_dispatchesExactlyOne() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func theOnlyPerson(name: String) -> Person {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func theOnlyPerson(name: String) -> Person {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }

                func theOnlyPersonStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name"))
                    }
                }

                private static let __xlTheOnlyPersonCache = XLRenderOnceCache<Person>()

                func fetchTheOnlyPerson(name: String) throws -> Person {
                    let __xlRequest = Self.__xlTheOnlyPersonCache.request(for: self) {
                        theOnlyPersonStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    let __xlRows = try __xlRequest.fetchAtMost(2, bindings: __xlPacket)
                    switch __xlRows.count {
                    case 0:
                        throw XLQueryCardinalityError.noRowsMatched
                    case 1:
                        return __xlRows[0]
                    default:
                        throw XLQueryCardinalityError.moreThanOneRowMatched
                    }
                }

                func prepareTheOnlyPerson(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlTheOnlyPersonCache.request(for: self) {
                        theOnlyPersonStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    ///
    /// The `sqlResult` -> `sql` swap applies only in callee position. A
    /// reference that merely names the entry point elsewhere in the body is
    /// left untouched. (The expansion is syntactic, so the contrived non-callee
    /// reference needs no runtime meaning.)
    ///
    func test_directResult_calleeRenameAppliesOnlyInCalleePosition() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func auditedPersonByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                        audit(sqlResult)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func auditedPersonByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                        audit(sqlResult)
                    }
                }

                func auditedPersonByNameStatement() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == XLNamedBindingReference<String>(name: "name"))
                        audit(sqlResult)
                    }
                }

                private static let __xlAuditedPersonByNameCache = XLRenderOnceCache<Person>()

                func fetchAuditedPersonByName(name: String) throws -> [Person] {
                    let __xlRequest = Self.__xlAuditedPersonByNameCache.request(for: self) {
                        auditedPersonByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }

                func prepareAuditedPersonByName(name: String) throws -> XLPreparedQuery<Person> {
                    let __xlRequest = Self.__xlAuditedPersonByNameCache.request(for: self) {
                        auditedPersonByNameStatement()
                    }
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }
}


final class SQLQueryMacroDiagnosticTests: XCTestCase {

    func test_nonFunctionDeclaration_emitsError() {
        assertMacroExpansion(
            """
            @SQLQuery
            struct Sample {
            }
            """,
            expandedSource: """
            struct Sample {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' can only be applied to a function.",
                    line: 1,
                    column: 1
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_missingRowType_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func allPeople() -> any XLQueryStatement {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func allPeople() -> any XLQueryStatement {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' requires the function to return '[Row]' (fetch all), 'Row?' (fetch one), 'Row' (fetch exactly one), or the legacy 'any/some XLQueryStatement<Row>', with an explicit row type. The row type declares the executor's result element and the shape selects the fetch.",
                    line: 3,
                    column: 25
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// An explicit `Void` return is excluded from the bare-`Row`
    /// (`.exactlyOne`) fallback, so it still falls through to the same
    /// missing-row-type diagnostic rather than being treated as a nonsensical
    /// `Void` row type. `.command` (write statements) is out of scope for
    /// v1.5.1; see the DeclaredQueries.md limitations section.
    ///
    func test_voidReturn_emitsMissingRowTypeError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func allPeople() -> Void {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func allPeople() -> Void {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' requires the function to return '[Row]' (fetch all), 'Row?' (fetch one), 'Row' (fetch exactly one), or the legacy 'any/some XLQueryStatement<Row>', with an explicit row type. The row type declares the executor's result element and the shape selects the fetch.",
                    line: 3,
                    column: 25
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// `Swift.Void` is the same type as the bare `Void` spelling covered by
    /// `test_voidReturn_emitsMissingRowTypeError` above, and must be excluded
    /// from the bare-`Row` fallback the same way (Copilot review, PR #381).
    ///
    func test_moduleQualifiedVoidReturn_emitsMissingRowTypeError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func allPeople() -> Swift.Void {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func allPeople() -> Swift.Void {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' requires the function to return '[Row]' (fetch all), 'Row?' (fetch one), 'Row' (fetch exactly one), or the legacy 'any/some XLQueryStatement<Row>', with an explicit row type. The row type declares the executor's result element and the shape selects the fetch.",
                    line: 3,
                    column: 25
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_throwingFunction_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func allPeople() throws -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func allPeople() throws -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' requires a nonthrowing, synchronous function. Statement builders only construct a value-free statement.",
                    line: 3,
                    column: 22
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_variadicParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func peopleNamed(names: String...) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func peopleNamed(names: String...) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' cannot bind a variadic parameter to a single named placeholder.",
                    line: 3,
                    column: 35
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_genericFunction_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func rows<Value>(value: Value) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func rows<Value>(value: Value) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' cannot be applied to a generic function. The generated statement builder takes no arguments, so generic parameters cannot be inferred.",
                    line: 3,
                    column: 14
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_staticFunction_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                static func allPeople() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                static func allPeople() -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' can only be applied to an instance method. The generated executor prepares its request through 'self.makeRequest(with:)'.",
                    line: 3,
                    column: 5
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_shadowingLocalBinding_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        let name = "frozen"
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        let name = "frozen"
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' shadows a query parameter inside the '@SQLQuery' body. The macro rewrites every reference to 'name' into a named binding, so a shadowing declaration would change what those references mean. Rename the declaration.",
                    line: 6,
                    column: 17
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_shadowingClosureParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { name in
                        let person = name.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { name in
                        let person = name.table(Person.self)
                        Select(person)
                        From(person)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' shadows a query parameter inside the '@SQLQuery' body. The macro rewrites every reference to 'name' into a named binding, so a shadowing declaration would change what those references mean. Rename the declaration.",
                    line: 4,
                    column: 15
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_parameterMemberAccess_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name.uppercased())
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name.uppercased())
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' cannot be used through member access in a '@SQLQuery' body. A parameter reference is rewritten to a named binding as a whole expression; compute the derived value before building the statement, or pass it as a separate parameter.",
                    line: 8,
                    column: 34
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_missingBody_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func allPeople() -> any XLQueryStatement<Person>
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func allPeople() -> any XLQueryStatement<Person>
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' requires a function body that returns the query statement.",
                    line: 3,
                    column: 19
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// A parameter named after a statement-builder entry point would be
    /// rewritten wherever the builder is called, corrupting the generated code.
    ///
    func test_reservedParameterName_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func rowsMatching(sql: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == sql)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func rowsMatching(sql: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == sql)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' cannot bind a parameter named 'sql'. The name collides with a statement-builder entry point, so rewriting its references would corrupt the builder call in the generated peer. Rename the parameter.",
                    line: 3,
                    column: 23
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// The `sqlResult` -> `sql` swap matches only an unqualified callee, so a
    /// qualified spelling is rejected rather than left to trap at runtime in
    /// the generated statement builder.
    ///
    func test_qualifiedEntryPoint_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> [Person] {
                    SwiftQL.sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> [Person] {
                    SwiftQL.sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'sqlResult' must be called unqualified in a '@SQLQuery' specification. The macro rewrites the entry point lexically and cannot distinguish a module qualifier from another object's member of the same name.",
                    line: 4,
                    column: 9
                )
            ],
            macros: makeTestMacros()
        )
    }

    // MARK: - Frozen-literal guard

    ///
    /// A collection parameter would render a variable-length `IN` list, so the
    /// SQL text changes with the element count and the render-once cache breaks.
    ///
    func test_collectionParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func peopleByNames(names: [String]) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == names)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func peopleByNames(names: [String]) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == names)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' cannot bind the array parameter 'names' to a single named placeholder. A variable-length list renders SQL whose text changes with the element count, which breaks the stable-SQL premise the prepared query relies on. Spell the elements in the statement with the 'in(_:)' expression forms, or pass a fixed set of scalar parameters.",
                    line: 3,
                    column: 31
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// An optional collection in the generic `Optional<[T]>` spelling is still a
    /// collection and is rejected, not just the postfix `[T]?` spelling.
    ///
    func test_genericOptionalCollectionParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func peopleByNames(names: Optional<[String]>) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == names)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func peopleByNames(names: Optional<[String]>) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == names)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' cannot bind the array parameter 'names' to a single named placeholder. A variable-length list renders SQL whose text changes with the element count, which breaks the stable-SQL premise the prepared query relies on. Spell the elements in the statement with the 'in(_:)' expression forms, or pass a fixed set of scalar parameters.",
                    line: 3,
                    column: 31
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// A parameter inside a string interpolation renders its value into the
    /// string rather than binding a placeholder.
    ///
    func test_stringInterpolationParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == "prefix\\(name)")
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == "prefix\\(name)")
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' is used inside a string interpolation in the '@SQLQuery' body, which renders its value into the string rather than binding a placeholder. Build the value into the statement with a comparison against a column, not an interpolated string.",
                    line: 8,
                    column: 43
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// Issue #661: a key-path component that shares a parameter's name is not a
    /// reference to the parameter. The rewrite leaves it unchanged, and the
    /// guard reports the shared name instead of letting the rewrite corrupt the
    /// key path.
    ///
    func test_parameterNamedLikeKeyPathComponent_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                        OrderBy(\\Person.name)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == name)
                        OrderBy(\\Person.name)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' is a query parameter and also a key-path component in the '@SQLQuery' body. The rewrite leaves a key-path component unchanged, so the two uses of the name mean different things. Rename the parameter.",
                    line: 9,
                    column: 29
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// Issue #661: a parameter named like a DSL callee would otherwise rewrite
    /// the clause itself (`From(person)`). The rewrite leaves a callee
    /// unchanged, and the guard reports the shared name.
    ///
    func test_parameterNamedLikeDSLCallee_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func people(From: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == From)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func people(From: String) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.name == From)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'From' is a query parameter and also the name of a called function or type in the '@SQLQuery' body. The rewrite leaves a callee unchanged, and a parameter value cannot be called, so the two uses of the name mean different things. Rename the parameter.",
                    line: 7,
                    column: 13
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// The callee check also covers a callee with generic arguments.
    ///
    func test_parameterNamedLikeGenericCallee_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func people(Limit: Int) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.age == Limit)
                        Limit<Int>(10)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func people(Limit: Int) -> [Person] {
                    sqlResult { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.age == Limit)
                        Limit<Int>(10)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'Limit' is a query parameter and also the name of a called function or type in the '@SQLQuery' body. The rewrite leaves a callee unchanged, and a parameter value cannot be called, so the two uses of the name mean different things. Rename the parameter.",
                    line: 9,
                    column: 13
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// A hand-constructed binding reference bypasses the signature contract and
    /// can disagree with the rendered parameter layout.
    ///
    func test_manualBindingReference_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func rows(id: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.id == id && person.other == XLNamedBindingReference<String>(name: "x"))
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func rows(id: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.id == id && person.other == XLNamedBindingReference<String>(name: "x"))
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' derives every named binding from the function signature, so 'XLNamedBindingReference' must not be constructed by hand in the body. A hand-built binding can disagree with the rendered parameter layout. Reference the parameter directly and let the macro generate the binding.",
                    line: 8,
                    column: 54
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// The manual-binding guard also covers the `contextualBinding(_:)`
    /// spelling, so the unqualified-callee match is exercised alongside the
    /// generic `XLNamedBindingReference<…>(…)` form.
    ///
    func test_manualContextualBinding_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func rows(id: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.id == id && person.other == contextualBinding("x"))
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func rows(id: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.id == id && person.other == contextualBinding("x"))
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQuery' derives every named binding from the function signature, so 'contextualBinding' must not be constructed by hand in the body. A hand-built binding can disagree with the rendered parameter layout. Reference the parameter directly and let the macro generate the binding.",
                    line: 8,
                    column: 54
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// A parameter never referenced in the body cannot bind a placeholder, and
    /// the signature-driven rewrite can catch it at the declaration site.
    ///
    func test_unusedParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func rows(id: String, unused: Int) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.id == id)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func rows(id: String, unused: Int) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.id == id)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'unused' is never referenced in the '@SQLQuery' body, so it cannot bind a placeholder. A standalone bindings struct defers this to execution time, but the signature-driven rewrite can catch it here: reference the parameter in the statement, or remove it.",
                    line: 3,
                    column: 27
                )
            ],
            macros: makeTestMacros()
        )
    }
}
