//
//  SQLExpression.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


public typealias XLCustomType = XLExpression & XLBindable & XLLiteral


// MARK: - Expressions


///
/// An SQL expression.
///
/// An expression evaluates to a value of a known type defined by the associated type `T`.
///
public protocol XLExpression<T>: XLEncodable {
    associatedtype T
}

extension XLExpression {
    
    ///
    /// Helper method used to encode an expression.
    ///
    /// Automatically unwraps the expression.
    ///
    /// > TODO: Make this internal.
    ///
    public func writeSQL(context: inout XLBuilder) {
        (T.self as! XLEncodable.Type).unwrapSQL(context: &context, builder: makeSQL)
    }
}


///
/// Context used to bind values to expression at runtime.
///
/// Used to pass a variable parameter into a prepared SQL statement at runtime,
///
/// A custom type definition must convert its internal representation into one of the supported intrinsic types
/// then call the relevant `bind` function, in order to pass the value to a prepared statement at runtime.
///
public protocol XLBindingContext {
    mutating func bindNull()
    mutating func bindInteger(value: Int)
    mutating func bindReal(value: Double)
    mutating func bindText(value: String)
    mutating func bindBlob(value: Data)
}


///
/// A type that can be passed to a prepared statement at runtime.
///
/// Bindable types include all intrinsic types and custom types.
///
public protocol XLBindable {
    func bind(context: inout XLBindingContext)
}


///
/// A value stored in the database.
///
/// Custom types must implement an initializer to read an intrinsic value from the database, and provide an
/// appropriate default placeholder value.
///
/// Custom types may optionally implement a wrapper to transform values in SQL expressions.
///
public protocol XLLiteral: XLBindable {
    
    ///
    /// Constructs a wrapped expression.
    ///
    typealias MakeExpression = (inout XLBuilder) -> Void
    
    ///
    /// - Returns: Any valid instance of the implementation. The default value is used internally by SwiftQL when creating prepared statements.
    ///
    static func sqlDefault() -> Self
    
    ///
    /// Initializes an instance from a database column.
    ///
    /// - Parameter reader: Reads values of columns.
    /// - Parameter index: Index of the column which should be read.
    ///
    /// Custom types should read the column at the provided index using the method for the relevant intrinsic type.
    ///
    init(reader: XLColumnReader, at index: Int) throws
    
    ///
    /// Wraps occurances of the type with an expression.
    ///
    /// The default behaviour is to return the expression without modification.
    ///
    /// Custom types may implement this method to wrap occurances of the type to perform specific
    /// encoding, such as converting a `String` / `TEXT` value into a a date.
    ///
    static func wrapSQL(context: inout XLBuilder, builder: MakeExpression)
}

extension XLLiteral {
    public static func wrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        builder(&context)
    }
}


///
/// A type of a value which can be compared to another value of the same type for equivalence.
///
public protocol XLEquatable: XLExpression {
    
}


///
/// A type of a value value which can be compared to another value of the same type for ordinality (greater
/// than, less than, greater than or equal to, less than or equal to).
///
public protocol XLComparable: XLEquatable {
    
}


///
/// Expression that refers to a table column.
///
public struct XLColumnReference<T>: XLExpression where T: XLLiteral {
    
    public var alias: XLName
    
    public var dependency: XLColumnDependency
    
    public init(dependency: XLColumnDependency, as alias: XLName) {
        self.dependency = dependency
        self.alias = alias
    }
    
    public func makeSQL(context: inout XLBuilder) {
        T.wrapSQL(context: &context) { context in
            context.qualifiedName(dependency.qualifiedName(forColumn: alias))
        }
    }    
}


///
/// Expression that refers to a column in a result, such as the list of columns in a select statement.
///
public struct XLColumnResult<T>: XLExpression where T: XLLiteral {
    
    public var alias: XLName
    
    public var dependency: XLColumnDependency
    
    public init(dependency: XLColumnDependency, as alias: XLName) {
        self.dependency = dependency
        self.alias = alias
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.qualifiedName(dependency.qualifiedName(forColumn: alias))
    }
}


///
/// Reference to a variable used in an expression.
///
public protocol XLBindingReference<T>: XLExpression {
    
}


