//
//  DeclaredQueryScanner.swift
//  SwiftQLDeclaredQueryDiscovery
//
//  Issue #659: finds every `@SQLQuery` and `@SQLQueries` declaration in a
//  target's source files, so a registry of the target's declared queries can
//  be generated rather than maintained by hand.
//
//  The scan is syntactic and reads every file of the target, in two passes.
//  The first pass records every type the target declares, whether it is
//  generic, and the `#if` conditions it is declared under. The second pass
//  resolves each declaration's database type against those records, so a
//  declaration on a generic type, or under a condition, is handled even when
//  the type is declared in another file.
//

import Foundation
import SwiftParser
import SwiftSyntax


/// One `import` a generated registry repeats, so it can name the same types.
public struct DeclaredQueryImport: Equatable, Sendable {

    /// The import as written, attributes included (`@testable import Foo`).
    public let declaration: String

    /// The `#if` condition the import is compiled under, or `nil`.
    public let condition: String?

    /// The imported module, the first component of the import path.
    public let module: String

    public init(declaration: String, condition: String?, module: String) {
        self.declaration = declaration
        self.condition = condition
        self.module = module
    }
}


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

    /// The `#if` condition the declaration itself is compiled under, or
    /// `nil`.
    public let condition: String?

    /// The `#if` condition the database type -- and every type it is nested
    /// in -- is declared under in this target, or `nil` when the type is
    /// unconditional or declared outside the target.
    public let typeCondition: String?

    public let file: String

    public let line: Int
}


/// A declaration the generated registry does not call, and why.
public struct SkippedDeclaredQueryDeclaration: Equatable, Sendable {

    public let file: String

    public let line: Int

    public let reason: String
}


/// The declarations found in a target's source files.
public struct DeclaredQueryScan: Equatable, Sendable {

    public var declarations: [DeclaredQueryDeclaration] = []

    /// Declarations the registry cannot reach. Each one is a build warning.
    public var skipped: [SkippedDeclaredQueryDeclaration] = []

    /// Declarations marked with ``DeclaredQueryScanner/exclusionMarker``.
    public var excluded: [SkippedDeclaredQueryDeclaration] = []

    /// The imports of the files that hold a declaration.
    public var imports: [DeclaredQueryImport] = []

    public init() {}
}


public enum DeclaredQueryScanner {

    ///
    /// A comment that leaves one declaration out of the registry without a
    /// warning. Write it directly above the declaration, before its first
    /// attribute. The scanner reads only the comments in front of the
    /// declaration's first token, so a comment between two attributes, or
    /// between an attribute and `func`, is not seen:
    ///
    ///     // swiftql-registry: ignore
    ///     @SQLQuery
    ///     func debugOnly() -> [Row] { ... }
    ///
    public static let exclusionMarker = "swiftql-registry: ignore"

    /// One source file of the target.
    public struct SourceFile: Sendable {

        public let path: String

        public let source: String

        public init(path: String, source: String) {
            self.path = path
            self.source = source
        }
    }

    /// Scans one source file on its own.
    public static func scan(source: String, file: String) -> DeclaredQueryScan {
        scan([SourceFile(path: file, source: source)])
    }

