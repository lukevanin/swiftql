//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/09/20.
//

import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros


// MARK: - Builder


struct MetaProperty {
    
    enum ColumnKind {
        
        case reference
        
        case result
    }
    
    enum Mutability {
        
        case mutable
        
        case immutable
    }
    
    var mutability: Mutability
    var name: String
    var alias: String
    var optional: Bool
    var type: String
    
    var qualifiedType: String {
        if optional {
            type + "?"
        }
        else {
            type
        }
    }
    
    func columnType(kind: ColumnKind) -> String {
        switch kind {
        case .reference:
            "XLColumnReference<\(qualifiedType)>"
        case .result:
            "XLColumnResult<\(qualifiedType)>"
        }
    }

    func makePropertyDecl() -> String {
        "public let \(name): \(qualifiedType)"
    }

    func makeColumnPropertyDecl(kind: ColumnKind) -> String {
        "public let \(name): \(columnType(kind: kind))"
    }
    
    func makeInstance(kind: ColumnKind, dependency: String) -> String {
        "\(columnType(kind: kind))(dependency: \(dependency), as: \"\(alias)\")"
    }
}

#warning("TODO: Remove anonymous properties")

struct MetaBuilder {
    
    private enum InternalError: LocalizedError {
        case unsupportedType(String)
        case bindingSpecifierNotSupported(String)
        
        var errorDescription: String? {
            switch self {
            case let .unsupportedType(type):
                return "Unsupported type \(type)."
            case let .bindingSpecifierNotSupported(bindingSpecifier):
                return "Binding specifier not supported: \(bindingSpecifier). Use var or let."
            }
        }
    }
    
    let structName: String
    
    let tableName: String
    
    let declaration: StructDeclSyntax
    
    let properties: [MetaProperty]
    
    let optionalProperties: [MetaProperty]
    
    let anonymousProperties: [MetaProperty]
    
    let anonymousOptionalProperties: [MetaProperty]

    let mutableProperties: [MetaProperty]

