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
            case let .stringSegment(name)? = literal.segments.first
        else {
            diagnostics.report(
                nameArgument.expression,
                id: "invalid-name-argument",
                "The 'name' argument must be a simple string literal without interpolation. Remove the interpolation, or omit the argument to use the name of the struct."
            )
            return fallback
        }
        return name.content.text
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
/// Surrounds a string with quote `"` characters for emission as a Swift string
/// literal in generated source.
///
internal func quoted(_ input: String) -> String {
    "\"\(input)\""
}
