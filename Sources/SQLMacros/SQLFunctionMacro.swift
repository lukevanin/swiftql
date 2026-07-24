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

        var diagnostics: [Diagnostic] = []

        // Use the name parameter from the macro if it is defined, otherwise use the name of the
        // enclosing struct as the SQL function name.
        if
            case let .argumentList(arguments) = node.arguments,
            let nameArg = arguments.first(where: { $0.label?.text == "name" })
        {
            if
                let nameLiteral = nameArg.expression.as(StringLiteralExprSyntax.self),
                nameLiteral.segments.count == 1,
                case let .stringSegment(nameString)? = nameLiteral.segments.first
            {
                self.functionName = nameString.content.text
            }
            else {
                diagnostics.append(
                    Diagnostic(
                        node: nameArg.expression,
                        id: "invalid-name-argument",
                        message: "The 'name' argument must be a simple string literal without interpolation. Remove the interpolation, or omit the argument to use the name of the struct."
                    )
                )
                self.functionName = structName
            }
        }
        else {
            self.functionName = structName
        }

        let argumentNames = Self.collectArguments(declaration: declaration, diagnostics: &diagnostics)

        guard diagnostics.isEmpty else {
            // Report the diagnostics in source order, regardless of the order in which the
            // declarations were classified.
            let sorted = diagnostics.sorted {
                $0.node.positionAfterSkippingLeadingTrivia < $1.node.positionAfterSkippingLeadingTrivia
            }
            throw DiagnosticsError(diagnostics: sorted)
        }

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
        diagnostics: inout [Diagnostic]
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
        diagnostics: inout [Diagnostic]
    ) -> [String] {

        func report(_ node: some SyntaxProtocol, id: String, _ message: String) {
            diagnostics.append(Diagnostic(node: node, id: id, message: message))
        }

        for modifier in variable.modifiers {
            switch modifier.name.text {
            case "static", "class":
                report(
                    modifier, id: "static-property",
                    "'\(modifier.name.text)' properties cannot be used as function arguments. Move the property to an extension of the type to exclude it from the generated 'makeSQL' implementation."
                )
                return []
            case "lazy":
                report(
                    modifier, id: "lazy-property",
                    "'lazy' properties cannot be used as function arguments. Use a plain stored property instead."
                )
                return []
            case "weak", "unowned":
                report(
                    modifier, id: "reference-modifier",
                    "'\(modifier.name.text)' properties cannot be used as function arguments. Use a plain stored property instead."
                )
                return []
            default:
                // Access control and other modifiers do not affect argument generation.
                break
            }
        }

        switch variable.bindingSpecifier.text {
        case "var", "let":
            break
        default:
            report(
                variable.bindingSpecifier, id: "binding-specifier",
                "'\(variable.bindingSpecifier.text)' properties cannot be used as function arguments. Use 'var' or 'let'."
            )
            return []
        }

        var names: [String] = []
        for binding in variable.bindings {

            if let accessorBlock = binding.accessorBlock, isComputed(accessorBlock) {
                report(
                    binding, id: "computed-property",
                    "Computed properties cannot be used as function arguments. Move the property to an extension of the type to exclude it from the generated 'makeSQL' implementation."
                )
                continue
            }

            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                report(
                    binding.pattern, id: "unsupported-pattern",
                    "Pattern '\(binding.pattern.trimmedDescription)' cannot be used as a function argument. Declare each argument as a separate property with its own name and type."
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
    /// Determines whether an accessor block belongs to a computed property. Stored properties may
    /// legitimately define `willSet` and `didSet` observers.
    ///
    private static func isComputed(_ accessorBlock: AccessorBlockSyntax) -> Bool {
        switch accessorBlock.accessors {
        case .getter:
            return true
        case .accessors(let accessors):
            return accessors.contains { accessor in
                switch accessor.accessorSpecifier.text {
                case "willSet", "didSet":
                    return false
                default:
                    return true
                }
            }
        }
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

    ///
    /// Helper method used to surround a string with quote `"` characters.
    ///
    private func quoted(_ input: String) -> String {
        "\"\(input)\""
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
