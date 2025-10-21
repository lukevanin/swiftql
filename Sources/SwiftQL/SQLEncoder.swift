//
//  XLEncoder.swift
//  
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


///
/// Defines a type that can be transformed into an SQL expression.
///
public protocol XLEncodable {
    typealias MakeExpression = (inout XLBuilder) -> Void
    
    ///
    /// Constructs an SQL expression at runtime.
    ///
    /// Implement this method to construct the SQL statement to encode a custom type.
    ///
    func makeSQL(context: inout XLBuilder)
    
    ///
    /// Wraps an SQL expression.
    ///
    /// The `unwrapSQL` method is applied to every occurrance of the custom type in an SQL expression
    /// when it is read.
    ///
    /// Custom types may implement this method to apply custom transformations to an intrinsic SQL value,
    /// such as transforming a `String` / `TEXT` value to a date.
    ///
    /// The default behaviour returns the original expression without modification.
    ///
    static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression)
}

extension XLEncodable {
    
    public static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        builder(&context)
    }
}


///
/// Defines an `XLEncodable` type that represents a list of values.
///
/// Used for expressions which usually contain a list of sub-expressions, such as `OrderBy` and
/// `GroupBy` clauses.
///
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


///
/// Defines an encoding of an SQL statement.
///
/// The encoding is a  representation of an SQL statement which can be executed by a specific database.
///
public struct XLEncoding {
    
    ///
    /// Opaque representation of an SQL statement which can be executed by the database.
    ///
    public let sql: String
    
    ///
    /// A set of names of database tables which are referenced in the SQL statement.
    ///
    /// Used by SwiftQL to determine when a table in a select statement has been modified by an insert,
    /// update, or delete statement.
    ///
    public let entities: Set<String>
}


///
/// Defines encoder which is used to produce an encoding of an SQL statement.
///
public protocol XLEncoder {
    
    ///
    /// Creates an SQL encoding of an encodable statement.
    ///
    /// Custom database encoders must implement this method and pass a suitable
    /// `XLBuilder` to the encodable expression. The builder implementation should produce a
    /// `XLEncoding`.
    ///
    func makeSQL(_ expression: any XLEncodable) -> XLEncoding
}


///
/// Encodes SwiftQL statements into SQL that can be executed by SQLite.
///
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


///
/// Encodes Swift values into a string representation in an SQL statement.
///
public protocol XLFormatter {
    
    ///
    /// Formats a `nil` literal into an SQL sub-expression.
    ///
    func null() -> String
    
    ///
    /// Formats an `Int` literal into an SQL sub-expression.
    ///
    func integer(_ value: Int) -> String
    
    ///
    /// Formats a `Double` literal into an SQL sub-expression.
    ///
    func real(_ value: Double) -> String
    
    ///
    /// Formats a `String` literal into an SQL sub-expression.
    ///
    func text(_ value: String) -> String
    
    ///
    /// Formats a `Data` literal into an SQL sub-expression.
    ///
    func blob(_ value: Data) -> String
    
    ///
    /// Formats a name, such as of a table or column, into an SQL sub-expression.
    ///
    func name(_ value: String) -> String
    
    ///
    /// Formats a qualified name, such as a table and column, into an SQL sub-expression. Each
    /// component of the name is provided as an entry in an array.
    ///
    func scopedName(_ values: [String]) -> String
    
    ///
    /// Formats a named variable into an SQL sub-expression.
    ///
    func namedBinding(_ named: String) -> String
    
    ///
    /// Formats an index variable into an SQL sub-expression.
    ///
    func indexedBinding(_ index: Int) -> String
}


///
/// Formats SwiftQL literals into SQL sub-expressions for use with SQLite.
///
public struct XLiteFormatter: XLFormatter {
    
    ///
    /// Defines the escape sequence used to encode identifiers.
    ///
    /// SQLite provides compatibility for different conventions for escaping names of identifiers. SwiftQL
    /// uses the backtick \` character for SQL statements by default.
    ///
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


///
/// Encodes SwiftQL expressions into SQL.
///
/// The `XLBuilder` is typically used by an associated `XLEncoder` to consutruct SQL statements for
/// a specific dialect of SQL.
///
public protocol XLBuilder {
    
    ///
    /// Constructs an expression.
    ///
    typealias Builder = (inout XLBuilder) -> Void
    
    ///
    /// Constructs a list of expressions.
    ///
    typealias ListBuilder = (inout XLListBuilder) -> Void
    
    ///
    /// Constructs a common table expression.
    ///
    typealias CommonTablesBuilder = (inout XLCommonTablesBuilder) -> Void
    