    ///
    /// Scans every source file of a target.
    ///
    /// Pass every file, not only the ones that declare queries: a database
    /// type declared in one file can be extended with a declaration in
    /// another, and whether it is generic or conditional is only known from
    /// its own declaration.
    ///
    public static func scan(_ files: [SourceFile]) -> DeclaredQueryScan {
        var walkers: [Walker] = []
        for file in files {
            let tree = Parser.parse(source: file.source)
            var walker = Walker(
                file: file.path,
                converter: SourceLocationConverter(fileName: file.path, tree: tree)
            )
            walker.visit(statements: tree.statements, scope: Scope())
            walkers.append(walker)
        }

        var types: [String: [TypeRecord]] = [:]
        for walker in walkers {
            for record in walker.types {
                types[record.name, default: []].append(record)
            }
        }

        var scan = DeclaredQueryScan()
        for walker in walkers {
            var holdsDeclaration = false
            for raw in walker.declarations {
                guard !raw.isExcluded else {
                    scan.excluded.append(SkippedDeclaredQueryDeclaration(
                        file: raw.file,
                        line: raw.line,
                        reason: "\(raw.subject) is marked '\(exclusionMarker)', so it is not in the declared-query registry and is not validated."
                    ))
                    continue
                }
                holdsDeclaration = true
                guard !raw.hasConditionalAttribute else {
                    scan.skipped.append(skip(
                        raw,
                        because: "has its attribute inside an #if in the attribute list, which the scanner does not evaluate",
                        fix: "Put the #if around the whole declaration to validate it"
                    ))
                    continue
                }
                guard let typeName = raw.typeName else {
                    scan.skipped.append(skip(
                        raw,
                        because: "is not declared in a type",
                        fix: nil
                    ))
                    continue
                }
                guard !raw.isPrivate else {
                    scan.skipped.append(skip(
                        raw,
                        because: "on \(typeName) is private or fileprivate, which the generated registry cannot reach",
                        fix: "Give it internal or wider access to validate it"
                    ))
                    continue
                }
                let resolution = resolve(typeName, in: types)
                guard !raw.isGeneric, !resolution.isGeneric else {
                    scan.skipped.append(skip(
                        raw,
                        because: "on \(typeName) is declared on a generic or constrained type, in an extension of one, or in a type nested in a type this target does not declare, which the generated registry cannot name",
                        fix: nil
                    ))
                    continue
                }
                scan.declarations.append(DeclaredQueryDeclaration(
                    databaseType: typeName,
                    form: raw.form,
                    condition: conditionExpression(raw.conditions),
                    typeCondition: resolution.condition,
                    file: raw.file,
                    line: raw.line
                ))
            }
            if holdsDeclaration {
                for declaredImport in walker.imports where !scan.imports.contains(declaredImport) {
                    scan.imports.append(declaredImport)
                }
            }
        }
        return scan
    }

    /// A skip warning in three parts: why the registry cannot call the
    /// declaration, what that means, and how to change it, if it can be
    /// changed.
    private static func skip(
        _ raw: RawDeclaration,
        because cause: String,
        fix: String?
    ) -> SkippedDeclaredQueryDeclaration {
        var reason = "\(raw.subject) \(cause). It is not in the declared-query registry and is not validated."
        if let fix {
            reason += " \(fix)."
        }
        reason += " To leave it out without this warning, mark it '// \(exclusionMarker)'."
        return SkippedDeclaredQueryDeclaration(file: raw.file, line: raw.line, reason: reason)
    }

    /// The generic flag and `#if` condition of a qualified type name,
    /// gathered from the type and from every type it is nested in.
    private static func resolve(
        _ typeName: String,
        in types: [String: [TypeRecord]]
    ) -> (isGeneric: Bool, condition: String?) {
        let components = topLevelComponents(of: typeName)
        var isGeneric = false
        var clauses: [String] = []
        var passedUndeclaredType = false
        for count in 1 ... max(components.count, 1) {
            let prefix = components.prefix(count).joined(separator: ".")
            guard let records = types[prefix] else {
                passedUndeclaredType = true
                continue
            }
            // The target declares this type inside one it does not declare,
            // such as `extension Array { struct Inner {} }`. The scanner
            // cannot see whether that outer type is generic, and naming a
            // generic type without arguments does not compile, so the type
            // is treated as unreachable.
            if passedUndeclaredType || records.contains(where: \.isGeneric) {
                isGeneric = true
            }
            // A type declared unconditionally anywhere needs no condition.
            guard !records.contains(where: { $0.conditions.isEmpty }) else {
                continue
            }
            if records.count == 1 {
                // A nested type repeats its enclosing type's clauses.
                for clause in records[0].conditions where !clauses.contains(clause) {
                    clauses.append(clause)
                }
            }
            else {
                let alternatives = records
                    .compactMap { conditionExpression($0.conditions) }
                    .joined(separator: " || ")
                if !clauses.contains(alternatives) {
                    clauses.append(alternatives)
                }
            }
        }
        return (isGeneric, conditionExpression(clauses))
    }

