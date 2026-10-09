//
//  SQLFunctionMacro.swift
//
//
//  Created by Luke Van In on 2026/07/24.
//

import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros


///
/// Errors thrown by the `SQLFunction` macro. Thrown errors are reported by the SwiftSyntaxMacros
/// infrastructure as a diagnostic located at the macro attribute, using this type's `description`
/// as the message, mirroring `SQLMacroError`.
///
public enum SQLFunctionMacroError: Error, CustomStringConvertible, LocalizedError {

    /// The macro is attached to a declaration which is not supported, such as a class or an enum.
    case unsupportedType

    public var description: String {
        switch self {
        case .unsupportedType:
            return "'@SQLFunction' can only be applied to a struct."
        }
    }

    public var errorDescription: String? {
        description
    }
}


///
/// Collects the stored properties of a struct annotated with `@SQLFunction`, and generates the
/// `definition` and `makeSQL(context:)` members from them.
///
/// Every stored property becomes one positional SQL function argument, in declaration order. Each
/// property must be typed as an `XLExpression` or an `XLSQLiteExpression` (spelled
/// `any XLExpression<...>`, `some XLExpression<...>`, `any XLSQLiteExpression<...>`, or a
/// module-qualified equivalent) so that its `.makeSQL` method can be referenced directly from the
/// generated code; any other stored property is reported as a diagnostic instead of silently
/// producing code which fails to compile. A custom function runs inside SQLite, and an
/// `XLSQLiteExpression` argument takes only a SQLite expression (issue #789).
///
internal struct FunctionMetaBuilder {

    /// Name of the struct defined in the Swift source file.
    let structName: String

    /// Name of the SQL function used to register with SQLite and emitted in generated SQL.
    /// Defaults to `structName` unless the `name:` parameter is defined on the macro.
    let functionName: String

    /// Ordered names of the stored properties which become SQL function arguments.
    var argumentNames: [String] {
        arguments.map(\.name)
    }

    /// Ordered stored properties which become SQL function arguments.
    let arguments: [FunctionArgument]

    /// Whether the struct declares an initializer of its own, which the
    /// generated one would sit beside rather than replace.
    let declaresInitializer: Bool

