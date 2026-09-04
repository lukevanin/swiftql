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

    var properties: [MetaProperty] { model.properties }

    var optionalProperties: [MetaProperty] { model.optionalProperties }

    var anonymousProperties: [MetaProperty] { model.anonymousProperties }

    var anonymousOptionalProperties: [MetaProperty] { model.anonymousOptionalProperties }

    var mutableProperties: [MetaProperty] { model.mutableProperties }

    var generatedIdentifierReservations: Set<String> {
        model.generatedIdentifierReservations
    }
}
