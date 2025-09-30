//
//  File.swift
//  
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


public protocol XLEncodable {
    typealias MakeExpression = (inout XLBuilder) -> Void
    func makeSQL(context: inout XLBuilder)
    static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression)
}

extension XLEncodable {
    
    public static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        builder(&context)
    }
}


struct XLEncodableList: XLEncodable {

    var separator: String
    
    var expressions: [any XLEncodable]
    
    init(separator: XLSeparator, expressions: [any XLEncodable]) {
        self.init(separator: separator.rawValue, expressions: expressions)
    }

    init(separator: String, expressions: [any XLEncodable]) {
        self.separator = separator
        self.expressions = expressions
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.list(separator: separator) { listBuilder in
            for expression in expressions {
                listBuilder.listItem { builder in
                    expression.makeSQL(context: &builder)
                }
            }
        }
    }
    
}


public struct XLEncoding {
    public let sql: String
    public let entities: Set<String>
}

public protocol XLEncoder {
    func makeSQL(_ expression: any XLEncodable) -> XLEncoding
}


public struct XLiteEncoder: XLEncoder {
    
    public var formatter: XLiteFormatter
    
    public init(formatter: XLiteFormatter) {
        self.formatter = formatter
    }
    
    public func makeSQL(_ expression: XLEncodable) -> XLEncoding {
        var builder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression.makeSQL(context: &builder)
        return XLEncoding(
            sql: builder.build(),
            entities: builder.entities()
        )
    }
}


public protocol XLFormatter {
    func null() -> String
    func integer(_ value: Int) -> String
    func real(_ value: Double) -> String
    func text(_ value: String) -> String
    func blob(_ value: Data) -> String
    func name(_ value: String) -> String
    func scopedName(_ values: [String]) -> String
    func namedBinding(_ named: String) -> String
    func indexedBinding(_ index: Int) -> String
}


public struct XLiteFormatter: XLFormatter {
    
    public enum IdentifierFormattingOptions {
        case noEscape
        case sqlite
        case mysqlCompatible
        case microsoftCompatible
        
        func escape(_ name: String) -> String {
            switch self {
            case .noEscape:
                name
            case .sqlite:
                "\"\(name)\""
            case .mysqlCompatible:
                "`\(name)`"
            case .microsoftCompatible:
                "[\(name)]"
            }
        }
    }
    
    public var identifierFormattingOptions: IdentifierFormattingOptions
    
    public init(identifierFormattingOptions: IdentifierFormattingOptions = .sqlite) {
        self.identifierFormattingOptions = identifierFormattingOptions
    }

    public func null() -> String {
        "NULL"
    }
    
    public func integer(_ value: Int) -> String {
        String(format: "%d", value)
    }
    
    public func real(_ value: Double) -> String {
        String(value)
    }
    
    public func text(_ text: String) -> String {
        "'\(text)'"
    }
    
    public func text(_ text: StaticString) -> String {
        "'\(text)'"
    }

    public func blob(_ data: Data) -> String {
        "x'\(data.hex())'"
    }
    
    public func name(_ value: String) -> String {
        identifierFormattingOptions.escape(value)
    }
    
    public func scopedName(_ values: [String]) -> String {
        values.map(name).joined(separator: ".")
    }
    
    public func namedBinding(_ named: String) -> String {
        ":\(named)"
    }
    
    public func indexedBinding(_ index: Int) -> String {
        String(format: "?%d", index + 1)
    }
}


public protocol XLBuilder {
    typealias Builder = (inout XLBuilder) -> Void
    typealias ListBuilder = (inout XLListBuilder) -> Void
    typealias CommonTablesBuilder = (inout XLCommonTablesBuilder) -> Void
    typealias ColumnsBuilder = (inout XLColumnDefinitionsBuilder) -> Void
    func build() -> String
    func entities() -> Set<String>
    mutating func entity(_ name: String)
    mutating func null()
    mutating func integer(_ value: Int)
    mutating func real(_ value: Double)
    mutating func text(_ value: String)
    mutating func blob(_ value: Data)
    mutating func name(_ value: XLName)
    mutating func qualifiedName(_ value: XLQualifiedName)
    mutating func namedBinding(_ name: XLName)
    mutating func indexedBinding(_ index: Int)
    mutating func list(separator: String, items: ListBuilder)
    mutating func block(beginsWith prefix: String, endsWith suffix: String, separator: XLSeparator, contents: Builder)
    mutating func unaryPrefix(_ operator: String, expression: Builder)
    mutating func unarySuffix(_ operator: String, expression: Builder)
    mutating func unaryOperator(_ operator: String, expression: Builder)
    mutating func binaryOperator(_ operator: String, left: Builder, right: Builder)
    mutating func between(term: Builder, minimum: Builder, maximum: Builder)
    mutating func cast(type: String, expression: Builder)
    mutating func simpleFunction(name: String, parameters: ListBuilder)
    mutating func aggregateFunction(name: String, distinct: Bool, parameters: ListBuilder)
    mutating func alias(_ name: XLName, expression: Builder)
    mutating func commonTables(builder: CommonTablesBuilder)
    mutating func createTable(_ name: XLQualifiedName)
    mutating func createTable(_ name: XLQualifiedName, builder: ColumnsBuilder)
}

