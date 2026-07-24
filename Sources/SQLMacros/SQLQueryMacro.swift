//
//  SQLQueryMacro.swift
//  SwiftQL
//
//  Spike (#359/#369): attached peer macro that rewrites a query-specification
//  function into a value-free statement builder plus an executor whose fetch
//  (`fetchAll` / `fetchOne`) is dispatched from the return annotation.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros


///
/// Declares a query-specification function as a reusable prepared query.
///
/// The attached function builds a `SELECT` statement from its parameters. The
/// macro generates two peers: a value-free statement builder in which every
/// parameter reference is replaced by a typed `XLNamedBindingReference`, and an
/// executor that renders the statement once per call through the enclosing
/// database's `makeRequest(with:)`, binds the parameter values into an
/// immutable invocation packet, and fetches the result. The fetch is dispatched
/// from the function's return annotation: `[Row]` (or the legacy
/// `any/some XLQueryStatement<Row>`) fetches all rows, `Row?` fetches one.
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

    /// The internal parameter name exactly as written, including any escaping
    /// backticks. Used where generated code passes the parameter value.
    var swiftName: String

    /// The internal parameter name without escaping backticks. Doubles as the
    /// SQL placeholder name and as the rewrite-matching key.
    var placeholderName: String

    /// The type annotation exactly as written in the signature.
    var type: String

    /// The typed named-binding reference that replaces every reference to the
    /// parameter inside the statement body.
    var bindingReference: String {
        "XLNamedBindingReference<\(type)>(name: \"\(placeholderName)\")"
    }
}


///
/// Removes the escaping backticks from an identifier spelling, so escaped and
/// unescaped references to the same declaration compare equal.
///
internal func normalizedIdentifier(_ text: String) -> String {
    guard text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") else {
        return text
    }
    return String(text.dropFirst().dropLast())
}


///
/// Result cardinality derived from the attached function's return type.
///
/// Spike (#369): with a direct-result signature the return annotation is the
/// only source of cardinality. `[Row]` maps to `fetchAll`, `Row?` to
/// `fetchOne`. The legacy `XLQueryStatement<Row>` spelling from #359 is treated
/// as `.many` for source compatibility.
///
internal enum SQLQueryCardinality {
    case many // [Row]  -> fetchAll
    case one  // Row?   -> fetchOne
}


///
/// The row element type, cardinality, and spelling style extracted from the
/// return clause.
///
internal struct SQLQueryReturnShape {

    /// The element type the executor decodes (e.g. `Person`).
    var rowType: String

    /// Whether the executor fetches all rows or an optional single row.
    var cardinality: SQLQueryCardinality

    /// `true` when the function declares its result directly (`[Row]` / `Row?`,
    /// spike #369); `false` for the legacy `XLQueryStatement<Row>` spelling
    /// (#359). In the direct-result case the statement-builder peer must swap
    /// the trapping `sqlResult` entry point for the real `sql` builder.
    var isDirectResult: Bool
}


///
/// Parses the attached function and generates the statement-builder and
/// executor peers for the `@SQLQuery` macro.
///
internal struct SQLQueryBuilder {

    let function: FunctionDeclSyntax

    let parameters: [SQLQueryParameter]

    let returnShape: SQLQueryReturnShape

    var rowType: String { returnShape.rowType }

    let rewrittenBodyText: String

    /// The user-facing attribute name used in diagnostics — `@SQLQuery` for
    /// the per-function peer macro, `@SQLQueries` when specifications are
    /// parsed out of a container by the member macro.
    let macroName: String

