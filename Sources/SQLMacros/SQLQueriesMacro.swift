//
//  SQLQueriesMacro.swift
//  SwiftQL
//
//  Spike (#369, container encoding): attached member macro that reads query
//  specifications from a nested `Query` container inside a database extension
//  and generates the executors as members of the database itself.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
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
/// Generated members (names provisional per #26):
///   * `struct Context` — connection-scoped executors; one per specification.
///   * `execute(_:)` — runs a closure against a context. The spike stub wraps
///     the database directly; pooling/transaction scoping is runtime design.
///   * One database-level convenience executor per specification, defined as
///     sugar over `execute`, so the implicit form is transparently the
///     explicit one.
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

        var builders: [SQLQueryBuilder] = []
        var diagnostics: [Diagnostic] = []
        var foundContainer = false
        for member in extensionDecl.memberBlock.members {
            guard let container = member.decl.as(StructDeclSyntax.self),
                  container.name.text == "Query" else {
                continue
            }
            foundContainer = true
            for containerMember in container.memberBlock.members {
                guard let function = containerMember.decl.as(FunctionDeclSyntax.self) else {
                    continue
                }
                do {
                    builders.append(try SQLQueryBuilder(node: node, declaration: function))
                }
                catch let error as DiagnosticsError {
                    diagnostics.append(contentsOf: error.diagnostics)
                }
            }
        }

        guard foundContainer else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    id: "sqlqueries-container-required",
                    message: "'@SQLQueries' requires a nested 'struct Query' container declaring the query specifications."
                )
            ])
        }
        guard diagnostics.isEmpty else {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        var members: [String] = []
        members.append(makeContextStruct(databaseType: databaseType, builders: builders))
        members.append(makeExecuteFunction())
        for builder in builders {
            members.append(builder.makeDatabaseExecutorFunction())
        }
        return members.map { DeclSyntax(stringLiteral: $0) }
    }

    ///
    /// Generates the `Context` container holding one connection-scoped
    /// executor per specification.
    ///
    private static func makeContextStruct(
        databaseType: String,
        builders: [SQLQueryBuilder]
    ) -> String {
        var lines: [String] = []
        lines.append("struct Context {")
        lines.append("    let database: \(databaseType)")
        for builder in builders {
            lines.append("")
            lines.append(indent(builder.makeContextExecutorFunction(), by: 4))
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the `execute` entry point. The spike stub binds the context
    /// straight to the database; connection checkout and transaction scoping
    /// are runtime design outside this macro spike.
    ///
    private static func makeExecuteFunction() -> String {
        var lines: [String] = []
        lines.append("func execute<__XLResult>(_ __xlWork: (Context) throws -> __XLResult) throws -> __XLResult {")
        lines.append("    try __xlWork(Context(database: self))")
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
    /// The value-free statement is built inline from the rewritten body, so
    /// the specification's placeholder SQL invariant carries over unchanged.
    ///
    func makeContextExecutorFunction() -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        // The rewritten body is a code block; applying it as a closure yields
        // the value-free statement without a separate builder symbol.
        let statementExpression = indentSkippingFirstLine(rewrittenBodyText, by: 4)
        var lines: [String] = []
        lines.append("func \(function.name.text)\(parameterClause) throws -> \(executorResultType) {")
        lines.append("    let __xlStatement: any XLQueryStatement<\(rowType)> = \(statementExpression)()")
        lines.append("    let __xlRequest = database.makeRequest(with: __xlStatement)")
        lines.append("    let __xlLayout = __xlRequest.parameterLayout")
        if parameters.isEmpty {
            lines.append("    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()")
        }
        else {
            lines.append("    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(")
            lines.append("        layout: __xlLayout,")
            lines.append("        bindings: [")
            for parameter in parameters {
                lines.append("            try _xlQueryParameterBinding(\(parameter.swiftName), named: \"\(parameter.placeholderName)\", in: __xlLayout),")
            }
            lines.append("        ]")
            lines.append("    ).validatingComplete()")
        }
        lines.append("    return try __xlRequest.\(fetchCallName)(bindings: __xlPacket)")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the database-level convenience executor: sugar over
    /// `execute`, so the implicit one-shot form is transparently the explicit
    /// context form.
    ///
    func makeDatabaseExecutorFunction() -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        var arguments: [String] = []
        for parameter in function.signature.parameterClause.parameters {
            let value = (parameter.secondName ?? parameter.firstName).text
            if parameter.firstName.tokenKind == .wildcard {
                arguments.append(value)
            }
            else {
                arguments.append("\(parameter.firstName.text): \(value)")
            }
        }
        let argumentList = arguments.joined(separator: ", ")
        var lines: [String] = []
        lines.append("func \(function.name.text)\(parameterClause) throws -> \(executorResultType) {")
        lines.append("    try execute { __xlContext in")
        lines.append("        try __xlContext.\(function.name.text)(\(argumentList))")
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
