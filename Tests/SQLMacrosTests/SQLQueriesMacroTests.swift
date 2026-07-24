//
//  SQLQueriesMacroTests.swift
//  SwiftQL
//
//  Tests for the `@SQLQueries` member macro (#369, container encoding): the
//  macro reads specifications from a nested `Query` container and generates a
//  connection-scoped `Context`, the `execute` entry point, and database-level
//  convenience executors.
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
        "SQLQueries": SQLQueriesMacro.self,
    ]
}


final class SQLQueriesMacroExpansionTests: XCTestCase {

    ///
    /// The container's specifications become executors carrying the
    /// specification's own name: connection-scoped on `Context`, one-shot
    /// sugar on the database. `[Row]` dispatches `fetchAll`, `Row?` dispatches
    /// `fetchOne`. The `Query` container itself is left untouched and is never
    /// referenced by the generated members.
    ///
    func test_container_generatesContextExecuteAndDatabaseExecutors() {
        assertMacroExpansion(
            """
            @SQLQueries
            extension MyDatabase {
                private struct Query {
                    func personByName(name: String) -> [Person] {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                            Where(person.name == name)
                        }
                    }
                    func personById(id: String) -> Person? {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                            Where(person.id == id)
                        }
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                private struct Query {
                    func personByName(name: String) -> [Person] {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                            Where(person.name == name)
                        }
                    }
                    func personById(id: String) -> Person? {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                            Where(person.id == id)
                        }
                    }
                }

                struct Context {
                    let database: MyDatabase

                    func personByName(name: String) throws -> [Person] {
                        let __xlStatement: any XLQueryStatement<Person> = {
                            sql { schema in
                                let person = schema.table(Person.self)
                                Select(person)
                                From(person)
                                Where(person.name == XLNamedBindingReference<String>(name: "name"))
                            }
                        }()
                        let __xlRequest = database.makeRequest(with: __xlStatement)
                        let __xlLayout = __xlRequest.parameterLayout
                        let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                            layout: __xlLayout,
                            bindings: [
                                try _xlQueryParameterBinding(name, named: "name", in: __xlLayout),
                            ]
                        ).validatingComplete()
                        return try __xlRequest.fetchAll(bindings: __xlPacket)
                    }

                    func personById(id: String) throws -> Person? {
                        let __xlStatement: any XLQueryStatement<Person> = {
                            sql { schema in
                                let person = schema.table(Person.self)
                                Select(person)
                                From(person)
                                Where(person.id == XLNamedBindingReference<String>(name: "id"))
                            }
                        }()
                        let __xlRequest = database.makeRequest(with: __xlStatement)
                        let __xlLayout = __xlRequest.parameterLayout
                        let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(
                            layout: __xlLayout,
                            bindings: [
                                try _xlQueryParameterBinding(id, named: "id", in: __xlLayout),
                            ]
                        ).validatingComplete()
                        return try __xlRequest.fetchOne(bindings: __xlPacket)
                    }
                }

                func execute<__XLResult>(_ __xlWork: (Context) throws -> __XLResult) throws -> __XLResult {
                    try __xlWork(Context(database: self))
                }

                func personByName(name: String) throws -> [Person] {
                    try execute { __xlContext in
                        try __xlContext.personByName(name: name)
                    }
                }

                func personById(id: String) throws -> Person? {
                    try execute { __xlContext in
                        try __xlContext.personById(id: id)
                    }
                }
            }
            """,
            macros: makeTestMacros()
        )
    }
}


final class SQLQueriesMacroAccessLevelTests: XCTestCase {

    ///
    /// The extension's access level propagates to every generated member, so a
    /// `public extension` exposes `Context`, `execute`, and the database-level
    /// executors to outside-module callers.
    ///
    func test_publicExtension_propagatesAccessLevelToGeneratedMembers() {
        assertMacroExpansion(
            """
            @SQLQueries
            public extension MyDatabase {
                private struct Query {
                    func allPeople() -> [Person] {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                        }
                    }
                }
            }
            """,
            expandedSource: """
            public extension MyDatabase {
                private struct Query {
                    func allPeople() -> [Person] {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                        }
                    }
                }

                public struct Context {
                    let database: MyDatabase

                    public func allPeople() throws -> [Person] {
                        let __xlStatement: any XLQueryStatement<Person> = {
                            sql { schema in
                                let person = schema.table(Person.self)
                                Select(person)
                                From(person)
                            }
                        }()
                        let __xlRequest = database.makeRequest(with: __xlStatement)
                        let __xlLayout = __xlRequest.parameterLayout
                        let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()
                        return try __xlRequest.fetchAll(bindings: __xlPacket)
                    }
                }

                public func execute<__XLResult>(_ __xlWork: (Context) throws -> __XLResult) throws -> __XLResult {
                    try __xlWork(Context(database: self))
                }

                public func allPeople() throws -> [Person] {
                    try execute { __xlContext in
                        try __xlContext.allPeople()
                    }
                }
            }
            """,
            macros: makeTestMacros()
        )
    }
}


final class SQLQueriesMacroDiagnosticTests: XCTestCase {

    ///
    /// A malformed specification inside the container is diagnosed with the
    /// container macro's own name, not '@SQLQuery' (which the user never
    /// wrote).
    ///
    func test_malformedContainerSpec_diagnosticNamesSQLQueries() {
        assertMacroExpansion(
            """
            @SQLQueries
            extension MyDatabase {
                struct Query {
                    func allPeople() throws -> [Person] {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                        }
                    }
                }
            }
            """,
            expandedSource: """
            extension MyDatabase {
                struct Query {
                    func allPeople() throws -> [Person] {
                        sqlResult { schema in
                            let person = schema.table(Person.self)
                            Select(person)
                            From(person)
                        }
                    }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQueries' requires a nonthrowing, synchronous function. Statement builders only construct a value-free statement.",
                    line: 4,
                    column: 26
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_nonExtensionDeclaration_emitsError() {
        assertMacroExpansion(
            """
            @SQLQueries
            struct MyDatabase {
            }
            """,
            expandedSource: """
            struct MyDatabase {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQueries' can only be applied to an extension of a database type. The generated executors prepare requests through the extended type's 'makeRequest(with:)'.",
                    line: 1,
                    column: 1
                )
            ],
            macros: makeTestMacros()
        )
    }

    func test_missingQueryContainer_emitsError() {
        assertMacroExpansion(
            """
            @SQLQueries
            extension MyDatabase {
            }
            """,
            expandedSource: """
            extension MyDatabase {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@SQLQueries' requires a nested 'struct Query' container declaring the query specifications.",
                    line: 1,
                    column: 1
                )
            ],
            macros: makeTestMacros()
        )
    }
}
