import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros



public enum SQLMacroError: LocalizedError {
    case unsupportedType
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
            DeclSyntax(stringLiteral: builder.makeMemberwizeInitializer())
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
        let builder = try MetaBuilder(node: node, declaration: declaration)
        return [
            ExtensionDeclSyntax(DeclSyntax(stringLiteral: builder.makeMetaResultExtension(table: true)))!,
            ExtensionDeclSyntax(DeclSyntax(stringLiteral: builder.makeMetaTableExtension()))!
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
            DeclSyntax(stringLiteral: builder.makeMemberwizeInitializer())
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
        let builder = try MetaBuilder(node: node, declaration: declaration)
        return [
            ExtensionDeclSyntax(DeclSyntax(stringLiteral: builder.makeMetaResultExtension(table: false)))!,
        ]
    }
}


@main struct SQLPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SQLTableMacro.self,
        SQLResultMacro.self,
    ]
}
