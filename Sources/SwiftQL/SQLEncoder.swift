//
//  SQLEncoder.swift
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
    /// The `unwrapSQL` method is applied to every occurrence of the custom type in an SQL expression
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

    var separator: XLSeparator
    
    var expressions: [any XLEncodable]
    
    init(separator: XLSeparator, expressions: [any XLEncodable]) {
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
    /// This metadata is available to database adapters and diagnostics. GRDB-backed live queries derive
    /// their observed database region from the prepared query instead of this set.
    ///
    public let entities: Set<String>

    /// Dialect identity and syntax capabilities required by this SQL.
    public let dialectRequirement: XLDialectRequirement

    /// The immutable static parameter metadata captured while rendering SQL.
    public let parameterLayout: XLParameterLayout

    /// The first deterministic conflict encountered while capturing parameter
    /// metadata. Legacy nonthrowing encoders retain this error so an execution
    /// boundary can reject the statement before preparing it.
    public let parameterLayoutError: XLInvocationBindingError?

    /// The first deterministic value-rendering failure encountered while
    /// building `sql`. The nonthrowing v1 encoder retains this error so every
    /// validated or executable boundary can reject the statement before
    /// SQLite parses partial SQL.
    public let valueEncodingError: XLSQLValueEncodingError?

    public init(
        sql: String,
        entities: Set<String>,
        dialectRequirement: XLDialectRequirement,
        parameterLayout: XLParameterLayout = .empty,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil
    ) {
        self.sql = sql
        self.entities = entities
        self.dialectRequirement = dialectRequirement
        self.parameterLayout = parameterLayout
        self.parameterLayoutError = parameterLayoutError
        self.valueEncodingError = valueEncodingError
    }
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

    /// Records a value-rendering failure without emitting an invalid SQL
    /// token. Builders that predate fallible rendering remain source
    /// compatible through the default implementation.
    mutating func valueEncodingFailed(_ error: XLSQLValueEncodingError)
    
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

    /// Adds a variable binding with immutable static parameter metadata.
    ///
    /// Builders that do not capture parameter layouts remain source-compatible:
    /// the default implementation renders the placeholder identified by
    /// `slot.key`.
    mutating func parameter(_ slot: XLParameterSlot)

    /// Adds a parameter declaration whose deterministic logical index is
    /// assigned from its first occurrence in the rendered statement.
    mutating func parameter(_ declaration: XLParameterDeclaration)
    
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
    /// - Parameter prefix: Prefix applied before the nested sub-expression, such as a leading expression or opening parenthesis.
    /// - Parameter suffix: Suffix applied after the nested sub-expression, such as a trailing expression or closing parenthesis.
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
    /// This differs from `unaryOperator` in that the prefix is applied as a separate sub-expression
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
    /// This differs from `unaryPrefix` in that the operator is applied immediately before
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

    /// Adds a list whose delimiter communicates its SQL grammar role.
    ///
    /// The existing string-based protocol requirement remains the compatibility
    /// seam for external builders. This overload maps semantic separators onto
    /// that established spelling.
    public mutating func list(
        separator: XLSeparator,
        items: ListBuilder
    ) {
        list(separator: separator.rawValue, items: items)
    }

    public mutating func valueEncodingFailed(
        _ error: XLSQLValueEncodingError
    ) {}

    public mutating func parameter(_ slot: XLParameterSlot) {
        switch slot.key {
        case .named(let name):
            namedBinding(XLName(name))
        case .indexed(let index):
            indexedBinding(index)
        }
    }

    public mutating func parameter(_ declaration: XLParameterDeclaration) {
        switch declaration.key {
        case .named(let name):
            namedBinding(XLName(name))
        case .indexed(let index):
            indexedBinding(index)
        }
    }

    public mutating func between(
        term: Builder,
        minimum: Builder,
        maximum: Builder
    ) {
        binaryOperator(
            "BETWEEN",
            left: term,
            right: { context in
                context.binaryOperator(
                    "AND",
                    left: minimum,
                    right: maximum
                )
            }
        )
    }
    
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

    ///
    /// Adds a common table expression with an optional `MATERIALIZED` /
    /// `NOT MATERIALIZED` hint.
    ///
    /// - Parameter alias: Name used to refer to the common table expression.
    /// - Parameter materialization: The materialization hint, or `.unspecified`.
    /// - Parameter expression: Constructs the common table expression.
    ///
    /// This is a protocol requirement so that dynamic dispatch reaches a
    /// conforming builder's override; the default implementation ignores the
    /// hint for builders that predate materialization support.
    ///
    mutating func commonTable(
        alias: XLName,
        materialization: XLCommonTableMaterialization,
        columns: [XLName],
        expression: Builder
    ) -> Void
}


extension XLCommonTablesBuilder {

    ///
    /// Default implementation for builders that predate materialization / column-list
    /// support: ignores both and renders the plain `alias AS (...)` form.
    ///
    public mutating func commonTable(
        alias: XLName,
        materialization: XLCommonTableMaterialization,
        columns: [XLName],
        expression: Builder
    ) {
        commonTable(alias: alias, expression: expression)
    }
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