extension XLBuilder {
    public mutating func parenthesis(contents: Builder) {
        block(beginsWith: "(", endsWith: ")", separator: .elided, contents: contents)
    }
}


public protocol XLListBuilder {
    typealias Builder = (inout XLBuilder) -> Void
    func build() -> String
    func entities() -> Set<String>
    mutating func listItem(expression: Builder) -> Void
}


public protocol XLCommonTablesBuilder {
    typealias Builder = (inout XLBuilder) -> Void
    func build() -> String
    func entities() -> Set<String>
    mutating func commonTable(alias: XLName, expression: Builder) -> Void
}


public protocol XLColumnDefinitionsBuilder {
    func build() -> String
    mutating func column(name: XLName, nullable: Bool)
}


public struct XLiteBuilder: XLBuilder {
    
    private var formatter: XLFormatter
    
    private var _tokens: [String] = []
    
    private var _entities: Set<String> = []
    
    public init(formatter: XLFormatter) {
        self.formatter = formatter
    }
    
    private mutating func append(_ tokens: String...) {
        _tokens.append(contentsOf: tokens.filter({ !$0.isEmpty }))
    }
    
    public func build() -> String {
        _tokens.joined(separator: XLSeparator.space.rawValue)
    }
    
    public func entities() -> Set<String> {
        _entities
    }
    
//    public mutating func boolean(_ value: Bool) {
//        append(formatter.boolean(value))
//    }
    
    public mutating func entity(_ name: String) {
        _entities.insert(name)
    }
    
    public mutating func null() {
        append(formatter.null())
    }
    
    public mutating func integer(_ value: Int) {
        append(formatter.integer(value))
    }
    
    public mutating func real(_ value: Double) {
        append(formatter.real(value))
    }
    
    public mutating func text(_ value: String) {
        append(formatter.text(value))
    }
    
    public mutating func blob(_ value: Data) {
        append(formatter.blob(value))
    }
    
//    public mutating func uuid(_ value: UUID) {
//        append(formatter.uuid(value))
//    }
    
//    public mutating func url(_ value: URL) {
//        append(formatter.url(value))
//    }
    
    public mutating func name(_ value: XLName) {
        append(formatter.name(value.rawValue))
    }
    
    public mutating func qualifiedName(_ name: XLQualifiedName) {
        append(formatter.scopedName(name.components.map { $0.rawValue }))
    }
    
    public mutating func namedBinding(_ name: XLName) {
        append(formatter.namedBinding(name.rawValue))
    }
    
    public mutating func indexedBinding(_ index: Int) {
        append(formatter.indexedBinding(index))
    }
    
    public mutating func list(separator: String, items: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(formatter: formatter, separator: separator)
        items(&listBuilder)
        append(listBuilder.build())
        _entities.formUnion(listBuilder.entities())
    }
    
    public mutating func block(beginsWith prefix: String, endsWith suffix: String, separator: XLSeparator, contents: (inout XLBuilder) -> Void) {
        var blockBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        contents(&blockBuilder)
        append(prefix + separator.rawValue + blockBuilder.build() + separator.rawValue + suffix)
        _entities.formUnion(blockBuilder.entities())
    }
    
    public mutating func unaryPrefix(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(`operator` + " " + expressionBuilder.build())
        _entities.formUnion(expressionBuilder.entities())
    }
    
    public mutating func unarySuffix(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(expressionBuilder.build() + " " + `operator`)
        _entities.formUnion(expressionBuilder.entities())
    }
    
    public mutating func unaryOperator(_ operator: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(`operator` + expressionBuilder.build())
        _entities.formUnion(expressionBuilder.entities())
    }
    
    public mutating func binaryOperator(_ operator: String, left: (inout XLBuilder) -> Void, right: (inout XLBuilder) -> Void) {
        var lhsExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        var rhsExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        left(&lhsExpressionBuilder)
        right(&rhsExpressionBuilder)
        append(lhsExpressionBuilder.build() + " " + `operator` + " " + rhsExpressionBuilder.build())
        _entities.formUnion(lhsExpressionBuilder.entities())
        _entities.formUnion(rhsExpressionBuilder.entities())
    }
    
    public mutating func between(term: (inout XLBuilder) -> Void, minimum: (inout XLBuilder) -> Void, maximum: (inout XLBuilder) -> Void) {
        var termExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        var minimumExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        var maximumExpressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        term(&termExpressionBuilder)
        minimum(&minimumExpressionBuilder)
        maximum(&maximumExpressionBuilder)
        append(termExpressionBuilder.build() + " BETWEEN " + minimumExpressionBuilder.build() + " AND " + maximumExpressionBuilder.build())
        _entities.formUnion(termExpressionBuilder.entities())
        _entities.formUnion(minimumExpressionBuilder.entities())
        _entities.formUnion(maximumExpressionBuilder.entities())
    }
    