    ///
    /// Constructs a list of column definitions.
    ///
    typealias ColumnsBuilder = (inout XLColumnDefinitionsBuilder) -> Void
    
    ///
    /// Creates an SQL expression from the current state.
    ///
    func build() -> String
    
    ///
    /// Creates a set of names of tables referenced in the SQL expression.
    ///
    func entities() -> Set<String>
    
    ///
    /// Adds a name of an entity (table or column).
    ///
    /// - Parameter name: Entity name.
    ///
    mutating func entity(_ name: String)
    
    ///
    /// Adds a `nil` literal.
    ///
    mutating func null()
    
    ///
    /// Adds an `Int` literal.
    ///
    /// - Parameter value: Int literal.
    ///
    mutating func integer(_ value: Int)
    
    ///
    /// Adds a `Double` literal.
    ///
    /// - Parameter value: Double literal.
    ///
    mutating func real(_ value: Double)
    
    ///
    /// Adds a `String` literal.
    ///
    /// - Parameter value: String literal.
    ///
    mutating func text(_ value: String)
    
    ///
    /// Adds a `Data` literal.
    ///
    /// - Parameter value: Data literal.
    ///
    mutating func blob(_ value: Data)
    
    ///
    /// Adds a name literal, such as the name of a table or column.
    ///
    /// - Parameter value: Name literal.
    ///
    mutating func name(_ value: XLName)
    
    ///
    /// Adds a qualified name, such as the name of a column on a specific table..
    ///
    /// - Parameter value: Qualified name.
    ///
    mutating func qualifiedName(_ value: XLQualifiedName)
    
    ///
    /// Adds a named variable binding.
    ///
    /// - Parameter name: Name of the parameter.
    ///
    mutating func namedBinding(_ name: XLName)
    
    ///
    /// Adds an indexed variable binding.
    ///
    /// - Parameter index: Ordinal index of the parameter.
    ///
    mutating func indexedBinding(_ index: Int)
    
    ///
    /// Adds a list. The list is constructed using a specialised `XLListBuilder`.
    ///
    /// - Parameter separator: Character sequence used to delimit list items.
    /// - Parameter items: A `ListBuilder` closure which is used to provide the items for the list.
    ///
    mutating func list(separator: String, items: ListBuilder)
    
    ///
    /// Adds a nested sub-expression.
    ///
    /// - Parameter beginsWith: Prefix applied before the nested sub-expression, such as a leading expression or opening parenthesis.
    /// - Parameter endsWith: Suffix applied after the nested sub-expression, such as a trailing expression or closing parenthesis.
    /// - Parameter separator: Character sequence used to delimit sub-expressions within the sub-expression.
    /// - Parameter contents: Sub-expression applied between the `beginsWith` and `endsWith` expressions.
    ///
    mutating func block(beginsWith prefix: String, endsWith suffix: String, separator: XLSeparator, contents: Builder)
    
    ///
    /// Adds a sub-expression with a leading prefix.
    ///
    /// - Parameter operator: Prefix applied before the sub-expression
    /// - Parameter expression: Sub-expression applied after the prefix.
    ///
    /// This differs from <doc:unaryOperator> in that the prefix is applied as a separate sub-expression
    /// separated by the standard delimiter (usually a space).
    ///
    mutating func unaryPrefix(_ operator: String, expression: Builder)
    
    ///
    /// Adds a sub-expression with a trailing suffix.
    ///
    /// - Parameter operator: Suffix applied after the sub-expression.
    /// - Parameter expression: Sub-expression applied before the suffix.
    ///
    mutating func unarySuffix(_ operator: String, expression: Builder)
    
    ///
    /// Adds a sub-expression with a leading operator.
    ///
    /// - Parameter operator: Leading operator applied before the expression.
    /// - Parameter expression: Sub-expression applied after the operator.
    ///
    /// This differs from <doc:unaryPrefix> in that the operator is applied immediately before
    /// the expression.
    ///
    mutating func unaryOperator(_ operator: String, expression: Builder)
    
    ///
    /// Adds two sub-expressions separated by an operator.
    ///
    /// - Parameter operator: Operator applied between the left and right expressions.
    /// - Parameter left: Expression on the left of the operator.
    /// - Parameter right: Expression on the right of the operator.
    ///
    mutating func binaryOperator(_ operator: String, left: Builder, right: Builder)
    
    ///
    /// Adds a `BETWEEN` sub-expression.
    ///
    /// - Parameter term: Sub-expression referenced in the between statement.
    /// - Parameter minimum: Minimum value for the `term`.
    /// - Parameter maximum: Maximum value for the `term`.
    ///
    mutating func between(term: Builder, minimum: Builder, maximum: Builder)
    
