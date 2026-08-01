import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros


///
/// Implements the `#row(...)` freestanding expression macro.
///
/// The public overloads declared in `Sources/SwiftQL/SQLRowMacro.swift` fix the arity (one to
/// six unlabeled column expressions) and the resulting ad hoc row type (`SQLScalarResult` for one
/// column, `SQLRow2`...`SQLRow6` for two to six), so the only work left here is rewriting
/// `#row(a, b, ...)` into the equivalent `Type.columns(...)` call the caller would otherwise have
/// to spell out by hand:
///
///     #row(person.id, person.name)
///     // -> SQLRow2.columns(_0: person.id, _1: person.name)
///
/// Because the public overloads already fix the arity and reject labeled arguments before this
/// macro ever runs, the diagnostics below are unreachable through the declared `#row` overloads
/// and only matter for direct `assertMacroExpansion` coverage or a future overload that relaxes
/// those constraints.
///
public struct SQLRowMacro: ExpressionMacro {

    static let fieldNames = ["_0", "_1", "_2", "_3", "_4", "_5"]

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = Array(node.argumentList)

        guard !arguments.isEmpty else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    id: "row.emptyArgumentList",
                    message: "'#row' requires at least one column expression, such as '#row(person.id)'."
                )
            )
            return "()"
        }

        guard arguments.count <= fieldNames.count else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    id: "row.tooManyArguments",
                    message: "'#row' supports at most \(fieldNames.count) columns; declare a named result with '@SQLResult' for wider projections."
                )
            )
            return "()"
        }

        for argument in arguments where argument.label != nil {
            context.diagnose(
                Diagnostic(
                    node: argument,
                    id: "row.labeledArgument",
                    message: "'#row' does not accept labeled arguments; pass column expressions positionally, such as '#row(person.id, person.name)'."
                )
            )
        }

        if arguments.count == 1 {
            let column = arguments[0].expression
            return "SQLScalarResult.columns(scalarValue: \(column))"
        }

        let typeName = "SQLRow\(arguments.count)"
        let columnArguments = arguments.enumerated().map { index, argument in
            "\(fieldNames[index]): \(argument.expression)"
        }.joined(separator: ", ")
        return "\(raw: typeName).columns(\(raw: columnArguments))"
    }
}
