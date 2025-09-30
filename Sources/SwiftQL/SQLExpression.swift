//
//  XLSyntax.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


#warning("TODO: Implement IN and NOT IN expressions")


public typealias XLCustomType = XLExpression & XLBindable & XLLiteral


// MARK: - Expressions


/// An XL expression. An expression evaluates to a value of a known type.
public protocol XLExpression<T>: XLEncodable {
    associatedtype T
}

extension XLExpression {
    public func writeSQL(context: inout XLBuilder) {
        (T.self as! XLEncodable.Type).unwrapSQL(context: &context, builder: makeSQL)
    }
}


public protocol XLBindingContext {
    mutating func bindNull()
    mutating func bindInteger(value: Int)
    mutating func bindReal(value: Double)
    mutating func bindText(value: String)
    mutating func bindBlob(value: Data)
}


public protocol XLBindable {
    func bind(context: inout XLBindingContext)
}


public protocol XLLiteral: XLBindable {
    typealias MakeExpression = (inout XLBuilder) -> Void
    static func sqlDefault() -> Self
    init(reader: XLColumnReader, at index: Int) throws
    static func wrapSQL(context: inout XLBuilder, builder: MakeExpression)
}

extension XLLiteral {
    public static func wrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        builder(&context)
    }
}


public protocol XLEquatable: XLExpression {
    
}


public protocol XLComparable: XLEquatable {
    
}


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


public protocol XLBindingReference<T>: XLExpression {
    
}


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


public struct XLTableName: XLEncodable, Equatable {
    
    public var name: XLName
    
    public init(name: XLName) {
        self.name = name
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.name(name)
    }
}


public protocol XLQualifiedName: XLEncodable {
    var components: [XLName] { get }
}

extension XLQualifiedName {
    public func makeSQL(context: inout XLBuilder) {
        context.qualifiedName(self)
    }
}


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


public struct XLQualifiedSelectColumnName: XLQualifiedName, Equatable {
    
    public let components: [XLName]
    
    public let column: XLName

    init(column: XLName) {
        self.column = column
        self.components = [column]
    }
}


public enum XLSeparator: String {
    #warning("TODO: Use semantic separator instead of literal (e.g. .list, .tuple)")
    case elided = ""
    case space = " "
    case comma = ", "
    case newline = "\n"
}


// MARK: - Concrete expressions


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


struct XLParenthesis<T>: XLExpression {
    
    private let expression: any XLEncodable
    
    init(expression: any XLEncodable) {
        self.expression = expression
    }
    
    func makeSQL(context: inout XLBuilder) {
        context.parenthesis(contents: expression.makeSQL)
    }
}


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
