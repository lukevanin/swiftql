//
//  DeclaredQueryScanner.swift
//  SwiftQLDeclaredQueryDiscovery
//
//  Issue #659: finds every `@SQLQuery` and `@SQLQueries` declaration in a
//  target's source files, so a registry of the target's declared queries can
//  be generated rather than maintained by hand.
//
//  The scan is syntactic. It records where each declaration is and on which
//  type, and the macros already generate the members the registry calls.
//

import Foundation
import SwiftParser
import SwiftSyntax


/// One declaration a generated registry can reach.
public struct DeclaredQueryDeclaration: Equatable, Sendable {

    public enum Form: Equatable, Sendable {

        /// An `@SQLQueries` extension. The registry reads its
        /// `declaredQueries` property.
        case container

        /// An `@SQLQuery` function. The registry calls its
        /// `<functionName>DeclaredQuery()` method.
        case peer(functionName: String, isMutating: Bool)
    }

    /// The database type as the declaration spells it, qualified by the
    /// types it is nested in.
    public let databaseType: String

    public let form: Form

    /// The `#if` condition the declaration is compiled under, or `nil`.
    public let condition: String?

    public let file: String

    public let line: Int
}


/// A declaration the generated registry cannot reach, and why.
public struct SkippedDeclaredQueryDeclaration: Equatable, Sendable {

    public let file: String

    public let line: Int

    public let reason: String
}


/// The declarations found in one or more source files.
public struct DeclaredQueryScan: Equatable, Sendable {

    public var declarations: [DeclaredQueryDeclaration] = []

    public var skipped: [SkippedDeclaredQueryDeclaration] = []

    /// The modules imported by the files that hold a declaration, so the
    /// generated registry can name the same database types.
    public var imports: [String] = []

    public init() {}

    public mutating func merge(_ other: DeclaredQueryScan) {
        declarations += other.declarations
        skipped += other.skipped
        for module in other.imports where !imports.contains(module) {
            imports.append(module)
        }
    }
}


public enum DeclaredQueryScanner {

    ///
    /// Scans one source file.
    ///
    /// A file that does not mention either macro is not parsed.
    ///
    public static func scan(source: String, file: String) -> DeclaredQueryScan {
        guard source.contains("@SQLQuer") || source.contains(".SQLQuer") else {
            return DeclaredQueryScan()
        }
        let tree = Parser.parse(source: source)
        var walker = Walker(
            file: file,
            converter: SourceLocationConverter(fileName: file, tree: tree)
        )
        walker.visit(statements: tree.statements, scope: Scope())
        var scan = walker.scan
        if !scan.declarations.isEmpty || !scan.skipped.isEmpty {
            scan.imports = walker.imports
        }
        return scan
    }
}


private struct Scope {
    var typeName: String?
    var isPrivate = false
    var isGeneric = false
    var conditions: [String] = []
}


private struct Walker {

    let file: String

    let converter: SourceLocationConverter

    var scan = DeclaredQueryScan()

