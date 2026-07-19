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
    public func writeSQL(context: inout XLBuilder) {
        guard let encodableType = T.self as? any XLEncodable.Type else {
            makeSQL(context: &context)
            return
        }
        encodableType.unwrapSQL(context: &context, builder: makeSQL)
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
/// Custom types must implement an initializer to read an intrinsic value from
/// the database. A default placeholder is needed only when the type is decoded
/// through the legacy result-introspection path.
///
/// Custom types may optionally implement a wrapper to transform values in SQL expressions.
///
public protocol XLLiteral: XLBindable {
    
    ///
    /// Constructs a wrapped expression.
    ///
    typealias MakeExpression = (inout XLBuilder) -> Void
    
    ///
    /// Returns a placeholder for legacy `SQLReader` result introspection.
    ///
    /// Generated static row layouts never call this method. New literal types
    /// that decode exclusively through a static layout can rely on the default
    /// implementation, which stops with a migration diagnostic if a legacy
    /// introspection path reaches it. Existing v1 types should keep an explicit
    /// implementation while they still use legacy result construction.
    ///
    static func sqlDefault() -> Self
    
    ///
    /// Initializes an instance from one database field.
    ///
    /// - Parameter reader: Reads the single field owned by this literal.
    ///
    /// Custom types should use the method for the relevant intrinsic type. The
    /// field reader already owns the correct column index.
    ///
    init(reader: XLFieldReader) throws

    /// Initializes an instance from a database column and separate index.
    ///
    /// This v1 compatibility requirement lets existing literal conformers keep
    /// compiling. New conformers should implement `init(reader:)` with an
    /// ``XLFieldReader``. The default implementations bridge in both directions,
    /// so every conformer must implement at least one of the two initializers.
    init(reader: any XLColumnReader, at index: Int) throws
    
    ///
    /// Wraps occurrences of the type with an expression.
    ///
    /// The default behaviour is to return the expression without modification.
    ///
    /// Custom types may implement this method to wrap occurrences of the type to perform specific
    /// encoding, such as converting a `String` / `TEXT` value into a a date.
    ///
    static func wrapSQL(context: inout XLBuilder, builder: MakeExpression)
}

extension XLLiteral {
    public init(reader: XLFieldReader) throws {
        self = try Self(
            reader: reader.columnReader,
            at: reader.index
        )
    }

    public init(reader: any XLColumnReader, at index: Int) throws {
        self = try Self(
            reader: XLFieldReader(reader: reader, at: index)
        )
    }

    public static func sqlDefault() -> Self {
        let typeName = String(reflecting: Self.self)
        preconditionFailure(
            "\(typeName) does not provide a legacy sqlDefault() placeholder. "
                + "Legacy SQLReader result introspection requires an explicit "
                + "placeholder; construct this result through the macro-generated "
                + "staticRowLayout(using:...) path instead."
        )
    }

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
public struct XLColumnReference<T>: XLExpression {
    
    public var alias: XLName
    
    public var dependency: XLColumnDependency
    
    public init(dependency: XLColumnDependency, as alias: XLName) {
        self.dependency = dependency
        self.alias = alias
    }
    
    public func makeSQL(context: inout XLBuilder) {
        guard let literalType = T.self as? any XLLiteral.Type else {
            context.qualifiedName(dependency.qualifiedName(forColumn: alias))
            return
        }
        literalType.wrapSQL(context: &context) { context in
            context.qualifiedName(dependency.qualifiedName(forColumn: alias))
        }
    }    
}


///
/// Expression that refers to a column in a result, such as the list of columns in a select statement.
///
public struct XLColumnResult<T>: XLExpression {
    
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


/// An expression whose logical result type can be replaced by an explicit
/// storage carrier for static contextual coding.
///
/// Column references opt in so a contextual `Date -> String`, for example,
/// renders the bare SQL column as `String` storage even if another module has
/// supplied a retroactive legacy `Date: XLLiteral` wrapper.
public protocol XLStaticStorageRetypableExpression {
    func staticStorageExpression<Storage>(
        as storageType: Storage.Type
    ) -> any XLExpression<Storage>
}


extension XLColumnReference: XLStaticStorageRetypableExpression {
    public func staticStorageExpression<Storage>(
        as _: Storage.Type
    ) -> any XLExpression<Storage> {
        XLColumnReference<Storage>(dependency: dependency, as: alias)
    }
}


extension XLColumnResult: XLStaticStorageRetypableExpression {
    public func staticStorageExpression<Storage>(
        as _: Storage.Type
    ) -> any XLExpression<Storage> {
        XLColumnResult<Storage>(dependency: dependency, as: alias)
    }
}


/// Source-compatibility bridge used by macro-generated v1 insert/update
/// helpers after column declarations became unconstrained.
///
/// Contextual-only values can now appear in generated table metadata, but
/// they must use a static row layout for encoding. Existing `XLLiteral` /
/// `XLExpression` values retain their original rendering behavior through
/// this wrapper.
public struct XLLegacyDynamicValueExpression<Value>: XLExpression {
    public typealias T = Value

    private let value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func makeSQL(context: inout XLBuilder) {
        guard let expression = value as? any XLEncodable else {
            preconditionFailure(
                "\(String(reflecting: Value.self)) is a contextual-only SQL value. Encode it through XLStaticRowLayout instead of the v1 MetaInsert/MetaUpdate path."
            )
        }
        expression.makeSQL(context: &context)
    }
}


/// Creates the dynamic v1 expression bridge used by generated compatibility
/// APIs. New contextual code should use ``XLStaticSelectField`` instead.
public func _xlLegacyValueExpression<Value>(
    _ value: Value
) -> XLLegacyDynamicValueExpression<Value> {
    XLLegacyDynamicValueExpression(value)
}


///
/// Reference to a variable used in an expression.
///
public protocol XLBindingReference<T>: XLExpression {
    
}


///
/// A variable used in an expression that is referred to by a given name.
///
public struct XLNamedBindingReference<T>: XLBindingReference, Sendable where T: XLLiteral {
    
    /// The placeholder name emitted in SQL.
    public let name: XLName
    
    /// Creates a named binding reference.
    ///
    /// - Parameter name: The placeholder name, without a leading colon.
    public init(name: XLName) {
        self.name = name
    }
    
    public func makeSQL(context: inout XLBuilder) {
        T.wrapSQL(context: &context) { context in
            context.parameter(
                _xlLegacyParameterDeclaration(
                    for: T.self,
                    key: .named(name.rawValue)
                )
            )
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
/// - Use a supported intrinsic type for the `RawValue`.
/// - Conform to the `XLEnum` protocol and declare `T` as `Self`.
/// - When using legacy `SQLReader` result introspection, implement
///   `sqlDefault()` and return any valid enum value. Static row layouts do not
///   require or call that placeholder, and it is never a fallback for database
///   decoding.
///
/// The `XLEnum` protocol provides default implementations for most of the required methods which can
/// be overridden as required. Reading an unknown stored raw value throws ``XLColumnReadError``.
///
public protocol XLEnum: XLLiteral, XLExpression, XLEquatable, XLComparable, RawRepresentable where T == Self, RawValue: XLExpression & XLLiteral & XLEquatable & XLComparable {
    
}

extension XLEnum {
        
    public init(reader: XLFieldReader) throws {
        let rawValue = try RawValue(reader: reader)
        guard let value = Self(rawValue: rawValue) else {
            throw XLColumnReadError(
                index: reader.index,
                expectedType: String(describing: Self.self),
                failure: .invalidValue(actualValue: String(reflecting: rawValue))
            )
        }
        self = value
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

    public init(reader: XLFieldReader) throws {
        if try reader.isNull() {
            self = nil
        }
        else {
            self = try Wrapped(reader: reader)
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
public struct XLName: XLEncodable, ExpressibleByStringLiteral, Equatable, Hashable, Sendable {
    
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
public struct XLSchemaName: XLEncodable, Equatable, Sendable {
    
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
/// A semantic delimiter used to encode SQL expressions.
///
/// Use ``list`` for comma-delimited SQL items and ``tuple`` for adjacent
/// grammar tokens. The literal-named enum cases remain available for source
/// compatibility with existing builders.
///
public enum XLSeparator: String, Sendable {
    case elided = ""
    case space = " "
    case comma = ", "
    case newline = "\n"

    /// Separates adjacent SQL grammar tokens with whitespace.
    public static let tuple: Self = .space

    /// Separates entries in an SQL list with a comma and whitespace.
    public static let list: Self = .comma
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
