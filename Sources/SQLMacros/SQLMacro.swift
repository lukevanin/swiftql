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


/// Access-level modifiers whose types Swift refuses to infer `Sendable` for.
///
/// A conformance a *different* module can see is an API promise, and Swift makes the declaring
/// module state such a promise on purpose rather than inferring it. Everything narrower than this
/// is inferred, so the macro has nothing to add there -- see `makeSendableExtension`.
private let sendableInferenceWithheldModifiers: Set<String> = ["public", "open", "package"]


///
/// Builds the `Sendable` conformance both `SQLTableMacro` and `SQLResultMacro` declare (issue
/// #531), or returns `nil` if the model does not need one.
///
/// A generated model is a struct whose stored properties are column values, so it is a value type
/// built from value types and is `Sendable` in every ordinary case. Swift infers exactly that for
/// such a struct on its own -- but not for one another module can see. The inference is withheld
/// from `public` (and `package`) types on purpose, because a conformance visible outside the
/// module is an API promise the declaring module has to make deliberately. Model types are exactly
/// the types users declare `public` and read on one task to use on another, so before this the
/// promise had to be written out by hand at every public declaration -- or the caller had to reach
/// for `nonisolated(unsafe)`, which switches the checking off rather than satisfying it.
///
/// So the macro fills in precisely the gap the inference leaves, and nothing more:
///
/// - **Only where inference is withheld.** An `internal`, `fileprivate`, or `private` model
///   already gets a compiler-inferred conformance, derived from its actual stored properties and
///   therefore strictly more precise than anything spelled here. Generating a second, redundant
///   one buys nothing and can only take something away: an internal model with a non-`Sendable`
///   stored property is diagnosed under an explicit conformance where the inference simply
///   declines to apply.
/// - **Checked, not asserted.** `extension Model: Sendable {}` is an ordinary conformance, so a
///   stored property whose type is not `Sendable` is diagnosed by the compiler on the generated
///   extension. The macro never writes `@unchecked`, so no model silently claims to be `Sendable`
///   when it is not.
/// - **Deferring to the declaration.** `protocols` holds only the conformances from the macro's
///   `conformances:` list that the type does not already have, so a model declared `: Sendable` --
///   or `: @unchecked Sendable`, the escape hatch for a property whose safety its author vouches
///   for -- yields an empty list here and no generated extension. That keeps the change
///   source-compatible with models that already state the conformance, such as the `TodoKit`
///   schema in `Examples/TodoApp`.
/// - **Non-generic models only.** A generic model would need a *conditional* conformance, one
///   `Sendable` requirement per generic parameter, the way the compiler's own inference produces
///   one. An extension macro cannot write that: resolving the `where` clause needs the type's
///   generic signature, resolving that needs every extension of the type, and expanding those
///   extension macros is where the requirement came from, so the compiler stops with `circular
///   reference expanding extension macros`. It is a real cycle, not a diagnostic quirk, and it
///   fires on `public` and `private` generic models alike. SwiftQL ships generic models itself --
///   `SQLScalarResult<T>` and `SQLRow2<C0, C1>`...`SQLRow6`, the row shapes behind `#row` -- so
///   this is not hypothetical. They are left as they were: a generic model that should be
///   `Sendable` says so itself, `extension MyRow: Sendable where T: Sendable {}`, and the macro
///   then defers to it like any other stated conformance.
/// - **Swift 6.0 and later only.** Swift 5.9 treats a macro-expanded extension as a separate
///   source file for the rule that a `Sendable` conformance must be declared alongside its type,
///   and warns `conformance to 'Sendable' must occur in the same source file as struct 'X'; use
///   '@unchecked Sendable' for retroactive conformance` on every model. The suggested spelling is
///   the one thing this change exists to avoid, so the 5.9 support point keeps the behaviour it
///   had and models there state the conformance themselves if they want it. The plugin is built
///   by the same toolchain that compiles the client, so `#if compiler(>=6.0)` below decides this
///   per compilation rather than per plugin build. See COMPATIBILITY.md.
///
private func makeSendableExtension(
    builder: MetaBuilder,
    conformingTo protocols: [TypeSyntax]
) throws -> ExtensionDeclSyntax? {
#if compiler(>=6.0)
    let requested = protocols.contains { type in
        // Matched by spelling because the syntax the compiler hands back carries no resolved
        // type. Both the bare and module-qualified spellings are accepted, and nothing else is,
        // so some other protocol whose name merely ends in "Sendable" cannot be mistaken for it.
        let name = type.trimmedDescription
        return name == "Sendable" || name == "Swift.Sendable"
    }
    guard requested else {
        return nil
    }
    let visibleOutsideModule = builder.declaration.modifiers.contains { modifier in
        sendableInferenceWithheldModifiers.contains(modifier.name.text)
    }
    guard visibleOutsideModule else {
        return nil
    }
    guard builder.declaration.genericParameterClause == nil else {
        return nil
    }
    return try makeExtensionDecl("extension \(builder.structName): Sendable {\n}")
#else
    return nil
#endif
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
        var extensions = [
            try makeExtensionDecl(builder.makeMetaResultExtension(table: true)),
            try makeExtensionDecl(builder.makeMetaTableExtension()),
        ]
        if let sendable = try makeSendableExtension(builder: builder, conformingTo: protocols) {
            extensions.append(sendable)
        }
        return extensions
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
        var extensions = [
            try makeExtensionDecl(builder.makeMetaResultExtension(table: false)),
        ]
        if let sendable = try makeSendableExtension(builder: builder, conformingTo: protocols) {
            extensions.append(sendable)
        }
        return extensions
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
        SQLRowMacro.self,
    ]
}
