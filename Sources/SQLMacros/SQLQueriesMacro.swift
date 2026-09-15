//
//  SQLQueriesMacro.swift
//  SwiftQL
//
//  Issues #18/#26 (container encoding): attached member macro that reads query
//  specifications from a nested `Query` container inside a database extension
//  and generates the executors as members of the database itself. Ported from
//  the milestone #28 spike on `experiment/sqlquery-peer-macro`.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros


///
/// Generates executors for the query specifications declared in a nested
/// `Query` container.
///
/// A per-function peer macro cannot produce this shape: peers land in the same
/// scope as the attached function (so a same-name executor is an invalid
/// redeclaration) and independent expansions cannot cooperate on one shared
/// `Context` type. A member macro attached to the *extension* sees every
/// specification in one expansion, so the executors can carry the
/// specification's own name in a different scope.
///
/// Generated members:
///   * `struct Context` — connection-scoped executors; one per specification.
///   * `execute(_:)` — runs a closure against a context pinned to one
///     transaction (issue #284's `XLTransactionalDatabase.withTransaction(_:)`):
///     every declared-query call and `context.database.makeRequest(with:)`
///     call inside the closure runs on one pinned connection, committing
///     together on success and rolling back together on any failure.
///   * One database-level convenience executor per specification. On a
///     database it runs the `Context` executor in a new transaction, as
///     `execute` does; on a transaction scope it runs it on the scope
///     (issue #662).
///
/// The `Query` container itself is never referenced by the generated code —
/// it is a pure specification namespace, so the user may declare it `private`
/// or `fileprivate` to remove the trapping spec functions from the visible
/// API surface.
///
public struct SQLQueriesMacro {
}