    var imports: [String] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
    }

    mutating func visit(statements: CodeBlockItemListSyntax, scope: Scope) {
        for item in statements {
            if case .decl(let decl) = item.item {
                visit(decl: decl, scope: scope)
            }
        }
    }

    mutating func visit(members: MemberBlockItemListSyntax, scope: Scope) {
        for member in members {
            visit(decl: member.decl, scope: scope)
        }
    }

    mutating func visit(decl: DeclSyntax, scope: Scope) {
        if let importDecl = decl.as(ImportDeclSyntax.self) {
            if scope.typeName == nil, importDecl.importKindSpecifier == nil {
                let module = importDecl.path.trimmedDescription
                if !imports.contains(module) {
                    imports.append(module)
                }
            }
            return
        }
        if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
            visit(ifConfig: ifConfig, scope: scope)
            return
        }
        if let extensionDecl = decl.as(ExtensionDeclSyntax.self) {
            let typeName = extensionDecl.extendedType.trimmedDescription
            var inner = scope
            inner.typeName = typeName
            inner.isPrivate = scope.isPrivate || Self.isPrivate(extensionDecl.modifiers)
            inner.isGeneric = extensionDecl.genericWhereClause != nil || typeName.contains("<")
            if Self.hasAttribute(extensionDecl.attributes, named: "SQLQueries") {
                record(.container, at: Syntax(extensionDecl), scope: inner)
            }
            visit(members: extensionDecl.memberBlock.members, scope: inner)
            return
        }
        if let nominal = Self.nominal(decl) {
            var inner = scope
            inner.typeName = scope.typeName.map { "\($0).\(nominal.name)" } ?? nominal.name
            inner.isPrivate = scope.isPrivate || Self.isPrivate(nominal.modifiers)
            inner.isGeneric = scope.isGeneric || nominal.isGeneric
            visit(members: nominal.members, scope: inner)
            return
        }
        if let function = decl.as(FunctionDeclSyntax.self),
           Self.hasAttribute(function.attributes, named: "SQLQuery") {
            let isTypeLevel = function.modifiers.contains { modifier in
                modifier.name.text == "static" || modifier.name.text == "class"
            }
            guard !isTypeLevel else {
                // The macro rejects a type-level specification with its own
                // diagnostic, so there is no member to call.
                return
            }
            var inner = scope
            inner.isPrivate = scope.isPrivate || Self.isPrivate(function.modifiers)
            let isMutating = function.modifiers.contains { $0.name.text == "mutating" }
            record(
                .peer(functionName: function.name.text, isMutating: isMutating),
                at: Syntax(function),
                scope: inner
            )
        }
    }

    mutating func visit(ifConfig: IfConfigDeclSyntax, scope: Scope) {
        var previous: [String] = []
        for clause in ifConfig.clauses {
            let condition = clause.condition?.trimmedDescription
            var parts = previous.map { "!(\($0))" }
            if let condition {
                parts.append("(\(condition))")
                previous.append(condition)
            }
            var inner = scope
            if !parts.isEmpty {
                inner.conditions.append(parts.joined(separator: " && "))
            }
            switch clause.elements {
            case .statements(let statements)?:
                visit(statements: statements, scope: inner)
            case .decls(let members)?:
                visit(members: members, scope: inner)
            default:
                break
            }
        }
    }

    mutating func record(
        _ form: DeclaredQueryDeclaration.Form,
        at node: Syntax,
        scope: Scope
    ) {
        let line = node.startLocation(converter: converter).line
        let subject: String
        switch form {
        case .container:
            subject = "The @SQLQueries extension"
        case .peer(let functionName, _):
            subject = "@SQLQuery '\(functionName)'"
        }
        guard let typeName = scope.typeName else {
            scan.skipped.append(SkippedDeclaredQueryDeclaration(
                file: file,
                line: line,
                reason: "\(subject) is not declared in a type, so it is not in the declared-query registry and is not validated."
            ))
            return
        }
        guard !scope.isPrivate else {
            scan.skipped.append(SkippedDeclaredQueryDeclaration(
                file: file,
                line: line,
                reason: "\(subject) on \(typeName) is private or fileprivate, so the generated declared-query registry cannot reach it and it is not validated. Give it internal or wider access to validate it."
            ))
            return
        }
        guard !scope.isGeneric else {
            scan.skipped.append(SkippedDeclaredQueryDeclaration(
                file: file,
                line: line,
                reason: "\(subject) on \(typeName) is declared on a generic or constrained type, which the generated declared-query registry cannot name, so it is not validated."
            ))
            return
        }
        let condition = scope.conditions.isEmpty
            ? nil
            : scope.conditions.map { "(\($0))" }.joined(separator: " && ")
        scan.declarations.append(DeclaredQueryDeclaration(
            databaseType: typeName,
            form: form,
            condition: condition,
            file: file,
            line: line
        ))
    }

    private struct Nominal {
        let name: String
        let modifiers: DeclModifierListSyntax
        let isGeneric: Bool
        let members: MemberBlockItemListSyntax
    }

    private static func nominal(_ decl: DeclSyntax) -> Nominal? {
        if let type = decl.as(StructDeclSyntax.self) {
            return Nominal(
                name: type.name.text,
                modifiers: type.modifiers,
                isGeneric: type.genericParameterClause != nil,
                members: type.memberBlock.members
            )
        }
        if let type = decl.as(ClassDeclSyntax.self) {
            return Nominal(
                name: type.name.text,
                modifiers: type.modifiers,
                isGeneric: type.genericParameterClause != nil,
                members: type.memberBlock.members
            )
        }
        if let type = decl.as(ActorDeclSyntax.self) {
            return Nominal(
                name: type.name.text,
                modifiers: type.modifiers,
                isGeneric: type.genericParameterClause != nil,
                members: type.memberBlock.members
            )
        }
        if let type = decl.as(EnumDeclSyntax.self) {
            return Nominal(
                name: type.name.text,
                modifiers: type.modifiers,
                isGeneric: type.genericParameterClause != nil,
                members: type.memberBlock.members
            )
        }
        return nil
    }

    private static func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            (modifier.name.text == "private" || modifier.name.text == "fileprivate")
                && modifier.detail == nil
        }
    }

    private static func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { element in
            guard case .attribute(let attribute) = element else {
                return false
            }
            let spelling = attribute.attributeName.trimmedDescription
            return spelling == name || spelling == "SwiftQL.\(name)"
        }
    }
}