    ///
    /// Convenience initializer used to initialise the builder with a `DeclGroupSyntax`.
    /// - throws: `SQLFunctionMacroError.unsupportedType` if the declaration is not a `StructDeclSyntax`
    ///
    init(node: AttributeSyntax, declaration: DeclGroupSyntax) throws {
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            throw SQLFunctionMacroError.unsupportedType
        }
        try self.init(node: node, declaration: declaration)
    }

    ///
    /// Initialises the builder with a node and a declaration.
    ///
    /// - Parameter node: Reference to the macro. E.g. `@SQLFunction(name: "foo")`
    /// - Parameter declaration: Reference to the struct which the macro is defined on.
    ///
    init(node: AttributeSyntax, declaration: StructDeclSyntax) throws {
        self.structName = declaration.name.text

        var diagnostics = MacroDiagnosticCollector()

        // Use the name parameter from the macro if it is defined, otherwise use the name of the
        // enclosing struct as the SQL function name.
        self.functionName = MacroNameArgument.resolve(
            of: node,
            defaultingTo: structName,
            diagnostics: &diagnostics
        )

        let arguments = Self.collectArguments(declaration: declaration, diagnostics: &diagnostics)

        try diagnostics.throwIfNotEmpty()

        self.arguments = arguments
        self.declaresInitializer = Self.declaresInitializer(in: declaration.memberBlock.members)
    }

    ///
    /// Collects the stored properties of the struct, mapping each one to a positional SQL function
    /// argument.
    ///
    /// Every member of the struct is either mapped faithfully to an argument, ignored because it
    /// can never be an argument (methods, initializers, and nested types), or reported as an error
    /// diagnostic located at the offending declaration (e.g. static, lazy, or computed properties,
    /// or a property whose type is not an `XLExpression`). No property is ever silently dropped.
    ///
    private static func collectArguments(
        declaration: StructDeclSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [FunctionArgument] {
        var names: [FunctionArgument] = []
        for member in declaration.memberBlock.members {
            // Members which are not variable declarations (methods, initializers, nested types,
            // subscripts) are never arguments.
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            names.append(contentsOf: collectArguments(variable: variable, diagnostics: &diagnostics))
        }
        return names
    }

    ///
    /// Whether `members` declare an initializer, including one inside an `#if`
    /// clause, which the generated initializer would sit beside rather than
    /// replace, or a stored property inside an `#if` clause, which the
    /// arguments do not include and so the generated initializer would leave
    /// unset.
    ///
    private static func declaresInitializer(in members: MemberBlockItemListSyntax, conditionally: Bool = false) -> Bool {
        members.contains { member in
            if member.decl.is(InitializerDeclSyntax.self) {
                return true
            }
            if conditionally, let variable = member.decl.as(VariableDeclSyntax.self), isStoredInstanceProperty(variable) {
                return true
            }
            guard let ifConfig = member.decl.as(IfConfigDeclSyntax.self) else {
                return false
            }
            return ifConfig.clauses.contains { clause in
                guard case .decls(let nested) = clause.elements else {
                    return false
                }
                return declaresInitializer(in: nested, conditionally: true)
            }
        }
    }

    ///
    /// Whether `variable` declares a stored instance property, which the
    /// memberwise initializer takes: not `static` or `class`, and with a
    /// binding that is not computed.
    ///
    private static func isStoredInstanceProperty(_ variable: VariableDeclSyntax) -> Bool {
        let isTypeMember = variable.modifiers.contains { modifier in
            modifier.name.text == "static" || modifier.name.text == "class"
        }
        guard !isTypeMember else {
            return false
        }
        return variable.bindings.contains { binding in
            guard let accessorBlock = binding.accessorBlock else {
                return true
            }
            return !StoredPropertyClassifier.isComputed(accessorBlock)
        }
    }

    ///
    /// Maps a single variable declaration to zero or more arguments, or appends an error diagnostic
    /// if the declaration cannot be mapped faithfully.
    ///
    private static func collectArguments(
        variable: VariableDeclSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [FunctionArgument] {

        func report(_ node: some SyntaxProtocol, id: String, _ message: String) {
            diagnostics.report(node, id: id, message)
        }

        guard
            StoredPropertyClassifier.accepts(
                variable,
                as: .functionArgument,
                diagnostics: &diagnostics
            )
        else {
            return []
        }

        // A private or fileprivate property narrows the memberwise
        // initializer to the same access, and the generated initializer
        // follows it. A setter-only modifier such as `private(set)` does
        // not narrow it.
        let access = variable.modifiers.compactMap { modifier -> FunctionArgument.Access? in
            guard modifier.detail == nil else {
                return nil
            }
            switch modifier.name.text {
            case "private":
                return .private
            case "fileprivate":
                return .fileprivate
            default:
                return nil
            }
        }.min()
        var names: [FunctionArgument] = []
        for binding in variable.bindings {

            if
                let accessorBlock = binding.accessorBlock,
                StoredPropertyClassifier.isComputed(accessorBlock)
            {
                StoredPropertyClassifier.reportComputed(
                    binding,
                    as: .functionArgument,
                    diagnostics: &diagnostics
                )
                continue
            }

            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                StoredPropertyClassifier.reportUnsupportedPattern(
                    binding.pattern,
                    as: .functionArgument,
                    diagnostics: &diagnostics
                )
                continue
            }
            let name = pattern.identifier.text

            guard let annotation = binding.typeAnnotation else {
                report(
                    binding, id: "missing-type-annotation",
                    "Property '\(name)' needs an explicit type annotation to be used as a function argument."
                )
                continue
            }

            guard isExpressionType(annotation.type) else {
                report(
                    annotation.type, id: "unsupported-argument-type",
                    "Property '\(name)' must be typed as 'any XLExpression<...>' or 'any XLSQLiteExpression<...>' (or the 'some' form of either) to be used as a function argument. Found '\(annotation.type.trimmedDescription)'."
                )
                continue
            }

            names.append(
                FunctionArgument(
                    name: name,
                    sqliteType: sqliteExpressionType(annotation.type),
                    hasInitialValue: binding.initializer != nil,
                    access: access
                )
            )
        }
        return names
    }

    ///
    /// The type of the generated initializer's parameter for a property typed
    /// `type`: `any XLSQLiteExpression` with the property's own generic
    /// arguments, so the argument must be a SQLite expression (issue #822).
    /// `nil` for a property typed `some ...`, which the initializer cannot
    /// take as an existential.
    ///
    private static func sqliteExpressionType(_ type: TypeSyntax) -> String? {
        guard
            let existential = type.as(SomeOrAnyTypeSyntax.self),
            existential.someOrAnySpecifier.tokenKind == .keyword(.any)
        else {
            return nil
        }
        // A module-qualified property type gets a module-qualified parameter
        // type, so a client that qualifies its types to avoid a clash is not
        // exposed to one. The qualifier is the module that declares
        // `XLSQLiteExpression`, whatever module the property named:
        // `XLExpression` is declared in SwiftQLQuery, which has no
        // `XLSQLiteExpression`, and the macro is declared in SwiftQLSQLite, so
        // a file that expands it sees that module (issue #790).
        let constraint = existential.constraint
        if let identifier = constraint.as(IdentifierTypeSyntax.self) {
            let genericArguments = identifier.genericArgumentClause?.trimmedDescription ?? ""
            return "any XLSQLiteExpression\(genericArguments)"
        }
        if let member = constraint.as(MemberTypeSyntax.self) {
            let genericArguments = member.genericArgumentClause?.trimmedDescription ?? ""
            return "any \(EmittedModule.sqlite).XLSQLiteExpression\(genericArguments)"
        }
        return nil
    }

    ///
    /// Determines whether a type annotation is an `XLExpression`, spelled as an existential
    /// (`any XLExpression<...>`), an opaque type (`some XLExpression<...>`), or a module-qualified
    /// equivalent (`any SwiftQL.XLExpression<...>`). A property whose type is a typealias for
    /// `XLExpression`, or a concrete conforming type, is not recognised by this syntactic check —
    /// spell the property using `any`/`some XLExpression` to use it as a function argument.
    ///
    private static func isExpressionType(_ type: TypeSyntax) -> Bool {
        if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            return isExpressionType(existential.constraint)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return expressionTypeNames.contains(identifier.name.text)
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return expressionTypeNames.contains(member.name.text)
        }
        return false
    }

    ///
    /// The expression protocols a property may name: `XLExpression`, which takes an expression
    /// of any dialect, and `XLSQLiteExpression`, which takes only a SQLite expression
    /// (issue #789).
    ///
    private static let expressionTypeNames: Set<String> = [
        "XLExpression",
        "XLSQLiteExpression",
    ]

    // MARK: - Generation

    ///
    /// Generates an initializer that takes each argument as a SQLite
    /// expression, in declaration order, with the labels of the memberwise
    /// initializer it replaces (issue #822).
    ///
    /// A custom function runs inside SQLite, so its arguments are SQLite
    /// expressions. A property typed `any XLExpression<...>` stores any
    /// expression, and the memberwise initializer would take a column of
    /// another dialect's model; this one does not. A struct with no
    /// arguments, an argument with an initial value, or an argument typed
    /// `some ...` keeps its memberwise initializer, which this cannot replace
    /// faithfully, and is not checked; so does a struct with a property inside
    /// an `#if` clause. A struct that declares an initializer,
    /// also inside an `#if` clause, keeps it as written: the initializer's
    /// parameter types decide what it takes. The generated initializer has
    /// the memberwise initializer's access: `private` or `fileprivate` when a
    /// property is.
    ///
    func makeInitializer() -> String? {
        guard !arguments.isEmpty, !declaresInitializer else {
            return nil
        }
        var parameters: [String] = []
        for argument in arguments {
            guard !argument.hasInitialValue, let type = argument.sqliteType else {
                return nil
            }
            parameters.append("\(argument.name): \(type)")
        }
        let access = arguments.compactMap(\.access).min().map { "\($0.rawValue) " } ?? ""
        var context = CodeWriter()
        context.block("\(access)init(\(parameters.joined(separator: ", ")))") { context in
            for argument in arguments {
                context.line("self.\(argument.name) = \(argument.name)")
            }
        }
        return context.build()
    }

    ///
    /// Generates the `definition` static property from the function name and argument count.
    ///
    func makeDefinitionDecl() -> String {
        "public static let definition = XLCustomFunctionDefinition(name: \(quoted(functionName)), numberOfArguments: \(argumentNames.count))"
    }

    ///
    /// Generates the `makeSQL(context:)` implementation, emitting one `listItem` call per
    /// argument, in declaration order.
    ///
    func makeMakeSQLFunction() -> String {
        var context = CodeWriter()
        context.block("public func makeSQL(context: inout XLBuilder)") { context in
            context.block(
                "context.simpleFunction(name: Self.definition.name)",
                opening: argumentNames.isEmpty ? " { _ in" : " { context in",
                closing: "}"
            ) { context in
                for name in argumentNames {
                    context.line("context.listItem(expression: \(name).makeSQL)")
                }
            }
        }
        return context.build()
    }

}


