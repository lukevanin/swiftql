//
//  SQLQueryDeclaredQueryEmission.swift
//  SwiftQL
//
//  Issue #659: emission of the data a declared query carries about itself.
//  `@SQLQuery` adds one `<name>DeclaredQuery` peer per declaration, and
//  `@SQLQueries` adds one `declaredQueries` member listing every
//  specification in its container. The generic runtime in
//  `SQLDeclaredQuery.swift` assembles that data into a static descriptor.
//
//  Kept apart from the executor generation so the executor's expansion does
//  not change.
//

import Foundation
import SwiftSyntax


extension SQLQueryBuilder {

    ///
    /// The name of the `@SQLQuery` peer that describes this declaration.
    ///
    var declaredQueryPeerName: String {
        "\(function.name.text)DeclaredQuery"
    }

    ///
    /// Generates the `@SQLQuery` peer describing this declaration.
    ///
    func makeDeclaredQueryPeer() -> String {
        var lines: [String] = []
        let prefix = macroModifierPrefix(function.modifiers)
        lines.append("\(prefix)static var \(declaredQueryPeerName): XLDeclaredQuery {")
        lines.append(indent(makeDeclaredQueryExpression(), by: 4))
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the `XLDeclaredQuery(...)` expression for this declaration.
    ///
    /// Everything it passes is something the macro already knows without type
    /// information: the name, the cardinality, each parameter's name and
    /// spelled type, the row type, and the rewritten value-free statement
    /// builder -- the same body the executor renders.
    ///
    func makeDeclaredQueryExpression() -> String {
        var lines: [String] = []
        lines.append("XLDeclaredQuery(")
        lines.append("    databaseType: Self.self,")
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
        lines.append("    statement: \(indent(rewrittenBodyText, by: 4).dropFirst(4))")
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
    /// Generates the `declaredQueries` member: one `XLDeclaredQuery` per
    /// specification in the container, in declaration order.
    ///
    /// Adding a specification to the container adds it here, so a manifest
    /// projected from this member needs no hand-written list.
    ///
    static func makeDeclaredQueriesMember(
        builders: [SQLQueryBuilder],
        modifierPrefix: String
    ) -> String {
        var lines: [String] = []
        lines.append("\(modifierPrefix)static var declaredQueries: [XLDeclaredQuery] {")
        if builders.isEmpty {
            lines.append("    []")
        }
        else {
            lines.append("    [")
            for builder in builders {
                let expression = builder.makeDeclaredQueryExpression() + ","
                lines.append(indent(expression, by: 8))
            }
            lines.append("    ]")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