    /// A dotted type name split at the dots outside generic arguments.
    private static func topLevelComponents(of typeName: String) -> [String] {
        var components: [String] = []
        var current = ""
        var depth = 0
        for character in typeName {
            switch character {
            case "<":
                depth += 1
                current.append(character)
            case ">":
                depth -= 1
                current.append(character)
            case "." where depth == 0:
                components.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        components.append(current)
        return components
    }

    static func conditionExpression(_ conditions: [String]) -> String? {
        conditions.isEmpty ? nil : conditions.map { "(\($0))" }.joined(separator: " && ")
    }
}


private struct Scope {
    var typeName: String?
    var isPrivate = false
    var isGeneric = false
    var conditions: [String] = []
}


private struct TypeRecord {
    let name: String
    let isGeneric: Bool
    let conditions: [String]
}


private struct RawDeclaration {
    let form: DeclaredQueryDeclaration.Form
    let subject: String
    let typeName: String?
    let isPrivate: Bool
    let isGeneric: Bool
    let isExcluded: Bool
    let hasConditionalAttribute: Bool
    let conditions: [String]
    let file: String
    let line: Int
}


private struct Walker {

    let file: String

    let converter: SourceLocationConverter

    var types: [TypeRecord] = []

    var declarations: [RawDeclaration] = []

    var imports: [DeclaredQueryImport] = []

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
            guard scope.typeName == nil else {
                return
            }
            let declaration = importDecl.trimmedDescription
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            let declaredImport = DeclaredQueryImport(
                declaration: declaration,
                condition: DeclaredQueryScanner.conditionExpression(scope.conditions),
                module: importDecl.path.first?.name.text ?? declaration
            )
            if !imports.contains(declaredImport) {
                imports.append(declaredImport)
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
            let hasAttribute = Self.hasAttribute(extensionDecl.attributes, named: "SQLQueries")
            let hasConditionalAttribute = Self.hasConditionalAttribute(extensionDecl.attributes, named: "SQLQueries")
            if hasAttribute || hasConditionalAttribute {
                record(
                    .container,
                    subject: "The @SQLQueries extension",
                    node: Syntax(extensionDecl),
                    isExcluded: Self.isExcluded(Syntax(extensionDecl)),
                    hasConditionalAttribute: !hasAttribute,
                    scope: inner
                )
            }
            visit(members: extensionDecl.memberBlock.members, scope: inner)
            return
        }
        if let alias = decl.as(TypeAliasDeclSyntax.self) {
            // A generic alias cannot be named without its arguments either,
            // so it counts as a generic type.
            types.append(TypeRecord(
                name: scope.typeName.map { "\($0).\(alias.name.text)" } ?? alias.name.text,
                isGeneric: scope.isGeneric || alias.genericParameterClause != nil,
                conditions: scope.conditions
            ))
            return
        }
        if let nominal = Self.nominal(decl) {
            let name = scope.typeName.map { "\($0).\(nominal.name)" } ?? nominal.name
            types.append(TypeRecord(
                name: name,
                isGeneric: scope.isGeneric || nominal.isGeneric,
                conditions: scope.conditions
            ))
            var inner = scope
            inner.typeName = name
            inner.isPrivate = scope.isPrivate || Self.isPrivate(nominal.modifiers)
            inner.isGeneric = scope.isGeneric || nominal.isGeneric
            visit(members: nominal.members, scope: inner)
            return
        }
        if let function = decl.as(FunctionDeclSyntax.self),
           Self.hasAttribute(function.attributes, named: "SQLQuery")
            || Self.hasConditionalAttribute(function.attributes, named: "SQLQuery") {
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
                subject: "@SQLQuery '\(function.name.text)'",
                node: Syntax(function),
                isExcluded: Self.isExcluded(Syntax(function)),
                hasConditionalAttribute: !Self.hasAttribute(function.attributes, named: "SQLQuery"),
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
        subject: String,
        node: Syntax,
        isExcluded: Bool,
        hasConditionalAttribute: Bool,
        scope: Scope
    ) {
        declarations.append(RawDeclaration(
            form: form,
            subject: subject,
            typeName: scope.typeName,
            isPrivate: scope.isPrivate,
            isGeneric: scope.isGeneric,
            isExcluded: isExcluded,
            hasConditionalAttribute: hasConditionalAttribute,
            conditions: scope.conditions,
            file: file,
            line: node.startLocation(converter: converter).line
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

    private static func isExcluded(_ node: Syntax) -> Bool {
        node.leadingTrivia.description.contains(DeclaredQueryScanner.exclusionMarker)
    }

    private static func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            (modifier.name.text == "private" || modifier.name.text == "fileprivate")
                && modifier.detail == nil
        }
    }

    /// Whether the attribute appears only inside an `#if` in the attribute
    /// list (`#if DEBUG @SQLQuery #endif`).
    private static func hasConditionalAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { element in
            guard case .ifConfigDecl(let ifConfig) = element else {
                return false
            }
            return ifConfig.description.contains("@\(name)")
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