///
/// A variable used in an expression that is referred to by a given name.
///
public struct XLNamedBindingReference<T>: XLBindingReference where T: XLLiteral {
    
    public let name: XLName
    
    public init(name: XLName) {
        self.name = name
    }
    
    public func makeSQL(context: inout XLBuilder) {
        T.wrapSQL(context: &context) { context in
            context.namedBinding(name)
        }
    }
}


///
/// A function that is called in an expression.
///
public struct XLFunction<T>: XLExpression where T: XLLiteral {
    
    private let name: String
    
    private let distinct: Bool
    
    private let parameters: [any XLExpression]
    
    public init(name: String, distinct: Bool = false, parameters: any XLExpression...) {
        self.name = name
        self.distinct = distinct
        self.parameters = parameters
    }

    public init(name: String, distinct: Bool = false, parameters: [any XLExpression]) {
        self.name = name
        self.distinct = distinct
        self.parameters = parameters
    }

    public func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: name) { context in
            for i in 0 ..< parameters.count {
                let parameter = parameters[i]
                if distinct && i == 0 {
                    context.listItem { context in
                        context.unaryPrefix("DISTINCT", expression: parameter.makeSQL)
                    }
                }
                else {
                    context.listItem(expression: parameter.makeSQL)
                }
            }
        }
    }
}


///
/// An enum that is used as a column on an `SQLTable` or `SQLResult`.
///
/// To use an enum for a column the enum must adhere to the following conditions:
/// - Use an intrinsic type for the `RawValue`,
/// - Conform to the `XLEnum` protocol.
/// - Implement the `sqlDefault` static method and return any valid enum value.
///
/// The `XLEnum` protocol provides default implementations for most of the required methods which can
/// be overriden as required.
///
public protocol XLEnum: XLLiteral, XLExpression, XLEquatable, XLComparable, RawRepresentable where T == Self, RawValue: XLExpression & XLLiteral & XLEquatable & XLComparable {
    
}

extension XLEnum {
        
    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = try RawValue(reader: reader, at: index)
        self = Self(rawValue: rawValue) ?? Self.sqlDefault()
    }
    
    public func bind(context: inout XLBindingContext) {
        rawValue.bind(context: &context)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        RawValue.wrapSQL(context: &context) { context in
            rawValue.makeSQL(context: &context)
        }
    }
}


extension XLExpression {
    
    public func toRawValue() -> some XLExpression<Int> where T: XLEnum, T.RawValue == Int {
        XLTypeAffinityExpression(expression: self)
    }
    
    public func toRawValue() -> some XLExpression<Double> where T: XLEnum, T.RawValue == Double {
        XLTypeAffinityExpression(expression: self)
    }
    
    public func toRawValue() -> some XLExpression<String> where T: XLEnum, T.RawValue == String {
        XLTypeAffinityExpression(expression: self)
    }
}


extension Optional {
    
    public typealias T = Optional<Wrapped>
}

extension Optional: XLEncodable where Wrapped: XLEncodable {

    public func makeSQL(context: inout XLBuilder) {
        switch self {
        case .none:
            context.null()
        case let .some(wrapped):
            wrapped.makeSQL(context: &context)
        }
    }
    
    public static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        Wrapped.unwrapSQL(context: &context, builder: builder)
    }
}

extension Optional: XLExpression where Wrapped: XLExpression {
    
}

extension Optional: XLBindable where Wrapped: XLBindable {
    
    public func bind(context: inout XLBindingContext) {
        if let self {
            self.bind(context: &context)
        }
        else {
            context.bindNull()
        }
    }
}

extension Optional: XLLiteral where Wrapped: XLLiteral {

    public static func sqlDefault() -> Optional<Wrapped> {
        Wrapped.sqlDefault()
    }

    public init(reader: XLColumnReader, at index: Int) throws {
        if reader.isNull(at: index) {
            self = nil
        }
        else {
            self = try Wrapped(reader: reader, at: index)
        }
    }
    
    public static func wrapSQL(context: inout XLBuilder, builder: (inout XLBuilder) -> Void) {
        Wrapped.wrapSQL(context: &context, builder: builder)
    }
}


extension XLExpression {
    
    ///
    /// Cast a non-null expression to an optional value expression. 
    ///
    public func toNullable() -> some XLExpression<Optional<T>> {
        XLTypeAffinityExpression(expression: self)
    }
}


