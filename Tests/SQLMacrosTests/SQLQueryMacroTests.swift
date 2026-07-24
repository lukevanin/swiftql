//
//  SQLQueryMacroTests.swift
//  SwiftQL
//
//  Tests for the `@SQLQuery` peer macro: signature-driven body rewriting,
//  executor generation, and diagnostics for unsupported declaration shapes.
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

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlStatement = personByNameStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
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

                public func fetchPeopleInCohort(name: String, minimumAge: Int) throws -> [Person] {
                    let __xlStatement = peopleInCohortStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
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

                func fetchPeopleByNickname(nickname: String?) throws -> [Person] {
                    let __xlStatement = peopleByNicknameStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(nickname, named: "nickname", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
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

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlStatement = personByNameStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
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

                func fetchRowsForKind(`class`: String) throws -> [Person] {
                    let __xlStatement = rowsForKindStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(`class`, named: "class", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
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

                func fetchAllPeople() throws -> [Person] {
                    let __xlStatement = allPeopleStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
        )
    }

    // MARK: - Spike #369: direct-result signatures + return-shape dispatch

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

                func fetchPersonByName(name: String) throws -> [Person] {
                    let __xlStatement = personByNameStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
                }
            }
            """,
            macros: makeTestMacros()
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

                func fetchPersonByExactName(name: String) throws -> Person? {
                    let __xlStatement = personByExactNameStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchOne(bindings: __xlPacket)
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

                func fetchAuditedPersonByName(name: String) throws -> [Person] {
                    let __xlStatement = auditedPersonByNameStatement()
                    let __xlRequest = self.makeRequest(with: __xlStatement)
                    let __xlLayout = __xlRequest.parameterLayout
                    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                        layout: __xlLayout,
                        bindings: [
                            try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                        ]
                    ).validatingComplete()
                    return try __xlRequest.fetchAll(bindings: __xlPacket)
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
                    message: "'@SQLQuery' requires the function to return '[Row]' (fetch all), 'Row?' (fetch one), or the legacy 'any/some XLQueryStatement<Row>', with an explicit row type. The row type declares the executor's result element and the shape selects the fetch.",
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

    // MARK: - Frozen-literal guard (#360)

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
    /// A parameter captured by a nested closure escapes the rewrite, which only
    /// reaches the statement builder itself.
    ///
    func test_nestedClosureParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(person.tags.contains { $0 == name })
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
                        Where(person.tags.contains { $0 == name })
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' is captured by a nested closure in the '@SQLQuery' body. The rewrite only reaches references in the statement builder itself, so a value captured deeper can escape into the cached SQL as a frozen literal. Reference the parameter directly in the statement.",
                    line: 8,
                    column: 48
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// A parameter passed to a helper call is invisible to the rewrite, so its
    /// value freezes into the cached SQL on the first invocation.
    ///
    func test_helperCallArgumentParameter_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        Select(person)
                        From(person)
                        Where(matches(name))
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
                        Where(matches(name))
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' is passed as an argument to a function call in the '@SQLQuery' body. The rewrite cannot see through the call, so the value would be frozen into the cached SQL on the first invocation. Use the parameter directly as a comparison operand (for example 'column == name') instead of passing it to a helper.",
                    line: 8,
                    column: 27
                )
            ],
            macros: makeTestMacros()
        )
    }

    ///
    /// A parameter used to initialize a local binding escapes the rewrite
    /// through the binding's later uses.
    ///
    func test_parameterInLocalBindingInitializer_emitsError() {
        assertMacroExpansion(
            """
            extension MyDatabase {
                @SQLQuery
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        let alias = name
                        Select(person)
                        From(person)
                        Where(person.name == alias)
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                func personByName(name: String) -> any XLQueryStatement<Person> {
                    sql { schema in
                        let person = schema.table(Person.self)
                        let alias = name
                        Select(person)
                        From(person)
                        Where(person.name == alias)
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'name' is used to initialize a local binding in the '@SQLQuery' body. The binding's later uses are outside the rewrite's reach, so the value can freeze into the cached SQL. Reference the parameter directly in the statement instead of storing it in a local.",
                    line: 6,
                    column: 25
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
