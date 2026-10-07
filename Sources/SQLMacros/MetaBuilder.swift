//
//  MetaBuilder.swift
//
//
//  Created by Luke Van In on 2024/09/20.
//

import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros


///
/// Generates code for `SQLTable` and `SQLResult` macros.
///
/// A thin facade over the two halves this used to be one file of (issue #564):
/// ``MetaModelParser`` turns the annotated declaration into a ``MetaModel``,
/// and the emitters -- `MetaBuilder+Result`, `MetaBuilder+Table`,
/// `MetaBuilder+StaticLayout` -- turn that model into Swift source. The macro
/// entry points still see one type with the same members it always had.
///
/// The `StructDeclSyntax` is kept here, not on the model: `SQLMacro.swift`
/// reads the declaration's own modifiers and generic clause to decide whether
/// to derive `Sendable`, which is a question about the *syntax*, not about the
/// table it describes.
///
internal struct MetaBuilder {

    /// SwiftSyntax declaration of the struct.
    let declaration: StructDeclSyntax

    /// The syntax-free description the emitters work from.
    let model: MetaModel

    ///
    /// Convenience initializer used to initialise the builder with a `DeclGroupSyntax`.
    /// - throws: `SQLMacroError.unsupportedType` if the declaration is not a `StructDeclSyntax`
    ///
    init(node: AttributeSyntax, declaration: DeclGroupSyntax) throws {
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            throw SQLMacroError.unsupportedType
        }
        try self.init(node: node, declaration: declaration)
    }

    init(node: AttributeSyntax, declaration: StructDeclSyntax) throws {
        self.declaration = declaration
        self.model = try MetaModelParser.parse(node: node, declaration: declaration)
    }

    // The model's members, forwarded so the emitters and the macro entry
    // points read exactly as they did before the split.

    var structName: String { model.structName }

    var tableName: String { model.tableName }

    var dialectType: String { model.dialectType }

    ///
    /// The member every generated metadata type names its dialect with (issue
    /// #789).
    ///
    /// Swift infers the protocols' `XLModelDialect` associated type from it.
    /// The associated type is in SwiftQL's prefix space, so the member type
    /// Swift gives the model does not capture a type of the user's own, such
    /// as one named `Dialect`.
    ///
    func makeDialectWitness(isStatic: Bool) -> String {
        let modifier = isStatic ? "public static var" : "public var"
        return "\(modifier) _dialect: \(dialectType).Type { \(dialectType).self }"
    }

    ///
    /// The type of a value slot of `valueType`: an assignment in
    /// `Setting { row in ... }`, an argument of `columns(...)` or of the
    /// generated initializers that take expressions (issue #825).
    ///
    /// The slot takes the model's dialect's expressions, and Swift values,
    /// which are expressions of every dialect. Each dialect's generated
    /// surface declares `XLAnyExpression<T>` on the dialect type, a generic
    /// typealias for `any` its expression protocol, so the macro reaches the
    /// protocol from the dialect type it already writes, and the error for
    /// another dialect's expression names both dialects. The name is a member
    /// of the dialect type and in SwiftQL's prefix space, so it captures no
    /// type of the user's own (issue #700).
    ///
    /// The typealias is generic and names the existential itself, rather
    /// than naming the protocol and taking its primary associated type at the
    /// use site, so it relies only on generic typealiases and parameterized
    /// existentials (Swift 5.7), not on how a compiler specializes a
    /// typealias of a protocol.
    ///
    func dialectExpressionType(_ valueType: String) -> String {
        "\(dialectType).XLAnyExpression<\(valueType)>"
    }

    var properties: [MetaProperty] { model.properties }

    var optionalProperties: [MetaProperty] { model.optionalProperties }

    var anonymousProperties: [MetaProperty] { model.anonymousProperties }

    var anonymousOptionalProperties: [MetaProperty] { model.anonymousOptionalProperties }

    var mutableProperties: [MetaProperty] { model.mutableProperties }

    var generatedIdentifierReservations: Set<String> {
        model.generatedIdentifierReservations
    }
}