    init(
        node: AttributeSyntax,
        declaration: some DeclSyntaxProtocol,
        macroName: String = "@SQLQuery"
    ) throws {
        self.macroName = macroName
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    id: "sqlquery-function-only",
                    message: "'\(macroName)' can only be applied to a function."
                )
            ])
        }
        self.function = function

        var diagnostics: [Diagnostic] = []

        if let typeLevelModifier = function.modifiers.first(where: { modifier in
            modifier.name.tokenKind == .keyword(.static)
                || modifier.name.tokenKind == .keyword(.class)
        }) {
            diagnostics.append(
                Diagnostic(
                    node: typeLevelModifier,
                    id: "sqlquery-instance-method-only",
                    message: "'\(macroName)' can only be applied to an instance method. The generated executor prepares its request through 'self.makeRequest(with:)'."
                )
            )
        }

        if let genericParameterClause = function.genericParameterClause {
            diagnostics.append(
                Diagnostic(
                    node: genericParameterClause,
                    id: "sqlquery-generic-function",
                    message: "'\(macroName)' cannot be applied to a generic function. The generated statement builder takes no arguments, so generic parameters cannot be inferred."
                )
            )
        }

        if let effectSpecifiers = function.signature.effectSpecifiers {
            diagnostics.append(
                Diagnostic(
                    node: effectSpecifiers,
                    id: "sqlquery-effect-specifiers",
                    message: "'\(macroName)' requires a nonthrowing, synchronous function. Statement builders only construct a value-free statement."
                )
            )
        }

        self.parameters = Self.makeParameters(
            of: function,
            macroName: macroName,
            diagnostics: &diagnostics
        )
        self.returnShape = Self.makeReturnShape(
            of: function,
            macroName: macroName,
            diagnostics: &diagnostics
        )

        guard let body = function.body else {
            diagnostics.append(
                Diagnostic(
                    node: Syntax(function.signature),
                    id: "sqlquery-body-required",
                    message: "'\(macroName)' requires a function body that returns the query statement."
                )
            )
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        let shadowingVisitor = SQLQueryShadowingVisitor(parameters: parameters, macroName: macroName)
        shadowingVisitor.walk(body)
        diagnostics.append(contentsOf: shadowingVisitor.diagnostics)

        if shadowingVisitor.diagnostics.isEmpty {
            // A shadowed name makes lexical parameter analysis unreliable, so
            // member-access checking waits until the shadowing is resolved.
            let memberAccessVisitor = SQLQueryParameterMemberAccessVisitor(parameters: parameters, macroName: macroName)
            memberAccessVisitor.walk(body)
            diagnostics.append(contentsOf: memberAccessVisitor.diagnostics)
        }

        guard diagnostics.isEmpty else {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        // In the direct-result case the spec body calls the trapping `sqlResult`
        // entry point (so the user's `-> [Row]` / `-> Row?` function type-checks
        // without executing). The generated statement builder must call the real
        // `sql` builder instead, so the rewriter renames that callee too.
        // (`sqlResult` is provisional — `sqlQuery` is already the labeled-closure
        // statement builder in SQLFunctionalSyntax.swift.)
        let calleeRenames = returnShape.isDirectResult ? ["sqlResult": "sql"] : [:]
        let rewriter = SQLQueryParameterRewriter(
            parameters: parameters,
            calleeRenames: calleeRenames
        )
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
    /// Parameter names that collide with a statement-builder entry point. The
    /// rewrite replaces every reference to a parameter, so a parameter with one
    /// of these names would corrupt the builder call in the generated code.
    ///
    private static let reservedParameterNames: Set<String> = [
        "sql", "sqlQuery", "sqlResult",
    ]

    ///
    /// Classifies the function parameters, reporting shapes that cannot be
    /// rewritten to a named binding.
    ///
    private static func makeParameters(
        of function: FunctionDeclSyntax,
        macroName: String,
        diagnostics: inout [Diagnostic]
    ) -> [SQLQueryParameter] {
        var parameters: [SQLQueryParameter] = []
        for parameter in function.signature.parameterClause.parameters {
            if let ellipsis = parameter.ellipsis {
                diagnostics.append(
                    Diagnostic(
                        node: ellipsis,
                        id: "sqlquery-variadic-parameter",
                        message: "'\(macroName)' cannot bind a variadic parameter to a single named placeholder."
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
                        message: "'\(macroName)' cannot bind a '\(specifier.text)' parameter to a named placeholder."
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
                        message: "'\(macroName)' requires every parameter to have a name. The name identifies the SQL placeholder."
                    )
                )
                continue
            }
            if reservedParameterNames.contains(normalizedIdentifier(name.text)) {
                // The rewrite replaces every reference to a parameter, and the
                // builder callee is itself a plain identifier reference — a
                // parameter with the same name would corrupt the builder call
                // in the generated peer.
                diagnostics.append(
                    Diagnostic(
                        node: name,
                        id: "sqlquery-reserved-parameter-name",
                        message: "'\(macroName)' cannot bind a parameter named '\(normalizedIdentifier(name.text))'. The name collides with a statement-builder entry point, so rewriting its references would corrupt the builder call in the generated peer. Rename the parameter."
                    )
                )
                continue
            }
            parameters.append(
                SQLQueryParameter(
                    swiftName: name.text,
                    placeholderName: normalizedIdentifier(name.text),
                    type: parameter.type.trimmedDescription
                )
            )
        }
        return parameters
    }

    ///
    /// Derives the row type and cardinality from the return annotation.
    ///
    /// Three spellings are accepted:
    ///   * `[Row]` (spike #369)                 → `.many`, direct result
    ///   * `Row?` (spike #369)                  → `.one`, direct result
    ///   * `any/some XLQueryStatement<Row>` (#359) → `.many`, legacy statement
    ///
    private static func makeReturnShape(
        of function: FunctionDeclSyntax,
        macroName: String,
        diagnostics: inout [Diagnostic]
    ) -> SQLQueryReturnShape {
        let returnType = function.signature.returnClause?.type.trimmed

        // `[Row]` and `Array<Row>` -> fetchAll, direct result.
        if let arrayType = returnType?.as(ArrayTypeSyntax.self) {
            return SQLQueryReturnShape(
                rowType: arrayType.element.trimmedDescription,
                cardinality: .many,
                isDirectResult: true
            )
        }
        // `Row?` and `Optional<Row>` -> fetchOne, direct result.
        if let optionalType = returnType?.as(OptionalTypeSyntax.self) {
            return SQLQueryReturnShape(
                rowType: optionalType.wrappedType.trimmedDescription,
                cardinality: .one,
                isDirectResult: true
            )
        }
        if let (name, arguments) = genericConstraint(of: returnType),
           name == "Array", let element = singleGenericArgument(arguments) {
            return SQLQueryReturnShape(rowType: element, cardinality: .many, isDirectResult: true)
        }
        if let (name, arguments) = genericConstraint(of: returnType),
           name == "Optional", let element = singleGenericArgument(arguments) {
            return SQLQueryReturnShape(rowType: element, cardinality: .one, isDirectResult: true)
        }

        // Legacy #359 spelling: `any/some XLQueryStatement<Row>` -> fetchAll.
        var constraint = returnType
        if let someOrAny = constraint?.as(SomeOrAnyTypeSyntax.self) {
            constraint = someOrAny.constraint.trimmed
        }
        if let (name, arguments) = genericConstraint(of: constraint),
           name == "XLQueryStatement", let rowType = singleGenericArgument(arguments) {
            return SQLQueryReturnShape(rowType: rowType, cardinality: .many, isDirectResult: false)
        }

        diagnostics.append(
            Diagnostic(
                node: Syntax(function.signature.returnClause?.type) ?? Syntax(function.signature),
                id: "sqlquery-return-type",
                message: "'\(macroName)' requires the function to return '[Row]' (fetch all), 'Row?' (fetch one), or the legacy 'any/some XLQueryStatement<Row>', with an explicit row type. The row type declares the executor's result element and the shape selects the fetch."
            )
        )
        return SQLQueryReturnShape(rowType: "", cardinality: .many, isDirectResult: false)
    }

    ///
    /// Splits a nominal type into its name token and generic argument clause,
    /// handling both a bare identifier (`Array<Row>`) and a member type
    /// (`Swift.Array<Row>`).
    ///
    private static func genericConstraint(
        of type: TypeSyntax?
    ) -> (name: String, arguments: GenericArgumentClauseSyntax?)? {
        if let identifierType = type?.as(IdentifierTypeSyntax.self) {
            return (identifierType.name.text, identifierType.genericArgumentClause)
        }
        if let memberType = type?.as(MemberTypeSyntax.self) {
            return (memberType.name.text, memberType.genericArgumentClause)
        }
        return nil
    }

    private static func singleGenericArgument(
        _ arguments: GenericArgumentClauseSyntax?
    ) -> String? {
        guard let arguments, arguments.arguments.count == 1 else {
            return nil
        }
        return arguments.arguments.first?.argument.trimmedDescription
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
        // The value-free statement is always an `XLQueryStatement<Row>`. In the
        // legacy #359 spelling the function already declared exactly that, so the
        // written return type is reused. In the direct-result case (#369) the
        // function declared `[Row]` / `Row?`, so the statement builder's return
        // type is synthesized from the extracted row type instead.
        let returnType: String
        if returnShape.isDirectResult {
            returnType = "any XLQueryStatement<\(rowType)>"
        }
        else {
            returnType = function.signature.returnClause?.type.trimmedDescription ?? ""
        }
        return "\(modifierPrefix)func \(statementFunctionName)() -> \(returnType) \(rewrittenBodyText)"
    }

    ///
    /// Generates the executor peer. The executor prepares a request from the
    /// value-free statement, encodes the parameter values into one immutable
    /// invocation packet, and fetches all rows.
    ///
    /// The executor's declared result type, derived from the cardinality.
    var executorResultType: String {
        switch returnShape.cardinality {
        case .many:
            return "[\(rowType)]"
        case .one:
            return "\(rowType)?"
        }
    }

    /// The request fetch the executor dispatches to.
    var fetchCallName: String {
        switch returnShape.cardinality {
        case .many:
            return "fetchAll"
        case .one:
            return "fetchOne"
        }
    }

    func makeExecutorFunction() -> String {
        let parameterClause = function.signature.parameterClause.trimmedDescription
        let resultType = executorResultType
        let fetchCall = fetchCallName
        var lines: [String] = []
        lines.append("\(modifierPrefix)func \(executorFunctionName)\(parameterClause) throws -> \(resultType) {")
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
                lines.append("            try _xlQueryParameterBinding(\(parameter.swiftName), named: \"\(parameter.placeholderName)\", in: __xlLayout),")
            }
            lines.append("        ]")
            lines.append("    ).validatingComplete()")
        }
        lines.append("    return try __xlRequest.\(fetchCall)(bindings: __xlPacket)")
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

    /// Identifier renames applied only to the called expression of a function
    /// call — used to swap the trapping `sqlResult` spec entry point for the
    /// real `sql` builder in the direct-result encoding (#369). References
    /// outside callee position are never renamed.
    private let calleeRenames: [String: String]

    init(parameters: [SQLQueryParameter], calleeRenames: [String: String] = [:]) {
        var replacements: [String: String] = [:]
        for parameter in parameters {
            replacements[parameter.placeholderName] = parameter.bindingReference
        }
        self.replacements = replacements
        self.calleeRenames = calleeRenames
        super.init()
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
        guard let replacement = replacements[normalizedIdentifier(node.baseName.text)] else {
            return ExprSyntax(node)
        }
        var expression = ExprSyntax("\(raw: replacement)")
        expression.leadingTrivia = node.leadingTrivia
        expression.trailingTrivia = node.trailingTrivia
        return expression
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        // A callee rename applies only in callee position: a reference that
        // merely *names* the entry point elsewhere in the body is left alone.
        var node = node
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
           let renamed = calleeRenames[normalizedIdentifier(callee.baseName.text)] {
            let token = TokenSyntax.identifier(renamed)
                .with(\.leadingTrivia, callee.baseName.leadingTrivia)
                .with(\.trailingTrivia, callee.baseName.trailingTrivia)
            node = node.with(\.calledExpression, ExprSyntax(callee.with(\.baseName, token)))
        }
        return super.visit(node)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
        guard let base = node.base else {
            return ExprSyntax(node)
        }
        return ExprSyntax(node.with(\.base, visit(base)))
    }
}


