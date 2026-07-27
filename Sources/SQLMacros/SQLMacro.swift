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


///
/// Shared member list for `SQLTableMacro` and `SQLResultMacro`: the memberwise initializer,
/// projection factory, static row-layout factory, and (issue #66) the declaration-level codec
/// metadata -- the stable per-property codec-key dictionary and one `staticResultField(_:...)`
/// convenience per `@SQLCodec`-annotated property. Kept in one place so both macros stay in sync.
private func makeCodecAwareMembers(builder: MetaBuilder) throws -> [DeclSyntax] {
    var members: [DeclSyntax] = [
        DeclSyntax(stringLiteral: builder.makeMemberwizeInitializer()),
        DeclSyntax(stringLiteral: builder.makeColumnsFunction()),
        DeclSyntax(stringLiteral: builder.makeStaticRowLayoutFunction()),
        DeclSyntax(stringLiteral: builder.makeCodecKeysDeclaration()),
    ]
    members.append(
        contentsOf: builder.makeCodecResultFieldFunctions().map {
            DeclSyntax(stringLiteral: $0)
        }
    )
    return members
}


// MARK: - SQLCodecMacro


///
/// Declares one stored property's contextual value-codec selection (issue #66).
///
/// `@SQLCodec` carries no storage and expands to no declarations of its own: `SQLTableMacro` and
/// `SQLResultMacro` read the attribute directly from the property's syntax while walking the
/// struct's members (see `MetaBuilder.collectCodecSelector`), and thread the codec key it names
/// into that property's generated `staticResultField(_:...)` convenience and into the type's
/// `_swiftQLPropertyCodecKeys` metadata. The Swift compiler enforces that the argument is a
/// genuine `XLValueCodecKey` value through this macro's own declared signature in
/// `Sources/SwiftQL/SQL.swift`; SwiftQL's runtime precedence (`XLValueCodingConfiguration`) still
/// validates the codec's Swift value type, dialect, and registration when the selection is
/// resolved, since a registry is a runtime value no macro can see.
///
public struct SQLCodecMacro {
}

extension SQLCodecMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
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
        return try makeCodecAwareMembers(builder: builder)
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
        return try makeCodecAwareMembers(builder: builder)
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
        SQLQueryMacro.self,
        SQLQueriesMacro.self,
        SQLFunctionMacro.self,
        SQLCodecMacro.self,
    ]
}