public protocol XLBoolean {
    
}

extension Bool: XLBoolean {
    
}

extension Optional: XLBoolean where Wrapped == Bool {
    
}


// MARK: - Names


///
/// A name used in a SwiftQL expression.
///
/// `XLName` is simply a wrapper for name references.
///
public struct XLName: XLEncodable, ExpressibleByStringLiteral, Equatable, Hashable {
    
    public var rawValue: String
    
    public init(_ value: StringLiteralType) {
        self.rawValue = value
    }
    
    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.name(self)
    }
}


///
/// A name of a schema used in a SwiftQL expression.
///
public struct XLSchemaName: XLEncodable, Equatable {
    
    public static let main = XLSchemaName(name: "main")
    
    public var name: XLName
    
    public init(name: XLName) {
        self.name = name
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.name(name)
    }
}


///
/// A name of a table used in a SwiftQL expression.
///
public struct XLTableName: XLEncodable, Equatable {
    
    public var name: XLName
    
    public init(name: XLName) {
        self.name = name
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.name(name)
    }
}


///
/// A qualified name used in a SwiftQL expression, such as the name of a column on a table.
///
public protocol XLQualifiedName: XLEncodable {
    var components: [XLName] { get }
}

extension XLQualifiedName {
    public func makeSQL(context: inout XLBuilder) {
        context.qualifiedName(self)
    }
}


///
/// A qualified name of a table.
///
public struct XLQualifiedTableName: XLQualifiedName, Equatable {
    
    public let components: [XLName]
    
    public let schema: XLSchemaName?
    
    public let name: XLName
    
    public init<T>(schema: XLSchemaName? = nil, table: T.Type) {
        self.init(schema: schema, name: XLName(stringLiteral: String(describing: T.self)))
    }
    
    public init(schema: XLSchemaName? = nil, name: XLName) {
        self.schema = schema
        self.name = name
        if let schema {
            components = [schema.name, name]
        }
        else {
            components = [name]
        }
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.qualifiedName(self)
        context.entity(name.rawValue)
    }
}


///
/// A qualified name of a table column.
///
public struct XLQualifiedTableAliasColumnName: XLQualifiedName, Equatable {
    
    public let components: [XLName]
    
    public let table: XLName
    
    public let column: XLName
    
    init(table: XLName, column: XLName) {
        self.table = table
        self.column = column
        self.components = [table, column]
    }
}


///
/// A qualified name of a column in a result set in a select statement.
///
public struct XLQualifiedSelectColumnName: XLQualifiedName, Equatable {
    
    public let components: [XLName]
    
    public let column: XLName

    init(column: XLName) {
        self.column = column
        self.components = [column]
    }
}


///
/// Delimiter used to encode SQLite expressions.
///
public enum XLSeparator: String {
    case elided = ""
    case space = " "
    case comma = ", "
    case newline = "\n"
}


// MARK: - Concrete expressions


///
/// An expression composed of multiple sub-expressions.
///
struct XLCompoundExpression<T>: XLExpression {
    
    private var separator: XLSeparator
    
    private var expressions: [any XLExpression]
    
    public init(separator: XLSeparator, expressions: [any XLExpression]) {
        self.separator = separator
        self.expressions = expressions
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.list(separator: separator.rawValue) { listBuilder in
            for expression in expressions {
                listBuilder.listItem { builder in
                    expression.makeSQL(context: &builder)
                }
            }
        }
    }
}


///
/// An expression enclosing a sub-expression with parenthesis.
///
struct XLParenthesis<T>: XLExpression {
    
    private let expression: any XLEncodable
    
    init(expression: any XLEncodable) {
        self.expression = expression
    }
    
    func makeSQL(context: inout XLBuilder) {
        context.parenthesis(contents: expression.makeSQL)
    }
}


///
/// An expression representing an SQL subquery.
///
struct XLSubquery<Wrapped>: XLExpression where Wrapped: XLLiteral {
    
    typealias T = Optional<Wrapped>
    
    private let statement: any XLEncodable

    init(statement: any XLQueryStatement<Wrapped>) {
        self.statement = statement
    }
    
    func makeSQL(context: inout XLBuilder) {
        context.parenthesis(contents: statement.makeSQL)
    }
}
