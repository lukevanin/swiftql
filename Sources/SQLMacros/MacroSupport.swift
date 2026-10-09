//
//  MacroSupport.swift
//  SwiftQL
//
//  Parsing and diagnostic pieces shared by the macro builders (issue #562).
//  `FunctionMetaBuilder` began as a fork of `MetaBuilder`'s parse half, so both
//  carried their own copy of the `name:` argument parse, the source-ordered
//  diagnostic throw, the stored-property modifier rejection, and the
//  computed-accessor test -- identical code with the same diagnostic ids and
//  messages differing only in the noun for what a property becomes.
//

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax


///
/// Accumulates macro diagnostics and throws them in source order.
///
/// A builder classifies every member of a declaration before failing, so one
/// invalid declaration reports a complete set of errors rather than only the
/// first. Members are not visited in source order -- bindings are resolved in
/// reverse so a shared type annotation can be carried backwards -- so the
/// collected diagnostics are sorted before they are thrown.
///
internal struct MacroDiagnosticCollector {

    private(set) var diagnostics: [Diagnostic] = []

    var isEmpty: Bool {
        diagnostics.isEmpty
    }

    ///
    /// Records one error diagnostic located at `node`.
    ///
    mutating func report(_ node: some SyntaxProtocol, id: String, _ message: String) {
        diagnostics.append(Diagnostic(node: node, id: id, message: message))
    }

    ///
    /// Records a diagnostic built elsewhere, such as an argument's.
    ///
    mutating func report(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
    }

    ///
    /// Throws every collected diagnostic, in source order, or returns if none
    /// were collected.
    ///
    func throwIfNotEmpty() throws {
        guard !diagnostics.isEmpty else {
            return
        }
        let sorted = diagnostics.sorted {
            $0.node.positionAfterSkippingLeadingTrivia < $1.node.positionAfterSkippingLeadingTrivia
        }
        throw DiagnosticsError(diagnostics: sorted)
    }
}


///
/// Resolves the optional `name:` argument shared by `@SQLTable`, `@SQLResult`,
/// and `@SQLFunction`.
///
internal enum MacroNameArgument {

    ///
    /// Returns the SQL name the macro was given, or `fallback` when the
    /// argument is absent.
    ///
    /// The argument has to be a plain string literal: it is baked into
    /// generated source at expansion time, where an interpolation has no value
    /// to read. An interpolated one is reported and `fallback` is used, so the
    /// rest of the declaration still gets classified and reports its own
    /// problems in the same pass.
    ///
    /// The literal's *represented value* is what is returned, not its source
    /// text. The two differ for a raw string (`#"a"b"#` is written without
    /// escapes) and for an escaped one (`"a\"b"` is written with a backslash
    /// that is not part of the name), and it is the represented value that is
    /// the SQL name. ``quoted(_:)`` puts the escapes back when the name is
    /// emitted into generated source.
    ///
    static func resolve(
        of node: AttributeSyntax,
        defaultingTo fallback: String,
        diagnostics: inout MacroDiagnosticCollector
    ) -> String {
        guard
            case let .argumentList(arguments) = node.arguments,
            let nameArgument = arguments.first(where: { $0.label?.text == "name" })
        else {
            return fallback
        }
        guard
            let literal = nameArgument.expression.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            case .stringSegment = literal.segments.first,
            let name = literal.representedLiteralValue
        else {
            diagnostics.report(
                nameArgument.expression,
                id: "invalid-name-argument",
                "The 'name' argument must be a simple string literal without interpolation. Remove the interpolation, or omit the argument to use the name of the struct."
            )
            return fallback
        }
        return name
    }
}


///
/// Resolves the optional `dialect:` argument shared by `@SQLQuery`,
/// `@SQLQueries`, and `@SQLBindings` (issue #687), and by `@SQLTable` and
/// `@SQLResult` (issue #789).
///
internal enum MacroDialectArgument {

    ///
    /// The dialect generated code names when the attribute names none, for a
    /// model and for a declared query alike.
    ///
    /// The dialect-less overloads are declared in `SwiftQLSQLite`, whose
    /// default dialect is SQLite, so an attribute without the argument
    /// expands to what it always meant. Module-qualified, because the
    /// expansion is in the user's file, which may also import a module with a
    /// type of the same name (issue #789). The module is `SwiftQLSQLite`, so a
    /// file that imports it alone can expand them, and the spelling stays
    /// valid if the type itself later moves out of `SwiftQLCore`, because
    /// `SwiftQLSQLite` re-exports it (issue #790).
    ///
    static let defaultDialectType = "SwiftQLSQLite.XLSQLiteDialect"

