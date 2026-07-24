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
}
