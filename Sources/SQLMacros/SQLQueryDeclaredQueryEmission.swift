//
//  SQLQueryDeclaredQueryEmission.swift
//  SwiftQL
//
//  Issue #659: emission of the data a declared query carries about itself.
//  `@SQLQuery` adds one `<name>DeclaredQuery()` method beside each
//  declaration, and `@SQLQueries` adds a `declaredQueries` property to its
//  `Context` and to the extended type. The generic runtime in
//  `SQLDeclaredQuery.swift` assembles that data into a static descriptor.
//
//  Every member is an instance member, and none copies a specification body
//  into a new context. The peer calls the existing `<name>Statement()` peer.
//  The container evaluates each body inside `Context`, exactly where its
//  executor already evaluates it. A body that compiles for the executor
//  therefore compiles here, including one that reads the database instance.
//

import Foundation
import SwiftSyntax


///
/// The modifiers a generated declared-query member keeps from its source.
///
/// Only access-level modifiers carry over, with `open` spelled `public`
/// because a member of an extension cannot be `open`. `mutating` carries
/// over when asked, because the peer calls a `mutating` statement builder.
/// Everything else (`nonisolated`, `override`, `final`, a setter access
/// such as `private(set)`, ...) is dropped: it describes the executor, not
/// the descriptor.
///
internal func declaredQueryModifierPrefix(
    _ modifiers: DeclModifierListSyntax,
    keepingMutating: Bool
) -> String {
    var kept: [String] = []
    for modifier in modifiers where modifier.detail == nil {
        switch modifier.name.text {
        case "public", "package", "internal", "fileprivate", "private":
            kept.append(modifier.name.text)
        case "open":
            kept.append("public")
        case "mutating" where keepingMutating:
            kept.append("mutating")
        default:
            break
        }
    }
    return kept.isEmpty ? "" : kept.joined(separator: " ") + " "
}


extension SQLQueryBuilder {

    ///
    /// The name of the `@SQLQuery` peer method that describes this
    /// declaration.
    ///
    var declaredQueryPeerName: String {
        "\(function.name.text)DeclaredQuery"
    }

    ///
    /// Generates the `@SQLQuery` peer method describing this declaration.
    ///
    /// The method calls the `<name>Statement()` peer the executor already
    /// renders, so it needs nothing the executor does not.
    ///
    func makeDeclaredQueryPeer() -> String {
        let prefix = declaredQueryModifierPrefix(function.modifiers, keepingMutating: true)
        var lines: [String] = []
        lines.append("\(prefix)func \(declaredQueryPeerName)() -> XLDeclaredQuery {")
        lines.append("    let __xlStatement: any XLQueryStatement<\(rowType)> = \(function.name.text)Statement()")
        lines.append(indent(
            "return " + makeDeclaredQueryExpression(database: "self", statement: "__xlStatement"),
            by: 4
        ))
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the `XLDeclaredQuery(...)` expression for this declaration.
    ///
    /// Everything it passes is something the macro already knows without type
    /// information: the name, the cardinality, each parameter's name and
    /// spelled type, the row type, and the already-built value-free
    /// statement.
    ///
    /// - Parameters:
    ///   - database: The database instance expression.
    ///   - statement: The local holding the value-free statement.
    ///
    func makeDeclaredQueryExpression(database: String, statement: String) -> String {
        var lines: [String] = []
        lines.append("XLDeclaredQuery(")
        lines.append("    database: \(database),")
        lines.append("    name: \"\(normalizedIdentifier(function.name.text))\",")
        lines.append("    cardinality: \(declaredCardinality),")
        if parameters.isEmpty {
            lines.append("    parameters: [],")
        }
        else {
            lines.append("    parameters: [")
            for parameter in parameters {
                lines.append("        XLDeclaredQueryParameter(name: \"\(parameter.placeholderName)\", valueType: \(Self.metatypeSpelling(of: parameter.type)).self),")
            }
            lines.append("    ],")
        }
        lines.append("    rowType: \(Self.metatypeSpelling(of: rowType)).self,")
        lines.append("    statement: { \(statement) }")
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    ///
    /// The `XLQueryCardinality` case the declared return type selects.
    ///
    private var declaredCardinality: String {
        switch returnShape.cardinality {
        case .many:
            return ".many"
        case .one:
            return ".zeroOrOne"
        case .exactlyOne:
            return ".exactlyOne"
        }
    }

    ///
    /// A type spelling usable before `.self`. An implicitly unwrapped
    /// optional cannot be spelled there, so it becomes `Optional<Wrapped>`.
    ///
    private static func metatypeSpelling(of type: String) -> String {
        guard type.hasSuffix("!") else {
            return type
        }
        return "Optional<\(type.dropLast())>"
    }
}


extension SQLQueriesMacro {

    ///
    /// Generates `Context.declaredQueries`: one `XLDeclaredQuery` per
    /// specification in the container, in declaration order.
    ///
    /// Each body is evaluated the way the `Context` executor evaluates it --
    /// applied as a closure inside an instance member of `Context` -- so a
    /// body that compiles for the executor compiles here.
    ///
    static func makeContextDeclaredQueriesMember(
        builders: [SQLQueryBuilder],
        modifierPrefix: String
    ) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)var declaredQueries: [XLDeclaredQuery] {")
        if builders.isEmpty {
            lines.append("    []")
            lines.append("}")
            return lines.joined(separator: "\n")
        }
        for (offset, builder) in builders.enumerated() {
            let body = indent(builder.rewrittenBodyText, by: 4).dropFirst(4)
            lines.append("    let __xlStatement\(offset): any XLQueryStatement<\(builder.rowType)> = \(body)()")
        }
        lines.append("    return [")
        for (offset, builder) in builders.enumerated() {
            let expression = builder.makeDeclaredQueryExpression(
                database: "database",
                statement: "__xlStatement\(offset)"
            )
            lines.append(indent(expression + ",", by: 8))
        }
        lines.append("    ]")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the extended type's `declaredQueries`, read through a
    /// `Context` on the database itself.
    ///
    /// Adding a specification to the container adds it here, so a manifest
    /// projected from this member needs no hand-written list.
    ///
    static func makeDatabaseDeclaredQueriesMember(modifierPrefix: String) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)var declaredQueries: [XLDeclaredQuery] {")
        lines.append("    Context(database: self).declaredQueries")
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