extension SQLQueriesMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let extensionDecl = declaration.as(ExtensionDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    id: "sqlqueries-extension-only",
                    message: "'@SQLQueries' can only be applied to an extension of a database type. The generated executors prepare requests through the extended type's 'makeRequest(with:)'."
                )
            ])
        }
        let databaseType = extensionDecl.extendedType.trimmedDescription

        // Propagate the extension's modifiers (access level) to every
        // generated member, so a `public extension` exposes the executors to
        // outside-module callers.
        let modifierPrefix = macroModifierPrefix(extensionDecl.modifiers)

        var builders: [SQLQueryBuilder] = []
        var diagnostics: [Diagnostic] = []
        let containers = extensionDecl.memberBlock.members.compactMap { member in
            member.decl.as(StructDeclSyntax.self).flatMap { container in
                container.name.text == "Query" ? container : nil
            }
        }

        guard let container = containers.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    id: "sqlqueries-container-required",
                    message: "'@SQLQueries' requires a nested 'struct Query' container declaring the query specifications."
                )
            ])
        }

        // A second `Query` container's specifications would silently merge into the same
        // generated executor set with no indication which container a given executor came
        // from -- diagnose it instead of merging.
        for extraContainer in containers.dropFirst() {
            diagnostics.append(
                Diagnostic(
                    node: Syntax(extraContainer),
                    id: "sqlqueries-multiple-containers",
                    message: "'@SQLQueries' found more than one nested 'struct Query' container in this extension. Declare every query specification in a single 'Query' container."
                )
            )
        }

        for containerMember in container.memberBlock.members {
            guard let function = containerMember.decl.as(FunctionDeclSyntax.self) else {
                continue
            }
            do {
                builders.append(try SQLQueryBuilder(
                    node: node,
                    declaration: function,
                    macroName: "@SQLQueries"
                ))
            }
            catch let error as DiagnosticsError {
                diagnostics.append(contentsOf: error.diagnostics)
            }
        }

        diagnostics.append(contentsOf: preparedQueriesCollisionDiagnostics(
            container: container,
            extensionDecl: extensionDecl
        ))

        guard diagnostics.isEmpty else {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        var members: [String] = []
        members.append(makeContextStruct(
            databaseType: databaseType,
            builders: builders,
            modifierPrefix: modifierPrefix
        ))
        members.append(makeExecuteFunction(modifierPrefix: modifierPrefix))
        for builder in builders {
            members.append(builder.makeDatabaseExecutorFunction(modifierPrefix: modifierPrefix))
        }
        members.append(makePreparedQueriesProperty(modifierPrefix: modifierPrefix))
        return try members.map(makeDecl)
    }

    ///
    /// The name of the database-level property that holds the prepared forms
    /// (issue #660).
    ///
    static let preparedQueriesPropertyName = "preparedQueries"

    ///
    /// Reports the collisions with the generated `preparedQueries` property
    /// that this expansion can see (issue #660), at the user's declaration
    /// instead of as a redeclaration error in generated code.
    ///
    /// A member macro sees only its own extension. A `preparedQueries` member
    /// declared in the type body or in another extension still collides, and
    /// the compiler reports that as a redeclaration.
    ///
    private static func preparedQueriesCollisionDiagnostics(
        container: StructDeclSyntax,
        extensionDecl: ExtensionDeclSyntax
    ) -> [Diagnostic] {
        let name = preparedQueriesPropertyName
        var diagnostics: [Diagnostic] = []
        for containerMember in container.memberBlock.members {
            guard let function = containerMember.decl.as(FunctionDeclSyntax.self),
                  normalizedIdentifier(function.name.text) == name else {
                continue
            }
            diagnostics.append(
                Diagnostic(
                    node: function.name,
                    id: "sqlqueries-reserved-specification-name",
                    message: "'@SQLQueries' generates a '\(name)' property on the database for observing declared queries, so a query specification cannot be named '\(name)'. Rename the specification."
                )
            )
        }
        for member in extensionDecl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                          normalizedIdentifier(pattern.identifier.text) == name else {
                        continue
                    }
                    diagnostics.append(preparedQueriesMemberDiagnostic(at: Syntax(pattern.identifier)))
                }
            }
            else if let function = member.decl.as(FunctionDeclSyntax.self),
                    normalizedIdentifier(function.name.text) == name,
                    function.signature.parameterClause.parameters.isEmpty {
                diagnostics.append(preparedQueriesMemberDiagnostic(at: Syntax(function.name)))
            }
        }
        return diagnostics
    }

    private static func preparedQueriesMemberDiagnostic(at node: Syntax) -> Diagnostic {
        let name = preparedQueriesPropertyName
        return Diagnostic(
            node: node,
            id: "sqlqueries-prepared-queries-collision",
            message: "'\(name)' collides with the property '@SQLQueries' generates on the database for observing declared queries. Rename this member."
        )
    }

    ///
    /// Generates the `Context` container holding one connection-scoped
    /// executor per specification.
    ///
    private static func makeContextStruct(
        databaseType: String,
        builders: [SQLQueryBuilder],
        modifierPrefix: String
    ) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)struct Context {")
        lines.append("    let database: \(databaseType)")
        for builder in builders {
            lines.append("")
            lines.append(indent(builder.makeRenderOnceCacheDeclaration(), by: 4))
            lines.append("")
            lines.append(indent(builder.makeContextExecutorFunction(modifierPrefix: modifierPrefix), by: 4))
        }
        lines.append("")
        lines.append(indent(makePreparedQueriesStruct(
            databaseType: databaseType,
            builders: builders,
            modifierPrefix: modifierPrefix
        ), by: 4))
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates `Context.PreparedQueries` (issue #660): one function per
    /// specification that returns an `XLPreparedQuery` for observation.
    ///
    /// It is nested in `Context` so it can reach each specification's private
    /// render-once cache. The prepared form and the executor therefore share
    /// one cache entry and emit the same preparation lines.
    ///
    private static func makePreparedQueriesStruct(
        databaseType: String,
        builders: [SQLQueryBuilder],
        modifierPrefix: String
    ) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)struct PreparedQueries {")
        lines.append("    let database: \(databaseType)")
        for builder in builders {
            lines.append("")
            lines.append(indent(builder.makePreparedQueriesFunction(modifierPrefix: modifierPrefix), by: 4))
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the database-level `preparedQueries` namespace. It binds to the
    /// database itself, not to a transaction scope, because an observation
    /// outlives any one transaction.
    ///
    private static func makePreparedQueriesProperty(modifierPrefix: String) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)var preparedQueries: Context.PreparedQueries {")
        lines.append("    Context.PreparedQueries(database: self)")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the `execute` entry point. `execute(_:)` runs `__xlWork`
    /// inside a real transaction (issue #284) by delegating to
    /// `withTransaction(_:)` (``XLTransactionalDatabase``): the extended
    /// database type must conform to `XLTransactionalDatabase` for the
    /// generated code to compile, exactly as it must already conform to
    /// `XLDatabase` for `makeRequest(with:)`. `Context` binds to the pinned
    /// scope `withTransaction(_:)` hands back, so every generated executor
    /// the closure calls — and any `execute` calls it makes on the outer
    /// database convenience form — commits or rolls back together.
    ///
    private static func makeExecuteFunction(modifierPrefix: String) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)func execute<__XLResult>(_ __xlWork: (Context) throws -> __XLResult) throws -> __XLResult {")
        lines.append("    try withTransaction { __xlScope in")
        lines.append("        try __xlWork(Context(database: __xlScope))")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}


///
/// Indents every line of a multi-line declaration by the given column count.
///
internal func indent(_ text: String, by spaces: Int) -> String {
    let padding = String(repeating: " ", count: spaces)
    return text
        .components(separatedBy: "\n")
        .map { $0.isEmpty ? $0 : padding + $0 }
        .joined(separator: "\n")
}


extension SQLQueryBuilder {

    ///
    /// Generates the connection-scoped executor for the `Context` container.
    /// The value-free statement is built inline from the rewritten body and
    /// prepared through this specification's own `XLRenderOnceCache` (a
    /// sibling `static` member of `Context`, emitted alongside this
    /// function), so the container form gets the same render-once behavior
    /// as the `@SQLQuery` peer macro's executor rather than re-rendering SQL
    /// on every call.
    ///
    func makeContextExecutorFunction(modifierPrefix: String) -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        // The rewritten body is a code block; applying it as a closure yields
        // the value-free statement without a separate builder symbol.
        let statementExpression = indentSkippingFirstLine(rewrittenBodyText, by: 8)
        var lines: [String] = []
        lines.append("\(modifierPrefix)func \(function.name.text)\(parameterClause) throws -> \(executorResultType) {")
        lines.append(
            contentsOf: makeExecutorBodyLines(
                preparing: statementExpression,
                against: "database"
            )
        )
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates one function of `Context.PreparedQueries` (issue #660). It emits the
    /// preparation lines the context executor emits, with the cache reached
    /// through `Context`, and returns the request and packet instead of
    /// fetching.
    ///
    func makePreparedQueriesFunction(modifierPrefix: String) -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        let statementExpression = indentSkippingFirstLine(rewrittenBodyText, by: 8)
        var lines: [String] = []
        lines.append("\(modifierPrefix)func \(function.name.text)\(parameterClause) throws -> XLPreparedQuery<\(rowType)> {")
        lines.append(
            contentsOf: makePreparationLines(
                preparing: statementExpression,
                against: "database",
                cacheOwner: "Context"
            )
        )
        lines.append("    return XLPreparedQuery(request: __xlRequest, bindings: __xlPacket)")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the database-level convenience executor. On a database it is
    /// the explicit context form run in a new transaction, as `execute` runs
    /// it. On a transaction scope it runs the context executor on the scope
    /// itself (issue #662), so a declared query joins the open transaction
    /// instead of throwing `nestedTransactionUnsupported`. The runtime helper
    /// `_xlWithDeclaredQueryScope` makes that choice, so the context executor
    /// and its render-once request and packet stay the same on both paths.
    ///
    func makeDatabaseExecutorFunction(modifierPrefix: String) -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        var arguments: [String] = []
        for parameter in function.signature.parameterClause.parameters {
            let value = (parameter.secondName ?? parameter.firstName).text
            if parameter.firstName.tokenKind == .wildcard {
                arguments.append(value)
            }
            else {
                // The call-site label must be unescaped even when the
                // parameter's own spelling is backtick-escaped (a reserved
                // keyword like `class`): Swift call-site argument labels are
                // never backtick-escaped, only the referenced local variable
                // is. `value` keeps its original (possibly escaped) spelling.
                let label = normalizedIdentifier(parameter.firstName.text)
                arguments.append("\(label): \(value)")
            }
        }
        let argumentList = arguments.joined(separator: ", ")
        var lines: [String] = []
        lines.append("\(modifierPrefix)func \(function.name.text)\(parameterClause) throws -> \(executorResultType) {")
        lines.append("    try _xlWithDeclaredQueryScope(self) { __xlDatabase in")
        lines.append("        try Context(database: __xlDatabase).\(function.name.text)(\(argumentList))")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Indents every line except the first — used when a multi-line block is
    /// embedded after an assignment on an already-indented line.
    ///
    private func indentSkippingFirstLine(_ text: String, by spaces: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else {
            return text
        }
        let padding = String(repeating: " ", count: spaces)
        for index in 1 ..< lines.count {
            if !lines[index].isEmpty {
                lines[index] = padding + lines[index]
            }
        }
        return lines.joined(separator: "\n")
    }
}
