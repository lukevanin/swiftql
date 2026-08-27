//
//  MetaPropertyBindingWalk.swift
//  SwiftQL
//
//  Resolving the bindings of one `var`/`let` declaration into columns.
//
//  Split out of the parser (issue #564) because it is the subtlest logic in the
//  expansion and had no test that named it: everything about it was asserted
//  through whole macro expansions, where a wrong answer reads as a diff in
//  generated Swift rather than as the rule it broke.
//

import SwiftDiagnostics
import SwiftSyntax


///
/// Resolves `let a, b: Int` and its relatives into one column per binding.
///
/// Swift lets several bindings share one declaration, and a type annotation
/// applies backwards: in `let a, b: Int` both properties are `Int`. So the
/// bindings are visited in *reverse*, carrying the most recently seen
/// annotation to the ones before it, and only a binding with its own annotation
/// or its own initial value stops the carry.
///
/// Every invalid binding is reported and skipped rather than abandoning the
/// declaration, so one declaration with several problems produces a complete
/// set of errors instead of only the first.
///
internal enum MetaPropertyBindingWalk {

    ///
    /// - Parameters:
    ///   - bindings: The declaration's bindings, in source order.
    ///   - mutability: `var` or `let`, already validated by the caller.
    ///   - codecKeyExpression: The `@SQLCodec` key this declaration selects,
    ///     when it has exactly one binding for the annotation to belong to.
    ///   - diagnostics: Collects a diagnostic for every binding that cannot be
    ///     mapped.
    /// - Returns: One column per binding that resolved, in source order.
    static func resolve(
        bindings: PatternBindingListSyntax,
        mutability: MetaProperty.Mutability,
        codecKeyExpression: String?,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [MetaProperty] {
        func report(_ node: some SyntaxProtocol, id: String, _ message: String) {
            diagnostics.report(node, id: id, message)
        }

        // The type annotation carried backwards across the bindings of the declaration. A carried
        // annotation which was already reported as unsupported is marked invalid, so that the
        // bindings covered by it are skipped without emitting a misleading cascade of errors.
        enum CarriedType {
            case none
            case invalid
            case resolved(type: String, optional: Bool)
        }

        // Resolve the name and type of each binding. A type annotation applies to the contiguous
        // preceding bindings which have neither their own annotation nor an initial value
        // (e.g. in `let a, b: Int` both properties are of type Int), so the bindings are visited in
        // reverse order, carrying the most recently seen annotation backwards. Every invalid
        // binding is reported and skipped, so that a single declaration with several problems
        // produces a complete set of errors.
        var reversedProperties: [MetaProperty] = []
        var carriedType: CarriedType = .none

        // Carries the annotation of a binding which was already reported as invalid, without
        // reporting the annotation again, so that the bindings covered by it are still resolved.
        func carryAnnotation(of binding: PatternBindingSyntax) {
            guard let annotation = binding.typeAnnotation else {
                return
            }
            if let resolved = resolveColumnType(annotation.type) {
                carriedType = .resolved(type: resolved.type, optional: resolved.optional)
            }
            else {
                carriedType = .invalid
            }
        }

        for binding in bindings.reversed() {

            if
                let accessorBlock = binding.accessorBlock,
                StoredPropertyClassifier.isComputed(accessorBlock)
            {
                StoredPropertyClassifier.reportComputed(
                    binding,
                    as: .column,
                    diagnostics: &diagnostics
                )
                carryAnnotation(of: binding)
                continue
            }

            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                StoredPropertyClassifier.reportUnsupportedPattern(
                    binding.pattern,
                    as: .column,
                    diagnostics: &diagnostics
                )
                carryAnnotation(of: binding)
                continue
            }
            let name = pattern.identifier.text

            if let annotation = binding.typeAnnotation {
                if let resolved = resolveColumnType(annotation.type) {
                    carriedType = .resolved(type: resolved.type, optional: resolved.optional)
                }
                else {
                    report(
                        annotation.type, id: "unsupported-column-type",
                        "Type '\(annotation.type.trimmedDescription)' cannot be used as a column type. Use a named type that conforms to 'XLLiteral' for a scalar column, or a nested '@SQLTable'/'@SQLResult' type for a composite column selection."
                    )
                    carriedType = .invalid
                    continue
                }
            }

            let resolvedType: (type: String, optional: Bool)
            switch (binding.typeAnnotation, binding.initializer, carriedType) {
            case (.some, _, .resolved(let type, let optional)):
                resolvedType = (type, optional)
            case (nil, .some, _):
                report(
                    binding, id: "missing-type-annotation",
                    "Property '\(name)' needs an explicit type annotation to be used as a column. The type of the initial value cannot be inferred by the macro."
                )
                // A binding with its own initial value takes its type from that
                // value, so it ends the contiguous run a later annotation
                // carries back over. Leaving the carry in place let a binding
                // before it inherit an annotation Swift would not have given
                // it: in `let a, b = 1, c: Int`, `a` was silently typed `Int`.
                carriedType = .none
                continue
            case (nil, nil, .resolved(let type, let optional)):
                resolvedType = (type, optional)
            case (nil, nil, .invalid):
                // The carried annotation was already reported as unsupported.
                continue
            case (nil, nil, .none):
                report(
                    binding, id: "missing-type-annotation",
                    "Property '\(name)' needs an explicit type annotation to be used as a column."
                )
                continue
            case (.some, _, .none), (.some, _, .invalid):
                // Unreachable: a resolved annotation always sets the carried type, and an
                // unsupported annotation skips the binding above.
                continue
            }

            if mutability == .immutable, binding.initializer != nil {
                report(
                    binding, id: "immutable-initial-value",
                    "A 'let' property with an initial value cannot be assigned by the generated initializer. Use 'var', or remove the initial value."
                )
                continue
            }

            // A property name may be escaped with backticks (e.g. to use a reserved word as a
            // name). The backticks are kept in the Swift name and stripped from the SQL name.
            let columnName: String
            if name.hasPrefix("`") && name.hasSuffix("`") && name.count > 2 {
                columnName = String(name.dropFirst().dropLast())
            }
            else {
                columnName = name
            }

            if MetaModel.reservedPropertyNames.contains(columnName) {
                report(
                    pattern, id: "reserved-property-name",
                    "Property name '\(columnName)' conflicts with a member generated by the macro. Rename the property."
                )
                continue
            }

            reversedProperties.append(
                MetaProperty(
                    mutability: mutability,
                    name: name,
                    alias: columnName,
                    optional: resolvedType.optional,
                    type: resolvedType.type,
                    codecKeyExpression: codecKeyExpression
                )
            )
        }

        return reversedProperties.reversed()
    }

