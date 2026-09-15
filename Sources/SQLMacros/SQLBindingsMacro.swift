//
//  SQLBindingsMacro.swift
//  SwiftQL
//
//  Issue #663: a typed invocation packet for the named bindings of a
//  statement value, so a caller never looks up a parameter slot by name.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros


///
/// One stored property of an `@SQLBindings` struct, which becomes one named
/// binding.
///
internal struct SQLBindingsProperty {

    /// The property name exactly as written, including any escaping backticks.
    /// Used where generated code declares or reads the property.
    var swiftName: String

    /// The property name without escaping backticks. This is the SQL
    /// placeholder name.
    var placeholderName: String

    /// The type annotation exactly as written.
    var type: String
}


///
/// Collects the stored properties of a struct annotated with `@SQLBindings`
/// and generates one typed binding reference per property plus the packet
/// builders.
///
/// The property is the single source of the binding's name and type: the
/// statement refers to the generated static reference, and the packet binds
/// the property value under the same name. A misspelled reference is a missing
/// static member, and a missing value is a missing memberwise-initializer
/// argument, so both fail to compile.
///
internal struct SQLBindingsBuilder {

    let accessPrefix: String

    let properties: [SQLBindingsProperty]

    init(node: AttributeSyntax, declaration: some DeclGroupSyntax) throws {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    id: "sqlbindings-struct-only",
                    message: "'@SQLBindings' can only be applied to a struct."
                )
            ])
        }

        var diagnostics = MacroDiagnosticCollector()
        var properties: [SQLBindingsProperty] = []
        for member in structDeclaration.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                // A declared initializer can supply a value itself, so a
                // call that leaves the value out would still compile.
                diagnostics.report(
                    initializer.initKeyword,
                    id: "sqlbindings-custom-initializer",
                    "'@SQLBindings' cannot be applied to a struct that declares an initializer. The memberwise initializer is what makes a missing value a compile error. Remove the initializer, and build the values in a function that calls the memberwise initializer."
                )
                continue
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            properties.append(
                contentsOf: Self.collectProperties(
                    variable: variable,
                    diagnostics: &diagnostics
                )
            )
        }
        try diagnostics.throwIfNotEmpty()

        self.accessPrefix = Self.accessPrefix(of: structDeclaration.modifiers)
        self.properties = properties
    }

    private static func collectProperties(
        variable: VariableDeclSyntax,
        diagnostics: inout MacroDiagnosticCollector
    ) -> [SQLBindingsProperty] {
        guard
            StoredPropertyClassifier.accepts(
                variable,
                as: .namedBinding,
                diagnostics: &diagnostics
            )
        else {
            return []
        }

        var properties: [SQLBindingsProperty] = []
        for binding in variable.bindings {
            if
                let accessorBlock = binding.accessorBlock,
                StoredPropertyClassifier.isComputed(accessorBlock)
            {
                StoredPropertyClassifier.reportComputed(
                    binding,
                    as: .namedBinding,
                    diagnostics: &diagnostics
                )
                continue
            }

            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                StoredPropertyClassifier.reportUnsupportedPattern(
                    binding.pattern,
                    as: .namedBinding,
                    diagnostics: &diagnostics
                )
                continue
            }
            let name = pattern.identifier.text

            guard let annotation = binding.typeAnnotation else {
                diagnostics.report(
                    binding,
                    id: "sqlbindings-missing-type-annotation",
                    "Property '\(normalizedIdentifier(name))' needs an explicit type annotation to be used as a named binding. The type declares the value type of the binding."
                )
                continue
            }

            if let initialValue = binding.initializer {
                // An initial value gives the memberwise-initializer parameter
                // a default, so a call that forgets the value would compile
                // and silently bind the initial value.
                diagnostics.report(
                    initialValue,
                    id: "sqlbindings-initial-value",
                    "Property '\(normalizedIdentifier(name))' cannot have an initial value when it is used as a named binding. The initial value makes the memberwise-initializer argument optional, so a call that leaves the value out would compile and bind the initial value. Remove the initial value."
                )
                continue
            }

            properties.append(
                SQLBindingsProperty(
                    swiftName: name,
                    placeholderName: normalizedIdentifier(name),
                    type: annotation.type.trimmedDescription
                )
            )
        }
        return properties
    }

    ///
    /// Generated members are visible wherever the struct is. A `private` or
    /// `fileprivate` struct already limits its members, so those members take
    /// the default access level rather than becoming private to the struct.
    ///
    /// Only the struct's own modifiers are read. swift-syntax 509, the
    /// package's floor, gives a member macro no view of an enclosing
    /// `public extension`, so a struct that is public only through its
    /// extension gets internal members. The documentation tells callers to
    /// write the modifier on the struct.
    ///
    private static func accessPrefix(of modifiers: DeclModifierListSyntax) -> String {
        for modifier in modifiers {
            switch modifier.name.text {
            case "public", "package":
                return "\(modifier.name.text) "
            default:
                continue
            }
        }
        return ""
    }

    ///
    /// Generates the typed reference a statement uses in place of a
    /// hand-written `XLNamedBindingReference`.
    ///
    func makeReferenceDecl(for property: SQLBindingsProperty) -> String {
        let reference = "XLNamedBindingReference<\(property.type)>"
        return """
        \(accessPrefix)static var \(property.swiftName): \(reference) {
            \(reference)(name: \(quoted(property.placeholderName)))
        }
        """
    }

    ///
    /// Generates the packet builder for a parameter layout. Every property is
    /// encoded under its own name, and the completed packet is validated, so a
    /// statement that uses a name the struct does not declare, or does not use
    /// a name the struct declares, throws instead of executing.
    ///
    func makeLayoutPacketFunction() -> String {
        var lines: [String] = []
        lines.append("\(accessPrefix)func bindings(in __xlLayout: XLParameterLayout) throws -> XLInvocationBindings<XLSQLiteValue> {")
        if properties.isEmpty {
            lines.append("    try XLInvocationBindings<XLSQLiteValue>(layout: __xlLayout, bindings: []).validatingComplete()")
        }
        else {
            lines.append("    try XLInvocationBindings<XLSQLiteValue>(")
            lines.append("        layout: __xlLayout,")
            lines.append("        bindings: [")
            for property in properties {
                lines.append("            try _xlQueryParameterBinding(self.\(property.swiftName), named: \(quoted(property.placeholderName)), in: __xlLayout),")
            }
            lines.append("        ]")
            lines.append("    ).validatingComplete()")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    ///
    /// Generates the packet builder for a prepared request.
    ///
    func makeRequestPacketFunction() -> String {
        """
        \(accessPrefix)func bindings<__XLRequest: XLRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
            try self.bindings(in: __xlRequest.parameterLayout)
        }
        """
    }

    ///
    /// Generates the packet builder for a prepared write request. A write
    /// without `RETURNING` prepares an `XLWriteRequest`, which is not an
    /// `XLRequest`. No SwiftQL request type conforms to both protocols, so the
    /// two overloads never make a call ambiguous.
    ///
    func makeWriteRequestPacketFunction() -> String {
        """
        \(accessPrefix)func bindings<__XLRequest: XLWriteRequest>(for __xlRequest: __XLRequest) throws -> XLInvocationBindings<XLSQLiteValue> {
            try self.bindings(in: __xlRequest.parameterLayout)
        }
        """
    }
}


///
/// Declares a struct as the typed named bindings of a statement value.
///
/// Each stored property becomes one named binding. The macro generates a static
/// `XLNamedBindingReference` with the property's name and type for the
/// statement to use, and `bindings(in:)` and `bindings(for:)`, which build the
/// immutable `XLInvocationBindings` packet from the property values.
///
public struct SQLBindingsMacro {
}

extension SQLBindingsMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let builder = try SQLBindingsBuilder(node: node, declaration: declaration)
        var declarations: [DeclSyntax] = []
        for property in builder.properties {
            declarations.append(try makeDecl(builder.makeReferenceDecl(for: property)))
        }
        declarations.append(try makeDecl(builder.makeLayoutPacketFunction()))
        declarations.append(try makeDecl(builder.makeRequestPacketFunction()))
        declarations.append(try makeDecl(builder.makeWriteRequestPacketFunction()))
        return declarations
    }
}