    public mutating func cast(type: String, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append("CAST(" + expressionBuilder.build() + " AS " + type + ")")
        _entities.formUnion(expressionBuilder.entities())
    }
    
    public mutating func simpleFunction(name: String, parameters: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(formatter: formatter, separator: ", ")
        parameters(&listBuilder)
        append(name + "(" + listBuilder.build() + ")")
        _entities.formUnion(listBuilder.entities())
    }
    
    public mutating func aggregateFunction(name: String, distinct: Bool, parameters: (inout XLListBuilder) -> Void) {
        var listBuilder: XLListBuilder = XLiteListBuilder(formatter: formatter, separator: ", ")
        parameters(&listBuilder)
        if distinct {
            append(name + "(DISTINCT " + listBuilder.build() + ")")
        }
        else {
            append(name + "(" + listBuilder.build() + ")")
        }
        _entities.formUnion(listBuilder.entities())
    }
    
    public mutating func alias(_ name: XLName, expression: (inout XLBuilder) -> Void) {
        var expressionBuilder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&expressionBuilder)
        append(expressionBuilder.build() + " AS " + formatter.name(name.rawValue))
        _entities.formUnion(expressionBuilder.entities())
    }
    
    public mutating func commonTables(builder: (inout XLCommonTablesBuilder) -> Void) {
        var commonTablesBuilder: XLCommonTablesBuilder = XLiteCommonTablesBuilder(formatter: formatter)
        builder(&commonTablesBuilder)
        append("WITH " + commonTablesBuilder.build())
        _entities.formUnion(commonTablesBuilder.entities())
    }

    public mutating func createTable(_ name: XLQualifiedName) {
        let tableName = formatter.scopedName(name.components.map { $0.rawValue })
        append("CREATE TABLE IF NOT EXISTS " + tableName + " AS")
    }

    public mutating func createTable(_ name: XLQualifiedName, builder: (inout XLColumnDefinitionsBuilder) -> Void) {
        var columnsBuilder: XLColumnDefinitionsBuilder = XLiteColumnDefinitionsBuilder(formatter: formatter)
        builder(&columnsBuilder)
        let tableName = formatter.scopedName(name.components.map { $0.rawValue })
        append("CREATE TABLE IF NOT EXISTS " + tableName + " (" + columnsBuilder.build() + ")")
    }
}


public struct XLiteListBuilder: XLListBuilder {
    
    private var formatter: XLFormatter
    
    private var separator: String
    
    private var _tokens: [String] = []
    
    private var _entities: Set<String> = []
    
    init(formatter: XLFormatter, separator: String) {
        self.separator = separator
        self.formatter = formatter
    }
    
    public func build() -> String {
        _tokens.joined(separator: separator)
    }
    
    public func entities() -> Set<String> {
        _entities
    }
    
    public mutating func listItem(expression: (inout XLBuilder) -> Void) {
        var builder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&builder)
        _tokens.append(builder.build())
        _entities.formUnion(builder.entities())
    }
}


public struct XLiteCommonTablesBuilder: XLCommonTablesBuilder {
    
    private var formatter: XLFormatter
    
    private var _tokens: [String] = []
    
    private var _entities: Set<String> = []

    init(formatter: XLFormatter) {
        self.formatter = formatter
    }
    
    public func build() -> String {
        _tokens.joined(separator: ", ")
    }
    
    public func entities() -> Set<String> {
        _entities
    }
    
    public mutating func commonTable(alias: XLName, expression: (inout XLBuilder) -> Void) {
        var builder: XLBuilder = XLiteBuilder(formatter: formatter)
        expression(&builder)
        _tokens.append(formatter.name(alias.rawValue) + " AS (" + builder.build() + ")")
        _entities.formUnion(builder.entities())
    }
}


public struct XLiteColumnDefinitionsBuilder: XLColumnDefinitionsBuilder {
    
    private var formatter: XLFormatter
    
    private var _tokens: [String] = []

    init(formatter: XLFormatter) {
        self.formatter = formatter
    }
    
    public func build() -> String {
        _tokens.joined(separator: ", ")
    }
    
    ///
    /// Append a column to a table CREATE statement.
    /// Note: We do not include the type definition, but instead rely on XLite type affinity to cast the stored value to the type defined in Swift.
    ///
    public mutating func column(name: XLName, nullable: Bool) {
        
        #warning("TODO: Include primary key specifier")
        
        #warning("TODO: Include default value")
        
        var components: [String] = []
        components.append(formatter.name(name.rawValue))
        if !nullable {
            components.append("NOT NULL")
        }
        _tokens.append(components.joined(separator: " "))
    }
}
