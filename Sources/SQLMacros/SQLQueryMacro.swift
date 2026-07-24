//
//  SQLQueryMacro.swift
//  SwiftQL
//
//  Spike (#359): attached peer macro that rewrites a statement-returning
//  function into a value-free statement builder plus a `fetchAll` executor.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros


///
/// Declares a statement-returning function as a reusable prepared query.
///
/// The attached function builds a `SELECT` statement from its parameters. The
/// macro generates two peers: a value-free statement builder in which every
/// parameter reference is replaced by a typed `XLNamedBindingReference`, and an
/// executor that renders the statement once per call through the enclosing
/// database's `makeRequest(with:)`, binds the parameter values into an
/// immutable invocation packet, and returns the `fetchAll` rows.
///
public struct SQLQueryMacro {
}

extension SQLQueryMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let builder = try SQLQueryBuilder(node: node, declaration: declaration)
        return [
            DeclSyntax(stringLiteral: builder.makeStatementFunction()),
            DeclSyntax(stringLiteral: builder.makeExecutorFunction()),
        ]
    }
}


///
/// One named function parameter that participates in the signature-driven body
/// rewrite.
///
internal struct SQLQueryParameter {

    /// The internal parameter name. Doubles as the SQL placeholder name.
    var name: String

    /// The type annotation exactly as written in the signature.
    var type: String

    /// The typed named-binding reference that replaces every reference to the
    /// parameter inside the statement body.
    var bindingReference: String {
        "XLNamedBindingReference<\(type)>(name: \"\(name)\")"
    }
}


///
/// Parses the attached function and generates the statement-builder and
/// executor peers for the `@SQLQuery` macro.
///
internal struct SQLQueryBuilder {

    private let function: FunctionDeclSyntax

    private let parameters: [SQLQueryParameter]

    private let rowType: String

    private let rewrittenBodyText: String