    ///
    /// Adds a `CAST` sub-expression.
    ///
    /// - Parameter type: Name of the type to cast to.
    /// - Parameter expression: Sub-expression to cast.
    ///
    mutating func cast(type: String, expression: Builder)
    
    ///
    /// Adds a non-aggregate function.
    ///
    /// - Parameter name: Name of the function.
    /// - Parameter parameters: List of parameters passed to the function.
    ///
    mutating func simpleFunction(name: String, parameters: ListBuilder)
    
    ///
    /// Adds an aggregate function.
    ///
    /// - Parameter name: Name of the function.
    /// - Parameter distinct: Add a DISTINCT clause to the function if `true`.
    /// - Parameter parameters: List of parameters passed to the function.
    ///
    /// An aggregate function differs from a non-aggregate function in that it allows for the use of a
    /// DISTINCT clause.
    ///
    mutating func aggregateFunction(name: String, distinct: Bool, parameters: ListBuilder)
    
    ///
    /// Adds an alias (`AS`) sub-expression.
    ///
    /// - Parameter name: Alias.
    /// - Parameter expression: Expression to alias, usually the name of a table or column.
    ///
    mutating func alias(_ name: XLName, expression: Builder)
    
    ///
    /// Adds common table sub-expressions.
    ///
    /// - Parameter builder: Constructs one or more common tables.
    ///
    mutating func commonTables(builder: CommonTablesBuilder)
    
    ///
    /// Adds a create table sub-expression.
    ///
    /// - Parameter name: Qualified name of the table.
    ///
    mutating func createTable(_ name: XLQualifiedName)
    
    ///
    /// Adds a create table sub-expressions.
    ///
    /// - Parameter name: Qualified name of the table.
    /// - Parameter builder: Constructs the list of columns defined on the table.
    ///
    mutating func createTable(_ name: XLQualifiedName, builder: ColumnsBuilder)
}

extension XLBuilder {
    
    ///
    /// Convenience method used to add a sub-expression with leading and trailing paranthesis.
    ///
    /// - Parameter contents: Constructs the contents of the sub-expression.
    ///
    public mutating func parenthesis(contents: Builder) {
        block(beginsWith: "(", endsWith: ")", separator: .elided, contents: contents)
    }
}


///
/// Cnstructs a list of sub-expressions.
///
public protocol XLListBuilder {
    
    ///
    /// Constructs a sub-expression.
    ///
    typealias Builder = (inout XLBuilder) -> Void
    
    ///
    /// Creates an SQL expression from the current state.
    ///
    func build() -> String
    
    ///
    /// Creates a set of names of entities referenced in the expressions in the list.
    ///
    func entities() -> Set<String>
    
    ///
    /// Adds an item to the list.
    ///
    /// - Parameter expression: Sub-expression to add to the list.
    ///
    mutating func listItem(expression: Builder) -> Void
}


///
/// Constructs a collection of common table expressions.
///
public protocol XLCommonTablesBuilder {
    
    ///
    /// Constructs a sub-expression.
    ///
    typealias Builder = (inout XLBuilder) -> Void
    
    ///
    /// Constructs an SQL expression from the current state.
    ///
    func build() -> String
    
    ///
    /// Creates a set of entities referenced by the common table expressions.
    ///
    func entities() -> Set<String>
    
    ///
    /// Adds a common table expression.
    ///
    /// - Parameter alias: Name used to refer to the common table expression in the containing SQL statement.
    /// - Parameter expression: Constructs the common table expression.
    ///
    mutating func commonTable(alias: XLName, expression: Builder) -> Void
}


///
/// Constructs a set of column definitions.
///
/// Used to define the set of columns in a `CREATE` expression.
///
public protocol XLColumnDefinitionsBuilder {
    
    ///
    /// Constructs an SQL expression from the current state.
    ///
    func build() -> String
    
    ///
    /// Adds a column.
    ///
    /// - Parameter name: Name of the column.
    /// - Parameter nullable: Indicates whether the column is optional (`true`) or non-optional (`false`).
    ///
    mutating func column(name: XLName, nullable: Bool)
}


///
/// Constructs an SQL expression that can be executed by SQLite.
///
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


///
/// Used by `XLiteBuilder` to construct a list of sub-expressions.
///
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


///
/// Used by `XLiteBuilder` to construct common table expressions.
///
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


///
/// Used by `XLiteBuilder` to construct a set of columns.
///
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