///
/// Rejects declarations inside the attached body that shadow a query
/// parameter.
///
/// The rewrite is lexical: every expression reference whose name matches a
/// parameter becomes a named binding. A local binding, closure parameter, or
/// nested function parameter with the same name would make those references
/// mean something else, so the collision is reported instead of silently
/// rewriting the shadowed uses.
///
internal final class SQLQueryShadowingVisitor: SyntaxVisitor {

    private let parameterNames: Set<String>

    private let macroName: String

    private(set) var diagnostics: [Diagnostic] = []

    init(parameters: [SQLQueryParameter], macroName: String = "@SQLQuery") {
        self.parameterNames = Set(parameters.map(\.placeholderName))
        self.macroName = macroName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        check(node.identifier)
        return .visitChildren
    }

    override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
        check(node.name)
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        check(node.secondName ?? node.firstName)
        return .visitChildren
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        check(node.secondName ?? node.firstName)
        return .visitChildren
    }

    private func check(_ name: TokenSyntax) {
        let identifier = normalizedIdentifier(name.text)
        guard parameterNames.contains(identifier) else {
            return
        }
        diagnostics.append(
            Diagnostic(
                node: name,
                id: "sqlquery-shadowed-parameter",
                message: "'\(identifier)' shadows a query parameter inside the '\(macroName)' body. The macro rewrites every reference to '\(identifier)' into a named binding, so a shadowing declaration would change what those references mean. Rename the declaration."
            )
        )
    }
}


///
/// Rejects member access whose base is a query parameter.
///
/// A parameter reference must be rewriteable to a named binding as a whole
/// expression. An access such as `name.lowercased()` transforms the value in
/// Swift, which no placeholder can represent, so the generated peer would fail
/// to type-check.
///
internal final class SQLQueryParameterMemberAccessVisitor: SyntaxVisitor {

    private let parameterNames: Set<String>

    private let macroName: String

    private(set) var diagnostics: [Diagnostic] = []

    init(parameters: [SQLQueryParameter], macroName: String = "@SQLQuery") {
        self.parameterNames = Set(parameters.map(\.placeholderName))
        self.macroName = macroName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let base = node.base?.as(DeclReferenceExprSyntax.self) else {
            return .visitChildren
        }
        let identifier = normalizedIdentifier(base.baseName.text)
        guard parameterNames.contains(identifier) else {
            return .visitChildren
        }
        diagnostics.append(
            Diagnostic(
                node: base,
                id: "sqlquery-parameter-member-access",
                message: "'\(identifier)' cannot be used through member access in a '\(macroName)' body. A parameter reference is rewritten to a named binding as a whole expression; compute the derived value before building the statement, or pass it as a separate parameter."
            )
        )
        return .visitChildren
    }
}