    ///
    /// Resolves a type annotation to a column type and optionality. Returns `nil` if the type cannot be
    /// used as a column type.
    ///
    static func resolveColumnType(_ type: TypeSyntax) -> (type: String, optional: Bool)? {
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            guard let wrapped = resolveColumnType(optionalType.wrappedType), !wrapped.optional else {
                return nil
            }
            return (wrapped.type, true)
        }
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            // Resolve the `Optional<T>` spelling to the same column type as `T?`.
            if identifierType.name.text == "Optional" {
                return resolveOptionalSugar(identifierType.genericArgumentClause)
            }
            // Keep generic arguments (e.g. `Array<Int>`) as part of the column type.
            return (identifierType.trimmedDescription, false)
        }
        if let memberType = type.as(MemberTypeSyntax.self) {
            // Resolve the module qualified `Swift.Optional<T>` spelling to the same column type
            // as `T?`.
            if
                memberType.name.text == "Optional",
                memberType.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
            {
                return resolveOptionalSugar(memberType.genericArgumentClause)
            }
            return (memberType.trimmedDescription, false)
        }
        if type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) {
            return (type.trimmedDescription, false)
        }
        return nil
    }

    ///
    /// Resolves the generic argument of an `Optional<T>` or `Swift.Optional<T>` spelling to the same
    /// column type as `T?`. Returns `nil` if the wrapped type cannot be used as a column type.
    ///
    static func resolveOptionalSugar(
        _ genericArgumentClause: GenericArgumentClauseSyntax?
    ) -> (type: String, optional: Bool)? {
        guard
            let arguments = genericArgumentClause?.arguments,
            arguments.count == 1,
            let argument = arguments.first?.argument,
            let wrapped = resolveColumnType(argument),
            !wrapped.optional
        else {
            return nil
        }
        return (wrapped.type, true)
    }


    // Build result-only meta data, used to select explicit columns without an underlying table.
}
