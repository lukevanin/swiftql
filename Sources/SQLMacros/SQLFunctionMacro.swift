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
import SwiftSyntaxBuilder
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
/// property must be typed as an `XLExpression` (spelled `any XLExpression<...>`, `some
/// XLExpression<...>`, or a module-qualified equivalent) so that its `.makeSQL` method can be
/// referenced directly from the generated code; any other stored property is reported as a
/// diagnostic instead of silently producing code which fails to compile.
///
internal struct FunctionMetaBuilder {

    /// Name of the struct defined in the Swift source file.
    let structName: String

    /// Name of the SQL function used to register with SQLite and emitted in generated SQL.
    /// Defaults to `structName` unless the `name:` parameter is defined on the macro.
    let functionName: String

    /// Ordered names of the stored properties which become SQL function arguments.
    let argumentNames: [String]

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

        let argumentNames = Self.collectArguments(declaration: declaration, diagnostics: &diagnostics)

        try diagnostics.throwIfNotEmpty()

        self.argumentNames = argumentNames
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
    ) -> [String] {
        var names: [String] = []
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
    /// Maps a single variable declaration to zero or more arguments, or appends an error diagnostic
    /// if the declaration cannot be mapped faithfully.
    ///
    private static func collectArguments(
        variable: VariableDeclSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [String] {

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

        var names: [String] = []
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
                    "Property '\(name)' must be typed as 'any XLExpression<...>' (or 'some XLExpression<...>') to be used as a function argument. Found '\(annotation.type.trimmedDescription)'."
                )
                continue
            }

            names.append(name)
        }
        return names
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
            return identifier.name.text == "XLExpression"
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == "XLExpression"
        }
        return false
    }

    // MARK: - Generation

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
        var context = SwiftSyntaxBuilder()
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
        return [
            DeclSyntax(stringLiteral: builder.makeDefinitionDecl()),
            DeclSyntax(stringLiteral: builder.makeMakeSQLFunction()),
        ]
    }
}
