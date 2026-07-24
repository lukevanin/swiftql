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

            // Run the strict reference checks only on an otherwise-valid
            // declaration: a structural, parameter, return-type, shadowing, or
            // member-access problem already reported means the body cannot be
            // analyzed cleanly, so piling on frozen-literal diagnostics would
            // just add noise.
            if diagnostics.isEmpty {
                // With shadowing and member access clean, every remaining
                // reference to a parameter must sit in a position the rewrite
                // can turn into a named binding. The frozen-literal guard
                // reports the reference shapes that would otherwise let a value
                // escape the rewrite and freeze into the cached SQL text (#360),
                // and records which parameters were actually referenced so an
                // unused parameter can be flagged too.
                let frozenLiteralGuard = SQLQueryFrozenLiteralGuard(parameters: parameters, macroName: macroName)
                frozenLiteralGuard.walk(body)
                diagnostics.append(contentsOf: frozenLiteralGuard.diagnostics)

                let bindableNames = Set(parameters.map(\.placeholderName))
                for signatureParameter in function.signature.parameterClause.parameters {
                    let nameToken = signatureParameter.secondName ?? signatureParameter.firstName
                    let normalized = normalizedIdentifier(nameToken.text)
                    guard bindableNames.contains(normalized),
                          !frozenLiteralGuard.referencedParameterNames.contains(normalized) else {
                        continue
                    }
                    diagnostics.append(
                        Diagnostic(
                            node: nameToken,
                            id: "sqlquery-unused-parameter",
                            message: "'\(normalized)' is never referenced in the '\(macroName)' body, so it cannot bind a placeholder. A standalone bindings struct defers this to execution time, but the signature-driven rewrite can catch it here: reference the parameter in the statement, or remove it."
                        )
                    )
                }
            }
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

        if returnShape.isDirectResult {
            // The rename is lexical and applies only to an unqualified callee.
            // A qualified spelling (`SwiftQL.sqlResult`) cannot be told apart
            // from another object's member of the same name, so it is rejected
            // rather than silently left to trap in the generated builder.
            let qualifiedVisitor = SQLQueryQualifiedEntryPointVisitor(
                entryPointNames: Set(calleeRenames.keys),
                macroName: macroName
            )
            qualifiedVisitor.walk(body)
            guard qualifiedVisitor.diagnostics.isEmpty else {
                throw DiagnosticsError(diagnostics: qualifiedVisitor.diagnostics)
            }
        }
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
            if let collection = collectionDescription(of: parameter.type) {
                // A collection parameter would render a variable-length `IN`
                // list, so the SQL text changes with the element count. That
                // breaks the stable-SQL premise the render-once prepared query
                // depends on (#360, #361), and a single named placeholder cannot
                // bind a list, so the shape is rejected at the declaration site.
                diagnostics.append(
                    Diagnostic(
                        node: parameter.type,
                        id: "sqlquery-collection-parameter",
                        message: "'\(macroName)' cannot bind the \(collection) parameter '\(normalizedIdentifier(name.text))' to a single named placeholder. A variable-length list renders SQL whose text changes with the element count, which breaks the stable-SQL premise the prepared query relies on. Spell the elements in the statement with the 'in(_:)' expression forms, or pass a fixed set of scalar parameters."
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

    ///
    /// Describes a parameter type that spells a collection form (`[T]`,
    /// `[K: V]`, `Array<…>`, `Set<…>`, `Dictionary<…>`), peeling one layer of
    /// optionality. Returns `nil` for scalar types. A single leading optional is
    /// unwrapped so `[T]?` is still recognized as a collection.
    ///
    private static func collectionDescription(of type: TypeSyntax) -> String? {
        var type = type.trimmed
        if let optional = type.as(OptionalTypeSyntax.self) {
            type = optional.wrappedType.trimmed
        }
        else if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            type = unwrapped.wrappedType.trimmed
        }
        if type.is(ArrayTypeSyntax.self) {
            return "array"
        }
        if type.is(DictionaryTypeSyntax.self) {
            return "dictionary"
        }
        if let (name, arguments) = genericConstraint(of: type), arguments != nil {
            switch name {
            case "Array":
                return "array"
            case "Set":
                return "set"
            case "Dictionary":
                return "dictionary"
            default:
                return nil
            }
        }
        return nil
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
/// Rejects qualified calls to a spec entry point in a direct-result body.
///
/// The `sqlResult` -> `sql` swap is lexical and matches only an unqualified
/// callee. A qualified spelling such as `SwiftQL.sqlResult { … }` cannot be
/// distinguished from another object's member of the same name, so it is
/// diagnosed instead of being left to trap at runtime in the generated
/// statement builder.
///
internal final class SQLQueryQualifiedEntryPointVisitor: SyntaxVisitor {

    private let entryPointNames: Set<String>

    private let macroName: String

    private(set) var diagnostics: [Diagnostic] = []

    init(entryPointNames: Set<String>, macroName: String) {
        self.entryPointNames = entryPointNames
        self.macroName = macroName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }
        let name = normalizedIdentifier(callee.declName.baseName.text)
        guard entryPointNames.contains(name) else {
            return .visitChildren
        }
        diagnostics.append(
            Diagnostic(
                node: Syntax(callee),
                id: "sqlquery-qualified-entry-point",
                message: "'\(name)' must be called unqualified in a '\(macroName)' specification. The macro rewrites the entry point lexically and cannot distinguish a module qualifier from another object's member of the same name."
            )
        )
        return .visitChildren
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


///
/// The frozen-literal guard.
///
/// The generated executor renders SQL once per declaration and reuses that
/// text on every call, so any parameter value that escapes the rewrite is
/// baked into the cached SQL on the first invocation and every later call
/// silently returns results for the first call's argument — a silent
/// wrong-results bug (#360). The rewrite can only turn a parameter reference
/// into a named binding when the reference sits directly in a query-expression
/// position (an operand of a comparison such as `column == name`). This guard
/// reports the reference shapes that place a parameter somewhere the rewrite
/// cannot reach, so the hazard becomes a declaration-site error instead.
///
/// Every parameter reference actually seen is recorded in
/// ``referencedParameterNames`` so the builder can additionally flag a
/// parameter that is never referenced at all.
///
internal final class SQLQueryFrozenLiteralGuard: SyntaxVisitor {

    private let parameterNames: Set<String>

    private let macroName: String

    private(set) var diagnostics: [Diagnostic] = []

    /// The normalized names of every parameter referenced anywhere in the body,
    /// including references in hazardous positions.
    private(set) var referencedParameterNames: Set<String> = []

    init(parameters: [SQLQueryParameter], macroName: String = "@SQLQuery") {
        self.parameterNames = Set(parameters.map(\.placeholderName))
        self.macroName = macroName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // A hand-constructed binding reference bypasses the signature contract:
        // the macro is the sole authority for the placeholder name and type, so
        // building one by hand can disagree with the rendered layout.
        if let calleeName = Self.calledBaseName(of: node.calledExpression),
           calleeName == "XLNamedBindingReference" || calleeName == "contextualBinding" {
            diagnostics.append(
                Diagnostic(
                    node: Syntax(node.calledExpression),
                    id: "sqlquery-manual-binding",
                    message: "'\(macroName)' derives every named binding from the function signature, so '\(calleeName)' must not be constructed by hand in the body. A hand-built binding can disagree with the rendered parameter layout. Reference the parameter directly and let the macro generate the binding."
                )
            )
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let identifier = normalizedIdentifier(node.baseName.text)
        guard parameterNames.contains(identifier) else {
            return .visitChildren
        }
        // A member name (`person.name`) is not a reference to the parameter, so
        // it neither counts as a use nor is a hazard — the member-access guard
        // owns the base-of-member-access case.
        if let memberAccess = node.parent?.as(MemberAccessExprSyntax.self),
           memberAccess.declName == node {
            return .visitChildren
        }
        referencedParameterNames.insert(identifier)
        classify(reference: node, identifier: identifier)
        return .visitChildren
    }

    ///
    /// Reports the first recognized hazardous position for a parameter
    /// reference. A reference that matches none of these is left for the
    /// rewrite (typically a comparison operand) and any residual type mismatch
    /// is caught by the compiler on the generated code.
    ///
    private func classify(reference node: DeclReferenceExprSyntax, identifier: String) {
        if hasAncestor(node, upToEnclosingFunction: { $0.is(ExpressionSegmentSyntax.self) }) {
            diagnostics.append(
                Diagnostic(
                    node: node,
                    id: "sqlquery-parameter-string-interpolation",
                    message: "'\(identifier)' is used inside a string interpolation in the '\(macroName)' body, which renders its value into the string rather than binding a placeholder. Build the value into the statement with a comparison against a column, not an interpolated string."
                )
            )
            return
        }
        if closureDepth(of: node) >= 2 {
            diagnostics.append(
                Diagnostic(
                    node: node,
                    id: "sqlquery-parameter-nested-closure",
                    message: "'\(identifier)' is captured by a nested closure in the '\(macroName)' body. The rewrite only reaches references in the statement builder itself, so a value captured deeper can escape into the cached SQL as a frozen literal. Reference the parameter directly in the statement."
                )
            )
            return
        }
        if isDirectCallArgument(node) {
            diagnostics.append(
                Diagnostic(
                    node: node,
                    id: "sqlquery-parameter-call-argument",
                    message: "'\(identifier)' is passed as an argument to a function call in the '\(macroName)' body. The rewrite cannot see through the call, so the value would be frozen into the cached SQL on the first invocation. Use the parameter directly as a comparison operand (for example 'column == \(identifier)') instead of passing it to a helper."
                )
            )
            return
        }
        if isVariableInitializer(node) {
            diagnostics.append(
                Diagnostic(
                    node: node,
                    id: "sqlquery-parameter-local-binding",
                    message: "'\(identifier)' is used to initialize a local binding in the '\(macroName)' body. The binding's later uses are outside the rewrite's reach, so the value can freeze into the cached SQL. Reference the parameter directly in the statement instead of storing it in a local."
                )
            )
            return
        }
    }

    ///
    /// The base identifier of a called expression, peeling a generic
    /// specialization (`XLNamedBindingReference<String>(…)`) and reading the
    /// member name of a member-access callee (`x.contextualBinding(…)`).
    ///
    private static func calledBaseName(of expression: ExprSyntax) -> String? {
        if let declReference = expression.as(DeclReferenceExprSyntax.self) {
            return normalizedIdentifier(declReference.baseName.text)
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return calledBaseName(of: specialization.expression)
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return normalizedIdentifier(memberAccess.declName.baseName.text)
        }
        return nil
    }

    ///
    /// Whether an ancestor up to (but not into) the enclosing specification
    /// function satisfies the predicate.
    ///
    private func hasAncestor(
        _ node: SyntaxProtocol,
        upToEnclosingFunction predicate: (Syntax) -> Bool
    ) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if ancestor.is(FunctionDeclSyntax.self) {
                return false
            }
            if predicate(ancestor) {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    ///
    /// The number of closures enclosing the reference within the specification
    /// function. The statement builder is itself a closure, so a value of one
    /// is the normal case and two or more means a further-nested closure.
    ///
    private func closureDepth(of node: SyntaxProtocol) -> Int {
        var depth = 0
        var current = node.parent
        while let ancestor = current {
            if ancestor.is(FunctionDeclSyntax.self) {
                break
            }
            if ancestor.is(ClosureExprSyntax.self) {
                depth += 1
            }
            current = ancestor.parent
        }
        return depth
    }

    ///
    /// Whether the reference is a direct argument expression of a function
    /// call. A comparison operand's parent is an infix operator expression, and
    /// a parenthesized operand's argument list belongs to a tuple, so neither is
    /// mistaken for a call argument.
    ///
    private func isDirectCallArgument(_ node: DeclReferenceExprSyntax) -> Bool {
        guard let labeled = node.parent?.as(LabeledExprSyntax.self),
              let list = labeled.parent?.as(LabeledExprListSyntax.self) else {
            return false
        }
        return list.parent?.is(FunctionCallExprSyntax.self) == true
    }

    ///
    /// Whether the reference is the initializer value of a local `let`/`var`
    /// binding (`let alias = name`).
    ///
    private func isVariableInitializer(_ node: DeclReferenceExprSyntax) -> Bool {
        hasAncestor(node, upToEnclosingFunction: { ancestor in
            guard let initializer = ancestor.as(InitializerClauseSyntax.self) else {
                return false
            }
            return initializer.parent?.is(PatternBindingSyntax.self) == true
        })
    }
}