    init(node: AttributeSyntax, declaration: some DeclSyntaxProtocol) throws {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    id: "sqlquery-function-only",
                    message: "'@SQLQuery' can only be applied to a function."
                )
            ])
        }
        self.function = function

        var diagnostics: [Diagnostic] = []

        if let genericParameterClause = function.genericParameterClause {
            diagnostics.append(
                Diagnostic(
                    node: genericParameterClause,
                    id: "sqlquery-generic-function",
                    message: "'@SQLQuery' cannot be applied to a generic function. The generated statement builder takes no arguments, so generic parameters cannot be inferred."
                )
            )
        }

        if let effectSpecifiers = function.signature.effectSpecifiers {
            diagnostics.append(
                Diagnostic(
                    node: effectSpecifiers,
                    id: "sqlquery-effect-specifiers",
                    message: "'@SQLQuery' requires a nonthrowing, synchronous function. Statement builders only construct a value-free statement."
                )
            )
        }

        self.parameters = Self.makeParameters(
            of: function,
            diagnostics: &diagnostics
        )
        self.rowType = Self.makeRowType(of: function, diagnostics: &diagnostics)

        guard let body = function.body else {
            diagnostics.append(
                Diagnostic(
                    node: Syntax(function.signature),
                    id: "sqlquery-body-required",
                    message: "'@SQLQuery' requires a function body that returns the query statement."
                )
            )
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        guard diagnostics.isEmpty else {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        let rewriter = SQLQueryParameterRewriter(parameters: parameters)
        self.rewrittenBodyText = Self.makeBodyText(rewriter.visit(body))
    }

    ///
    /// Removes the source-column indentation from the rewritten body so the
    /// generated peer is independent of how deeply the attached function is
    /// nested. The closing brace's column measures the indentation to strip.
    ///
    private static func makeBodyText(_ body: CodeBlockSyntax) -> String {
        let text = body.trimmedDescription
        var lines = text.components(separatedBy: "\n")
        guard lines.count > 1, let closingLine = lines.last else {
            return text
        }
        let indentation = closingLine.prefix { $0 == " " }.count
        guard indentation > 0 else {
            return text
        }
        for index in 1 ..< lines.count {
            var line = lines[index]
            var removed = 0
            while removed < indentation, line.first == " " {
                line.removeFirst()
                removed += 1
            }
            lines[index] = line
        }
        return lines.joined(separator: "\n")
    }

    ///
    /// Classifies the function parameters, reporting shapes that cannot be
    /// rewritten to a named binding.
    ///
    private static func makeParameters(
        of function: FunctionDeclSyntax,
        diagnostics: inout [Diagnostic]
    ) -> [SQLQueryParameter] {
        var parameters: [SQLQueryParameter] = []
        for parameter in function.signature.parameterClause.parameters {
            if let ellipsis = parameter.ellipsis {
                diagnostics.append(
                    Diagnostic(
                        node: ellipsis,
                        id: "sqlquery-variadic-parameter",
                        message: "'@SQLQuery' cannot bind a variadic parameter to a single named placeholder."
                    )
                )
                continue
            }
            if let attributedType = parameter.type.as(AttributedTypeSyntax.self),
               let specifier = attributedType.specifier {
                diagnostics.append(
                    Diagnostic(
                        node: attributedType,
                        id: "sqlquery-parameter-specifier",
                        message: "'@SQLQuery' cannot bind a '\(specifier.text)' parameter to a named placeholder."
                    )
                )
                continue
            }
            let name = parameter.secondName ?? parameter.firstName
            guard name.tokenKind != .wildcard else {
                diagnostics.append(
                    Diagnostic(
                        node: name,
                        id: "sqlquery-unnamed-parameter",
                        message: "'@SQLQuery' requires every parameter to have a name. The name identifies the SQL placeholder."
                    )
                )
                continue
            }
            parameters.append(
                SQLQueryParameter(
                    name: name.text,
                    type: parameter.type.trimmedDescription
                )
            )
        }
        return parameters
    }

    ///
    /// Extracts the row type from a `some XLQueryStatement<Row>` or
    /// `any XLQueryStatement<Row>` return annotation.
    ///
    private static func makeRowType(
        of function: FunctionDeclSyntax,
        diagnostics: inout [Diagnostic]
    ) -> String {
        let returnType = function.signature.returnClause?.type.trimmed
        var constraint = returnType
        if let someOrAny = constraint?.as(SomeOrAnyTypeSyntax.self) {
            constraint = someOrAny.constraint.trimmed
        }

        let name: TokenSyntax?
        let genericArguments: GenericArgumentClauseSyntax?
        if let identifierType = constraint?.as(IdentifierTypeSyntax.self) {
            name = identifierType.name
            genericArguments = identifierType.genericArgumentClause
        }
        else if let memberType = constraint?.as(MemberTypeSyntax.self) {
            name = memberType.name
            genericArguments = memberType.genericArgumentClause
        }
        else {
            name = nil
            genericArguments = nil
        }

        guard
            let name,
            name.text == "XLQueryStatement",
            let arguments = genericArguments?.arguments,
            arguments.count == 1,
            let rowType = arguments.first?.argument.trimmedDescription
        else {
            diagnostics.append(
                Diagnostic(
                    node: Syntax(function.signature.returnClause?.type) ?? Syntax(function.signature),
                    id: "sqlquery-return-type",
                    message: "'@SQLQuery' requires the function to return 'any XLQueryStatement<Row>' with an explicit row type. The row type declares the executor's result element."
                )
            )
            return ""
        }
        return rowType
    }

    private var modifierPrefix: String {
        let modifiers = function.modifiers.trimmedDescription
        if modifiers.isEmpty {
            return ""
        }
        return modifiers + " "
    }

    private var statementFunctionName: String {
        "\(function.name.text)Statement"
    }

    private var executorFunctionName: String {
        "fetch\(function.name.text.prefix(1).uppercased())\(function.name.text.dropFirst())"
    }

    ///
    /// Generates the value-free statement builder. The rewritten body renders
    /// named placeholders instead of inline value literals, so the SQL text is
    /// identical for every invocation.
    ///
    func makeStatementFunction() -> String {
        let returnType = function.signature.returnClause?.type.trimmedDescription ?? ""
        return "\(modifierPrefix)func \(statementFunctionName)() -> \(returnType) \(rewrittenBodyText)"
    }

    ///
    /// Generates the executor peer. The executor prepares a request from the
    /// value-free statement, encodes the parameter values into one immutable
    /// invocation packet, and fetches all rows.
    ///
    func makeExecutorFunction() -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        var lines: [String] = []
        lines.append("\(modifierPrefix)func \(executorFunctionName)\(parameterClause) throws -> [\(rowType)] {")
        lines.append("    let __xlStatement = \(statementFunctionName)()")
        lines.append("    let __xlRequest = self.makeRequest(with: __xlStatement)")
        lines.append("    let __xlLayout = __xlRequest.parameterLayout")
        if parameters.isEmpty {
            lines.append("    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()")
        }
        else {
            lines.append("    let __xlPacket = try XLInvocationBindings<XLSQLiteValue>(")
            lines.append("        layout: __xlLayout,")
            lines.append("        bindings: [")
            for parameter in parameters {
                lines.append("            _xlQueryParameterBinding(\(parameter.name), named: \"\(parameter.name)\", in: __xlLayout),")
            }
            lines.append("        ]")
            lines.append("    ).validatingComplete()")
        }
        lines.append("    return try __xlRequest.fetchAll(bindings: __xlPacket)")
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}


///
/// Replaces every expression reference to a function parameter with the
/// parameter's typed named-binding reference.
///
/// Member names are never rewritten: `person.name` keeps its member `name`
/// while a parameter also called `name` is still rewritten wherever it appears
/// as the base of a member access or as a standalone reference.
///
internal final class SQLQueryParameterRewriter: SyntaxRewriter {

    private let replacements: [String: String]

    init(parameters: [SQLQueryParameter]) {
        var replacements: [String: String] = [:]
        for parameter in parameters {
            replacements[parameter.name] = parameter.bindingReference
        }
        self.replacements = replacements
        super.init()
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
        guard let replacement = replacements[node.baseName.text] else {
            return ExprSyntax(node)
        }
        var expression = ExprSyntax("\(raw: replacement)")
        expression.leadingTrivia = node.leadingTrivia
        expression.trailingTrivia = node.trailingTrivia
        return expression
    }

    override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
        guard let base = node.base else {
            return ExprSyntax(node)
        }
        return ExprSyntax(node.with(\.base, visit(base)))
    }
}
