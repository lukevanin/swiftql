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
                            _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
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
                            _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                            _xlQueryParameterBinding(minimumAge, named: "minimumAge", in: __xlLayout),
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
                            _xlQueryParameterBinding(nickname, named: "nickname", in: __xlLayout),
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
                            _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
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
                    message: "'@SQLQuery' requires the function to return 'any XLQueryStatement<Row>' with an explicit row type. The row type declares the executor's result element.",
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
