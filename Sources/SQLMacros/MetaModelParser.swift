//
//  MetaModelParser.swift
//  SwiftQL
//
//  The parse half of the `@SQLTable`/`@SQLResult` expansion: SwiftSyntax in,
//  a `MetaModel` out.
//
//  Split out of MetaBuilder.swift (issue #564). Nothing here emits a character
//  of Swift, and nothing downstream of it looks at syntax again.
//

import Foundation
import SwiftSyntax


internal enum MetaModelParser {

    ///
    /// Parses an annotated declaration into the model the emitters work from.
    ///
    /// - Parameter node: Reference to the macro. E.g. `@SQLTable(name: "foo")`
    /// - Parameter declaration: The struct the macro is attached to.
    ///
    /// Every member is classified before anything is thrown, so one invalid
    /// declaration reports its complete set of problems rather than only the
    /// first.
    ///
    static func parse(
        node: AttributeSyntax,
        declaration: StructDeclSyntax
    ) throws -> MetaModel {
        var diagnostics = MacroDiagnosticCollector()

        // Use the name parameter from the macro if it is defined, otherwise
        // use the name of the struct for the table name.
        let structName = declaration.name.text
        let tableName = MacroNameArgument.resolve(
            of: node,
            defaultingTo: structName,
            diagnostics: &diagnostics
        )

        // Collect the properties from the struct definition.
        let properties = collectProperties(
            declaration: declaration,
            diagnostics: &diagnostics
        )

        try diagnostics.throwIfNotEmpty()

        return MetaModel(
            structName: structName,
            tableName: tableName,
            genericParameterNames: declaration.genericParameterClause?
                .parameters.map { $0.name.text } ?? [],
            properties: properties
        )
    }

    ///
    /// Collects the stored properties of the struct, mapping each one to a column.
    ///
    /// Every member of the struct is either mapped faithfully to a column, ignored because it can never
    /// be a column (methods, initializers, and nested types), or reported as an error diagnostic located
    /// at the offending declaration (e.g. static, lazy, or computed properties). No property is ever
    /// silently dropped.
    ///
    private static func collectProperties(
        declaration: StructDeclSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [MetaProperty] {
        var properties: [MetaProperty] = []
        for member in declaration.memberBlock.members {
            // Members which are not variable declarations (methods, initializers, nested types,
            // subscripts) are never columns.
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            properties.append(contentsOf: collectProperties(variable: variable, diagnostics: &diagnostics))
        }
        return properties
    }

    ///
    /// Maps a single variable declaration to zero or more columns, or appends an error diagnostic if the
    /// declaration cannot be mapped faithfully.
    ///
    private static func collectProperties(
        variable: VariableDeclSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [MetaProperty] {

        func report(_ node: some SyntaxProtocol, id: String, _ message: String) {
            diagnostics.report(node, id: id, message)
        }

        guard StoredPropertyClassifier.accepts(variable, as: .column, diagnostics: &diagnostics) else {
            return []
        }

        // Issue #66: a stored property may carry at most one `@SQLCodec(_:)` attribute,
        // selecting a named contextual value codec for that property alone. The attribute
        // applies to the variable declaration as a whole, so a declaration sharing one
        // annotation across several bindings (e.g. `@SQLCodec(x) var a, b: Int`) cannot
        // resolve which binding it names and is reported instead of guessed.
        let codecSelector = collectCodecSelector(
            attributes: variable.attributes,
            diagnostics: &diagnostics
        )
        if let codecSelector, variable.bindings.count > 1 {
            report(
                codecSelector.node, id: "ambiguous-codec-declaration-target",
                "'@SQLCodec' cannot be shared by several bindings in one declaration. Declare the annotated property in its own 'var'/'let' statement."
            )
        }

        // The specifier is known to be `var` or `let`: anything else was
        // rejected by the classifier above.
        let mutability: MetaProperty.Mutability =
            variable.bindingSpecifier.text == "var" ? .mutable : .immutable

        return MetaPropertyBindingWalk.resolve(
            bindings: variable.bindings,
            mutability: mutability,
            codecKeyExpression: variable.bindings.count == 1
                ? codecSelector?.expression
                : nil,
            diagnostics: &diagnostics
        )
    }

    /// Reads and validates every `@SQLCodec(_:)` attribute attached to one variable declaration
    /// (issue #66). `@SQLCodec` itself expands to nothing (see `SQLCodecMacro`); its role is
    /// metadata, resolved entirely here while `SQLTableMacro`/`SQLResultMacro` walk the
    /// property list. The Swift compiler already enforces the macro's own declared signature
    /// (`SQLCodec(_ key: XLValueCodecKey)`) as an ordinary call, so a wrong argument type or
    /// missing argument is diagnosed by the compiler itself before this ever runs; only shapes
    /// the compiler cannot see this early -- more than one selector on the same property, or a
    /// labeled/argument-count mismatch inside an already-valid call -- are reported here.
    private static func collectCodecSelector(
        attributes: AttributeListSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> (expression: String, node: AttributeSyntax)? {
        var selectors: [(expression: String, node: AttributeSyntax)] = []
        for element in attributes {
            guard case let .attribute(attribute) = element else {
                continue
            }
            guard attribute.attributeName.trimmedDescription == "SQLCodec" else {
                continue
            }
            guard
                case let .argumentList(arguments) = attribute.arguments,
                arguments.count == 1,
                let argument = arguments.first,
                argument.label == nil
            else {
                diagnostics.report(
                    attribute,
                    id: "invalid-codec-selector",
                    "'@SQLCodec' requires exactly one unlabeled argument naming a durable 'XLValueCodecKey'."
                )
                continue
            }
            selectors.append((argument.expression.trimmedDescription, attribute))
        }
        guard let first = selectors.first else {
            return nil
        }
        for duplicate in selectors.dropFirst() {
            diagnostics.report(
                duplicate.node,
                id: "conflicting-codec-selector",
                "Property has more than one '@SQLCodec' attribute. A property may select at most one explicit codec."
            )
        }
        return first
    }
}