    init(node: AttributeSyntax, declaration: DeclGroupSyntax) throws {
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            throw SQLMacroError.unsupportedType
        }
        try self.init(node: node, declaration: declaration)
    }
    
    init(node: AttributeSyntax, declaration: StructDeclSyntax) throws {
        self.structName = declaration.name.text
        self.declaration = declaration
        
        if
            case let .argumentList(arguments) = node.arguments,
            let nameArg = arguments.first(where: { $0.label?.text == "name" }),
            let nameLiteral = nameArg.expression.as(StringLiteralExprSyntax.self),
            nameLiteral.segments.count == 1,
            case let .stringSegment(nameString)? = nameLiteral.segments.first
        {
            self.tableName = nameString.content.text
        }
        else {
            self.tableName = structName
        }
        
        let properties = try declaration.memberBlock.members
            .compactMap { member in
                guard let declaration = member.decl.as(VariableDeclSyntax.self) else {
                    return nil
                }
                guard let binding = declaration.bindings.first else {
                    return nil
                }
                let mutability: MetaProperty.Mutability
                switch declaration.bindingSpecifier.text {
                case "var":
                    mutability = .mutable
                case "let":
                    mutability = .immutable
                default:
                    throw InternalError.bindingSpecifierNotSupported(declaration.bindingSpecifier.text )
                }
                return (binding, mutability)
            }
            .compactMap { (binding: PatternBindingSyntax, mutability: MetaProperty.Mutability) -> MetaProperty? in
                
                guard let typeAnnotation = binding.typeAnnotation else {
                    return nil
                }
                
                var type: String
                var optional: Bool
                
                if let simpleType = typeAnnotation.type.as(IdentifierTypeSyntax.self) {
                    type = simpleType.name.text
                    optional = false
                }
                else if let optionalType = typeAnnotation.type.as(OptionalTypeSyntax.self)?.wrappedType.as(IdentifierTypeSyntax.self) {
                    type = optionalType.name.text
                    optional = true
                }
                else {
                    throw InternalError.unsupportedType(String(describing: typeAnnotation.type))
                }
                
                let name = binding.pattern.as(IdentifierPatternSyntax.self)!.identifier.text
                
                return MetaProperty(mutability: mutability, name: name, alias: name, optional: optional, type: type)
            }
        self.properties = properties
        self.optionalProperties = properties.map {
            MetaProperty(mutability: $0.mutability, name: $0.name, alias: $0.alias, optional: true, type: $0.type)
        }
        self.anonymousProperties = properties.map {
            MetaProperty(mutability: $0.mutability, name: $0.name, alias: $0.name, optional: $0.optional, type: $0.type)
        }
        self.anonymousOptionalProperties = properties.map {
            MetaProperty(mutability: $0.mutability, name: $0.name, alias: $0.name, optional: true, type: $0.type)
        }
        self.mutableProperties = properties.filter {
            $0.mutability == .mutable
        }

    }


    func makeConformanceExtension(name: String) -> String {
        var context = SwiftSyntaxBuilder()
        context.block("extension \(structName): \(name)") { context in
            
        }
        return context.build()
    }

    
    // Build result-only meta data, used to select explicit columns without an underlying table.
    func makeMetaResultExtension(table: Bool) -> String {
        var context = SwiftSyntaxBuilder()
        context.block("extension \(structName): XLResult") { context in
            
            makeCommonMeta(context: &context, table: table)
        }
        return context.build()
    }
    
    // Build table meta data, used to select from concrete tables and views which are defined by the database schema.
    func makeMetaTableExtension() -> String {
        var context = SwiftSyntaxBuilder()

        context.block("extension \(structName): XLTable") { context in
            
            context.block("public static func sqlTableName() -> XLQualifiedTableName") { context in
                context.line("XLQualifiedTableName(name: XLName(\(quoted(tableName))))")
            }
            
            makeWriter(context: &context)

            context.block("public static func makeSQLTable(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult") { context in
                var parameters: [String] = []
                parameters.append("_namespace: namespace")
                parameters.append("_dependency: dependency")
                for property in properties {
                    parameters.append(property.name + ": " + property.makeInstance(kind: .reference, dependency: "dependency"))
                }
                context.block("MetaResult(" + parameters.joined(separator: ", ") + ")") { context in
                    context.declaration("\(structName)") { context in
                        for property in properties {
                            context.item { context in
                                context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .reference, dependency: "dependency")), alias: \(quoted(property.name)))")
                            }
                        }
                    }
                }
            }

            context.block("public static func makeSQLNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult") { context in
                var parameters: [String] = []
                parameters.append("_namespace: namespace")
                parameters.append("_dependency: dependency")
                for property in properties {
                    parameters.append(property.name + ": " + property.makeInstance(kind: .reference, dependency: "dependency"))
                }
                context.block("MetaNamedResult(" + parameters.joined(separator: ", ") + ")") { context in
                    context.declaration("\(structName)") { context in
                        for property in properties {
                            context.item { context in
                                context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .reference, dependency: "dependency")), alias: \(quoted(property.name)))")
                            }
                        }
                    }
                }
            }
            
            context.block("public static func makeSQLNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult") { context in
                var parameters: [String] = []
                parameters.append("_namespace: namespace")
                parameters.append("_dependency: dependency")
                for property in optionalProperties {
                    parameters.append(property.name + ": " + property.makeInstance(kind: .reference, dependency: "dependency"))
                }
                context.block("return MetaNullableResult(" + parameters.joined(separator: ", ") + ")") { context in
                    context.declaration("Nullable") { context in
                        for property in optionalProperties {
                            context.item { context in
                                context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .reference, dependency: "dependency")), alias: \(quoted(property.name)))")
                            }
                        }
                    }
                }
            }
            
            context.block("public static func makeSQLNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult") { context in
                var parameters: [String] = []
                parameters.append("_namespace: namespace")
                parameters.append("_dependency: dependency")
                for property in optionalProperties {
                    parameters.append(property.name + ": " + property.makeInstance(kind: .reference, dependency: "dependency"))
                }
                context.block("return MetaNullableNamedResult(" + parameters.joined(separator: ", ") + ")") { context in
                    context.declaration("Nullable") { context in
                        for property in optionalProperties {
                            context.item { context in
                                context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .reference, dependency: "dependency")), alias: \(quoted(property.name)))")
                            }
                        }
                    }
                }
            }
            
            makeCreate(context: &context)
        }
            
        return context.build()
    }
    
    private func makeWriter(context: inout SwiftSyntaxBuilder) {
        
        context.block("public struct MetaWritableTable: XLMetaWritableTable") { context in

            context.line("public typealias Row = \(structName)")
            context.line("public typealias Dependency = XLEncodable & XLColumnDependency")

            context.line("public let _table: any XLEncodable")

            context.line("public let _namespace: XLNamespace")
            context.line("private let _dependency: XLTableDeclaration")
            
            for property in properties {
                context.line(property.makeColumnPropertyDecl(kind: .reference))
            }

            context.block("public init(namespace: XLNamespace, dependency: XLTableDeclaration)") { context in
                context.line("_namespace = namespace")
                context.line("_dependency = dependency")
                context.line("_table = dependency")
                for property in properties {
                    context.line(property.name + " = " + property.makeInstance(kind: .reference, dependency: "dependency"))
                }
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in

            }
        }

        context.block("public struct MetaInsert: XLMetaInsert") { context in
            
            context.line("public typealias Row = \(structName)")
            
            for property in properties {
                context.line("private let \(property.name): any XLExpression<\(property.qualifiedType)>")
            }
            
            // Discrete parameters.
            var parameters: [String] = []
            for property in properties {
                parameters.append("\(property.name): any XLExpression<\(property.qualifiedType)>")
            }
            context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                for property in properties {
                    context.line("self.\(property.name) = \(property.name)")
                }
            }
            
            // Instance parameter.
            context.block("public init(_ instance: \(structName))") { context in
                for property in properties {
                    context.line("\(property.name) = XLTypeAffinityExpression<\(property.qualifiedType)>(expression: instance.\(property.name))")
                }
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                
                context.block("context.parenthesis") { context in
                    context.block("$0.list(separator: \",\")") { context in
                        for property in properties {
                            context.block("$0.listItem") { context in
                                context.line("$0.name(XLName(\"\(property.name)\"))")
                            }
                        }
                    }
                }
                
                context.block("context.unaryPrefix(\"VALUES\")") { context in
                    context.block("$0.parenthesis") { context in
                        context.block("$0.list(separator: \",\")") { context in
                            for property in properties {
                                context.block("$0.listItem") { context in
                                    context.line("\(property.name).writeSQL(context: &$0)")
                                }
                            }
                        }
                    }
                }
            }
        }
            
        context.block("public struct MetaUpdate: XLMetaUpdate") { context in
            
            context.line("public typealias Row = \(structName)")
            
            for property in properties {
                context.line("public var \(property.name): Optional<any SwiftQL.XLExpression<\(property.qualifiedType)>>")
            }
            
            context.block("public init()") { context in
                for property in properties {
                    context.line("\(property.name) = nil")
                }
            }
            
            var parameters: [String] = []
            for property in properties {
                parameters.append("\(property.name): Optional<any XLExpression<\(property.qualifiedType)>> = nil")
            }
            context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                for property in properties {
                    context.line("self.\(property.name) = \(property.name)")
                }
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.block("context.unaryPrefix(\"SET\")") { context in
                    context.block("$0.list(separator: \",\")") { context in
                        for property in properties {
                            context.block("if let \(property.name)") { context in
                                context.block("$0.listItem") { context in
                                    context.block("$0.binaryOperator(\"=\", left: XLName(\"\(property.name)\").makeSQL)") { context in
                                        context.line("\(property.name).writeSQL(context: &$0)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
               
        context.block("public struct UpdateRequest") { context in
            
            context.line("public typealias Row = \(structName)")
            
            for property in mutableProperties {
                context.line("public var \(property.name): Optional<\(property.type)>")
            }
            
            context.block("public init()") { context in
                for property in mutableProperties {
                    context.line("self.\(property.name) = nil")
                }
            }
            
            if !mutableProperties.isEmpty {
                var parameters: [String] = []
                for property in mutableProperties {
                    parameters.append("\(property.name): Optional<\(property.type)> = nil")
                }
                context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                    for property in mutableProperties {
                        context.line("self.\(property.name) = \(property.name)")
                    }
                }
            }
            
            context.block("public func apply(to entity: Row) -> Row") { context in
                context.line("var output = entity")
                for property in mutableProperties {
                    context.block("if let value = \(property.name)") { context in
                        context.line("output.\(property.name) = value")
                    }
                }
                context.line("return output")
            }
            
            context.block("public func makeUpdate() -> MetaUpdate") { context in
                context.line("var output = MetaUpdate()")
                for property in mutableProperties {
                    context.block("if let value = \(property.name)") { context in
                        if property.optional {
                            context.line("output.\(property.name) = XLTypeAffinityExpression<\(property.qualifiedType)>(expression: value.toNullable())")
                        }
                        else {
                            context.line("output.\(property.name) = XLTypeAffinityExpression<\(property.qualifiedType)>(expression: value)")
                        }
                    }
                }
                context.line("return output")
            }
        }
        
        context.block("public static func makeSQLInsert(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable") { context in
            context.line("MetaWritableTable(namespace: namespace, dependency: dependency)")
        }
        
        context.block("public static func makeSQLUpdate(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable") { context in
            context.line("MetaWritableTable(namespace: namespace, dependency: dependency)")
        }
    }
    
    private func makeCreate(context: inout SwiftSyntaxBuilder) {
        
        context.block("public struct MetaCreate: XLMetaCreate") { context in
            
            context.line("public typealias Table = \(structName)")
            
            context.line("public let name: XLQualifiedTableName")
            
            context.block("public init(name: XLQualifiedTableName)") { context in
                context.line("self.name = name")
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in

                context.block("context.createTable(self.name)") { context in
                    for property in properties {
                        context.line("$0.column(name: XLName(\"\(property.name)\"), nullable: \(property.optional))")
                    }
                }
            }
        }
        
        context.block("public struct MetaCreateAs: XLMetaCreate") { context in
            
            context.line("public typealias Table = \(structName)")
            
            context.line("public let name: XLQualifiedTableName")
            
            context.block("public init(name: XLQualifiedTableName)") { context in
                context.line("self.name = name")
            }
            
            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("context.createTable(self.name)")
            }
        }
        
        context.block("public static func makeSQLCreate() -> MetaCreate") { context in
            context.line("MetaCreate(name: sqlTableName())")
        }
        
        context.block("public static func makeSQLCreateAs() -> MetaCreateAs") { context in
            context.line("MetaCreateAs(name: sqlTableName())")
        }
    }
    
    private func makeCommonMeta(context: inout SwiftSyntaxBuilder, table: Bool) {
        
        var properties: [MetaProperty]
        var optionalProperties: [MetaProperty]
        let conformances: [String] = ["XLRowReadable", "XLEncodable"]
        let columnKind: MetaProperty.ColumnKind
        if table {
            // Table
            columnKind = .reference
            properties = self.properties
            optionalProperties = self.optionalProperties
        }
        else {
            // Select result
            columnKind = .result
            properties = self.anonymousProperties
            optionalProperties = self.anonymousOptionalProperties

        }

        // Nullable
        context.block("public struct Nullable: XLMetaNullable") { context in
            
            context.line("public typealias Basis = \(structName)")
            
            for property in optionalProperties {
                context.line(property.makePropertyDecl())
            }
        }

        // MetaResult
        let metaResultConformances = (["XLMetaResult"] + conformances).joined(separator: ", ")
        context.block("public struct MetaResult: \(metaResultConformances)") { context in

            context.line("public typealias Row = \(structName)")
            context.line("public typealias RowIterator = (XLRowReader) throws -> \(structName)")
            context.line("public let _namespace: XLNamespace")
            context.line("public let _dependency: XLTableDeclaration")

            for property in properties {
                context.line(property.makeColumnPropertyDecl(kind: columnKind))
            }

            context.line("public let _iterator: RowIterator")

            context.block("public func readRow(reader: XLRowReader) throws -> \(structName)") { context in
                context.line("try _iterator(reader)")
            }

            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("_dependency.makeSQL(context: &context)")
            }
        }
        
        // MetaNamedResult
        let metaNamedResultConformances = (["XLMetaNamedResult"] + conformances).joined(separator: ", ")
        context.block("public struct MetaNamedResult: \(metaNamedResultConformances)") { context in

            context.line("public typealias Row = \(structName)")
            context.line("public typealias RowIterator = (XLRowReader) throws -> \(structName)")
            context.line("public let _namespace: XLNamespace")
            context.line("public let _dependency: XLNamedTableDeclaration")

            for property in properties {
                context.line(property.makeColumnPropertyDecl(kind: columnKind))
            }

            context.line("public let _iterator: RowIterator")

            context.block("public func readRow(reader: XLRowReader) throws -> \(structName)") { context in
                context.line("try _iterator(reader)")
            }

            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("_dependency.makeSQL(context: &context)")
            }
        }
        
        // MetaNullableResult
        let metaNullableResultConformances = (["XLMetaNullableResult"] + conformances).joined(separator: ", ")
        context.block("public struct MetaNullableResult: \(metaNullableResultConformances)") { context in

            context.line("public typealias Row = \(structName).Nullable")
            context.line("public typealias RowIterator = (XLRowReader) throws -> \(structName).Nullable")
            context.line("public let _namespace: XLNamespace")
            context.line("public let _dependency: XLTableDeclaration")

            for property in optionalProperties {
                context.line(property.makeColumnPropertyDecl(kind: columnKind))
            }

            context.line("public let _iterator: RowIterator")

            context.block("public func readRow(reader: XLRowReader) throws -> \(structName).Nullable") { context in
                context.line("try _iterator(reader)")
            }

            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("_dependency.makeSQL(context: &context)")
            }
        }
        
        // MetaNullableNamedResult
        let metaNullableNamedResultConformances = (["XLMetaNullableNamedResult"] + conformances).joined(separator: ", ")
        context.block("public struct MetaNullableNamedResult: \(metaNullableNamedResultConformances)") { context in

            context.line("public typealias Row = \(structName).Nullable")
            context.line("public typealias RowIterator = (XLRowReader) throws -> \(structName).Nullable")
            context.line("public let _namespace: XLNamespace")
            context.line("public let _dependency: XLNamedTableDeclaration")

            for property in optionalProperties {
                context.line(property.makeColumnPropertyDecl(kind: columnKind))
            }

            context.line("public let _iterator: RowIterator")

            context.block("public func readRow(reader: XLRowReader) throws -> \(structName).Nullable") { context in
                context.line("try _iterator(reader)")
            }

            context.block("public func makeSQL(context: inout XLBuilder)") { context in
                context.line("_dependency.makeSQL(context: &context)")
            }
        }
        
        // MetaCommonTable
        context.block("public struct MetaCommonTable: XLMetaCommonTable") { context in
            
            context.line("public typealias Result = \(structName)")

            context.line("public let definition: XLCommonTableDependency")

            context.block("public init(commonTable: XLCommonTableDependency)") { context in
                context.line("self.definition = commonTable")
            }
        }

        // Reader
        context.block("public struct SQLReader: XLRowReadable") { context in

            context.line("public typealias Row = \(structName)")

            for property in properties {
                context.line("private let \(property.name): any SwiftQL.XLExpression<\(property.qualifiedType)>")
            }

            var parameters: [String] = []
            for property in properties {
                parameters.append("\(property.name): any SwiftQL.XLExpression<\(property.qualifiedType)>")
            }
            context.block("public init(\(parameters.joined(separator: ", ")))") { context in
                for property in properties {
                    context.line("self.\(property.name) = \(property.name)")
                }
            }

            context.block("public func readRow(reader: XLRowReader) throws -> \(structName)") { context in
                context.declaration("\(structName)") { context in
                    for property in properties {
                        context.item { context in
                            context.line("\(property.name): try reader.column(\(property.name), alias: \(quoted(property.name)))")
                        }
                    }
                }
            }
        }
    
        // Static methods
        
        var columnParameters: [String] = []
        for property in properties {
            columnParameters.append("\(property.name): any SwiftQL.XLExpression<\(property.qualifiedType)>")
        }
        context.block("public static func columns(\(columnParameters.joined(separator: ", "))) -> MetaResult") { context in
            context.block("result") { context in
                context.declaration("SQLReader") { context in
                    for property in properties {
                        context.item { context in
                            context.line("\(property.name): \(property.name)")
                        }
                    }
                }
            }
        }
        
        context.block("public static func makeSQLCommonTable(namespace: XLNamespace, dependency: XLCommonTableDependency) -> MetaCommonTable") { context in
            context.line("MetaCommonTable(commonTable: dependency)")
        }

        context.block("public static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaResult") { context in
            var parameters: [String] = []
            parameters.append("_namespace: namespace")
            parameters.append("_dependency: dependency")
            for property in anonymousProperties {
                parameters.append(property.name + ": " + property.makeInstance(kind: columnKind, dependency: "dependency"))
            }
            parameters.append("_iterator: iterator")
            context.line("return MetaResult(" + parameters.joined(separator: ", ") + ")")
        }

        context.block("public static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaNamedResult") { context in
            var parameters: [String] = []
            parameters.append("_namespace: namespace")
            parameters.append("_dependency: dependency")
            for property in anonymousProperties {
                parameters.append(property.name + ": " + property.makeInstance(kind: columnKind, dependency: "dependency"))
            }
            parameters.append("_iterator: iterator")
            context.line("return MetaNamedResult(" + parameters.joined(separator: ", ") + ")")
        }
        
        context.block("public static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult") { context in
            var parameters: [String] = []
            parameters.append("_namespace: namespace")
            parameters.append("_dependency: dependency")
            for property in anonymousProperties {
                parameters.append(property.name + ": " + property.makeInstance(kind: columnKind, dependency: "dependency"))
            }
            context.block("return MetaResult(" + parameters.joined(separator: ", ") + ")") { context in
                context.declaration("\(structName)") { context in
                    for property in anonymousProperties {
                        context.item { context in
                            context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .result, dependency: "dependency")), alias: \(quoted(property.name)))")
                        }
                    }
                }
            }
        }
        
        context.block("public static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult") { context in
            var parameters: [String] = []
            parameters.append("_namespace: namespace")
            parameters.append("_dependency: dependency")
            for property in anonymousProperties {
                parameters.append(property.name + ": " + property.makeInstance(kind: columnKind, dependency: "dependency"))
            }
            context.block("return MetaNamedResult(" + parameters.joined(separator: ", ") + ")") { context in
                context.declaration("\(structName)") { context in
                    for property in anonymousProperties {
                        context.item { context in
                            context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .result, dependency: "dependency")), alias: \(quoted(property.name)))")
                        }
                    }
                }
            }
        }
        
        context.block("public static func makeSQLAnonymousNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult") { context in
            var parameters: [String] = []
            parameters.append("_namespace: namespace")
            parameters.append("_dependency: dependency")
            for property in anonymousOptionalProperties {
                parameters.append(property.name + ": " + property.makeInstance(kind: columnKind, dependency: "dependency"))
            }
            context.block("return MetaNullableResult(" + parameters.joined(separator: ", ") + ")") { context in
                context.declaration("Nullable") { context in
                    for property in anonymousOptionalProperties {
                        context.item { context in
                            context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .result, dependency: "dependency")), alias: \(quoted(property.name)))")
                        }
                    }
                }
            }
        }
        
        context.block("public static func makeSQLAnonymousNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult") { context in
            var parameters: [String] = []
            parameters.append("_namespace: namespace")
            parameters.append("_dependency: dependency")
            for property in anonymousOptionalProperties {
                parameters.append(property.name + ": " + property.makeInstance(kind: columnKind, dependency: "dependency"))
            }
            context.block("return MetaNullableNamedResult(" + parameters.joined(separator: ", ") + ")") { context in
                context.declaration("Nullable") { context in
                    for property in anonymousOptionalProperties {
                        context.item { context in
                            context.line("\(property.name): try $0.column(\(property.makeInstance(kind: .result, dependency: "dependency")), alias: \(quoted(property.name)))")
                        }
                    }
                }
            }
        }    }
    
    func makeMemberwizeInitializer() -> String {
        var context = SwiftSyntaxBuilder()
        var parameters: [String] = []
        for property in properties {
            parameters.append("\(property.name): \(property.qualifiedType)")
        }
        context.block("public init(\(parameters.joined(separator: ", ")))") { context in
            for property in properties {
                context.line("self.\(property.name) = \(property.name)")
            }
        }
        return context.build()
    }
    
//    private func alias(at index: Int) -> String {
//        "c\(index)"
//    }
    
    private func quoted(_ input: String) -> String {
        "\"\(input)\""
    }
}