    ///
    /// Returns the dialect type the attribute names, as source text, or
    /// ``defaultDialectType`` when the argument is absent.
    ///
    /// The macro declaration types the argument as `Dialect.Type`, so the
    /// compiler has already checked that it names a dialect. The macro still
    /// needs the type's *spelling*, to write it into the generated code, so
    /// the argument has to be written as `SomeDialect.self`. Any other
    /// expression of the right type -- a variable holding the metatype, a
    /// call, a parenthesised type -- is reported, because generated code
    /// cannot name its type.
    ///
    /// The check is syntactic, so it cannot tell a variable written
    /// `dialect.self` from a type. That spelling reaches the generated code,
    /// and the compiler reports it there.
    ///
    /// A reported argument is returned as a diagnostic, with
    /// `defaultDialectType` in its place, rather than thrown: the caller adds
    /// it to the diagnostics it collects from the rest of the declaration, so
    /// one compile reports every problem.
    ///
    static func resolve(
        of node: AttributeSyntax,
        macroName: String
    ) -> (dialectType: String, diagnostic: Diagnostic?) {
        guard
            case let .argumentList(arguments) = node.arguments,
            let dialectArgument = arguments.first(where: { $0.label?.text == "dialect" })
        else {
            return (defaultDialectType, nil)
        }
        guard
            let memberAccess = dialectArgument.expression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.tokenKind == .keyword(.self),
            memberAccess.declName.argumentNames == nil,
            let base = memberAccess.base,
            isTypeName(base)
        else {
            let diagnostic = Diagnostic(
                node: dialectArgument.expression,
                id: "invalid-dialect-argument",
                message: "The 'dialect' argument of '\(macroName)' must name the dialect type directly, as 'SomeDialect.self'. The generated code writes that type, so it cannot be read from a variable."
            )
            return (defaultDialectType, diagnostic)
        }
        return (base.trimmedDescription, nil)
    }

    ///
    /// Whether `expression` spells a type the generated code can write in a
    /// type position, followed by `.Value`: a name, a qualified name, or
    /// either with generic arguments. A parenthesised or computed base also
    /// type-checks as a metatype, but `(SomeDialect).Value` is not a type.
    ///
    private static func isTypeName(_ expression: ExprSyntax) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.argumentNames == nil
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            guard let base = member.base, member.declName.argumentNames == nil else {
                return false
            }
            return isTypeName(base)
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return isTypeName(specialization.expression)
        }
        return false
    }
}


///
/// Names what the stored properties of a macro-annotated struct become, so the
/// shared classification diagnostics read naturally for each macro.
///
internal struct StoredPropertyRole {

    /// Plural, as in "cannot be used as _columns_".
    let plural: String

    /// Singular with its article, as in "cannot be used as _a column_".
    let singular: String

    /// Singular without an article, as in "declare each _column_ as a separate
    /// property".
    let item: String

    /// What moving a property to an extension excludes it from, as in "to
    /// exclude it from _the generated columns_".
    let exclusion: String

    /// The columns of an `@SQLTable` / `@SQLResult` model.
    static let column = Self(
        plural: "columns",
        singular: "a column",
        item: "column",
        exclusion: "the generated columns"
    )

    /// The positional arguments of an `@SQLFunction` custom function.
    static let functionArgument = Self(
        plural: "function arguments",
        singular: "a function argument",
        item: "argument",
        exclusion: "the generated 'makeSQL' implementation"
    )

    /// The named bindings of an `@SQLBindings` packet.
    static let namedBinding = Self(
        plural: "named bindings",
        singular: "a named binding",
        item: "binding",
        exclusion: "the generated binding packet"
    )
}


///
/// The stored-property tests every macro builder applies before mapping a
/// declaration, phrased for the role the properties play.
///
internal enum StoredPropertyClassifier {