///
/// One stored property of a custom function: one positional SQL argument.
///
internal struct FunctionArgument {

    /// The property's name, which is also the initializer's argument label.
    let name: String

    /// The generated initializer's parameter type, or `nil` when the property
    /// is typed in a form the initializer cannot take.
    let sqliteType: String?

    /// Whether the property has an initial value, which the memberwise
    /// initializer makes optional.
    let hasInitialValue: Bool

    /// The property's access when it narrows the memberwise initializer's:
    /// `private` or `fileprivate`, and `nil` otherwise.
    let access: Access?

    /// An access level narrower than the memberwise initializer's default.
    enum Access: String, Comparable {
        case `private`
        case `fileprivate`

        static func < (lhs: Access, rhs: Access) -> Bool {
            lhs == .private && rhs == .fileprivate
        }
    }
}


///
/// Declares a struct as a custom SQL scalar function.
///
/// Generates the ``XLCustomFunction/definition`` (name + argument count) and the
/// `makeSQL(context:)` implementation from the struct's stored properties, each of which becomes
/// one positional SQL function argument in declaration order. The conformance to
/// `XLCustomFunction` and the `execute(reader:)` implementation — the actual computation — are
/// still written by hand.
///
public struct SQLFunctionMacro {
}

extension SQLFunctionMacro: MemberMacro {

    ///
    /// Generates the `definition` and `makeSQL(context:)` members for a custom function struct.
    ///
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let builder = try FunctionMetaBuilder(node: node, declaration: declaration)
        var declarations = [
            try makeDecl(builder.makeDefinitionDecl()),
            try makeDecl(builder.makeMakeSQLFunction()),
        ]
        if let initializer = builder.makeInitializer() {
            declarations.append(try makeDecl(initializer))
        }
        return declarations
    }
}
