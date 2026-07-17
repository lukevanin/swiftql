import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros



public enum SQLMacroError: Error, CustomStringConvertible, LocalizedError {

    /// The macro is attached to a declaration which is not supported, such as a class or an enum.
    case unsupportedType

    /// The macro generated code which could not be parsed. This indicates a bug in SwiftQL.
    case invalidGeneratedCode

    public var description: String {
        switch self {
        case .unsupportedType:
            return "'@SQLTable' and '@SQLResult' can only be applied to a struct."
        case .invalidGeneratedCode:
            return "The macro generated invalid code. This is a bug in SwiftQL - please report it."
        }
    }

    public var errorDescription: String? {
        description
    }
}


///
/// Parses generated source code as an extension declaration.
///
/// - throws: `SQLMacroError.invalidGeneratedCode` if the source does not parse to an extension
/// declaration, instead of crashing the compiler plugin.
///
private func makeExtensionDecl(_ source: String) throws -> ExtensionDeclSyntax {
    guard let extensionDecl = ExtensionDeclSyntax(DeclSyntax(stringLiteral: source)) else {
        throw SQLMacroError.invalidGeneratedCode
    }
    return extensionDecl
}


// MARK: - SQLTableMacro


///
/// Declares a struct as an SQL table.
///
public struct SQLTableMacro {
}

extension SQLTableMacro: MemberMacro {

    ///
    /// Generates a memberwise initializer for a table struct.
    ///
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let builder = try MetaBuilder(node: node, declaration: declaration)
        return [
            DeclSyntax(stringLiteral: builder.makeMemberwizeInitializer()),
            DeclSyntax(stringLiteral: builder.makeColumnsFunction()),
        ]
    }
}

extension SQLTableMacro: ExtensionMacro {

    ///
    /// Generates structs and methods for a table struct.
    ///
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let builder: MetaBuilder
        do {
            builder = try MetaBuilder(node: node, declaration: declaration)
        }
        catch is DiagnosticsError, is SQLMacroError {
            // The member expansion reports the diagnostics for an invalid declaration. The same
            // errors are not reported again here to avoid emitting duplicate diagnostics.
            return []
        }
        return [
            try makeExtensionDecl(builder.makeMetaResultExtension(table: true)),
            try makeExtensionDecl(builder.makeMetaTableExtension()),
        ]
    }
}


// MARK: - SQLResultMacro


///
/// Declares a struct as an SQL column set.
///
public struct SQLResultMacro {
}

extension SQLResultMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let builder = try MetaBuilder(node: node, declaration: declaration)
        return [
            DeclSyntax(stringLiteral: builder.makeMemberwizeInitializer()),
            DeclSyntax(stringLiteral: builder.makeColumnsFunction()),
        ]
    }
}

extension SQLResultMacro: ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let builder: MetaBuilder
        do {
            builder = try MetaBuilder(node: node, declaration: declaration)
        }
        catch is DiagnosticsError, is SQLMacroError {
            // The member expansion reports the diagnostics for an invalid declaration. The same
            // errors are not reported again here to avoid emitting duplicate diagnostics.
            return []
        }
        return [
            try makeExtensionDecl(builder.makeMetaResultExtension(table: false)),
        ]
    }
}


@main struct SQLPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SQLTableMacro.self,
        SQLResultMacro.self,
    ]
}