    ///
    /// Reports the modifiers and binding specifier that disqualify a whole
    /// variable declaration, returning `false` when one was found.
    ///
    /// A rejected declaration yields no properties at all, so the caller stops
    /// rather than resolving bindings whose meaning it already reported.
    ///
    static func accepts(
        _ variable: VariableDeclSyntax,
        as role: StoredPropertyRole,
        diagnostics: inout MacroDiagnosticCollector
    ) -> Bool {
        for modifier in variable.modifiers {
            switch modifier.name.text {
            case "static", "class":
                diagnostics.report(
                    modifier,
                    id: "static-property",
                    "'\(modifier.name.text)' properties cannot be used as \(role.plural). Move the property to an extension of the type to exclude it from \(role.exclusion)."
                )
                return false
            case "lazy":
                diagnostics.report(
                    modifier,
                    id: "lazy-property",
                    "'lazy' properties cannot be used as \(role.plural). Use a plain stored property instead."
                )
                return false
            case "weak", "unowned":
                diagnostics.report(
                    modifier,
                    id: "reference-modifier",
                    "'\(modifier.name.text)' properties cannot be used as \(role.plural). Use a plain stored property instead."
                )
                return false
            default:
                // Access control and other modifiers do not affect generation.
                break
            }
        }
        switch variable.bindingSpecifier.text {
        case "var", "let":
            return true
        default:
            diagnostics.report(
                variable.bindingSpecifier,
                id: "binding-specifier",
                "'\(variable.bindingSpecifier.text)' properties cannot be used as \(role.plural). Use 'var' or 'let'."
            )
            return false
        }
    }

    ///
    /// Reports a computed property, which has no storage to read or write.
    ///
    static func reportComputed(
        _ binding: PatternBindingSyntax,
        as role: StoredPropertyRole,
        diagnostics: inout MacroDiagnosticCollector
    ) {
        diagnostics.report(
            binding,
            id: "computed-property",
            "Computed properties cannot be used as \(role.plural). Move the property to an extension of the type to exclude it from \(role.exclusion)."
        )
    }

    ///
    /// Reports a binding pattern that names no single property, such as a tuple
    /// destructuring.
    ///
    static func reportUnsupportedPattern(
        _ pattern: PatternSyntax,
        as role: StoredPropertyRole,
        diagnostics: inout MacroDiagnosticCollector
    ) {
        diagnostics.report(
            pattern,
            id: "unsupported-pattern",
            "Pattern '\(pattern.trimmedDescription)' cannot be used as \(role.singular). Declare each \(role.item) as a separate property with its own name and type."
        )
    }

    ///
    /// Determines whether an accessor block belongs to a computed property.
    /// Stored properties may legitimately define `willSet` and `didSet`
    /// observers.
    ///
    static func isComputed(_ accessorBlock: AccessorBlockSyntax) -> Bool {
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
}


///
/// Renders a declaration's modifiers as the prefix of a generated declaration,
/// so a generated member inherits the access level of whatever it is generated
/// from.
///
/// Returns an empty string -- not a stray space -- when there are no modifiers.
///
internal func macroModifierPrefix(_ modifiers: DeclModifierListSyntax) -> String {
    let description = modifiers.trimmedDescription
    if description.isEmpty {
        return ""
    }
    return description + " "
}


///
/// Renders a string as a Swift string literal in generated source.
///
/// The escaping is not decoration. A name reaching here is a *value* -- an
/// `@SQLTable(name:)` argument the author may have written as a raw string, a
/// property name, a column alias -- and pasting a value containing `"` or `\\`
/// between quotes produces source that does not parse. Before issue #563 this
/// only added the quotes, so `@SQLTable(name: #"my"table"#)` expanded to
/// `name: "my"table"` and the annotated declaration failed to compile with
/// errors pointing at generated code.
///
internal func quoted(_ input: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(input.count + 2)
    for character in input {
        switch character {
        case "\\":
            escaped += "\\\\"
        case "\"":
            escaped += "\\\""
        case "\n":
            escaped += "\\n"
        case "\r":
            escaped += "\\r"
        case "\t":
            escaped += "\\t"
        case "\0":
            escaped += "\\0"
        default:
            escaped.append(character)
        }
    }
    return "\"" + escaped + "\""
}


///
/// Parses one generated declaration, failing loudly when what the macro built
/// does not parse.
///
/// `DeclSyntax(stringLiteral:)` never fails. It parses whatever it is handed
/// and leaves error nodes in the tree, which the compiler then reports against
/// the *expansion* -- so a single missing brace or malformed signature in a
/// generated member surfaces as a wall of errors about code the author never
/// wrote. Checking `hasError` here turns that into one diagnostic that names
/// the generated source, which is a SwiftQL bug report rather than a puzzle for
/// whoever wrote the annotated declaration.
///
/// - throws: ``SQLMacroError/invalidGeneratedCode(_:)`` carrying `source`.
///
internal func makeDecl(_ source: String) throws -> DeclSyntax {
    let declaration = DeclSyntax(stringLiteral: source)
    guard !declaration.hasError else {
        throw SQLMacroError.invalidGeneratedCode(source)
    }
    return declaration
}
