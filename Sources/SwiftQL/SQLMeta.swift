//
//  SQLMeta.swift
//
//
//  Created by Luke Van In on 2023/08/07.
//

import Foundation


// MARK: - Database


public protocol XLDatabaseMetadata {
    func schema() -> XLSchemaName
}


public class XLDatabaseMetadataObject: XLDatabaseMetadata {
    
    private let _schema: XLSchemaName
    
    init(schema: XLSchemaName = .main) {
        self._schema = schema
    }
    
    public func schema() -> XLSchemaName {
        _schema
    }
    
}


// MARK: - Column reading


///
/// An error encountered while reading a typed value from a database result or
/// custom-function argument.
///
public struct XLColumnReadError: Error, Equatable, LocalizedError, CustomStringConvertible, Sendable {

    ///
    /// The reason a value could not be read.
    ///
    public enum Failure: Equatable, Sendable {
        /// The requested index was outside the available values.
        case indexOutOfBounds(valueCount: Int)

        /// A non-optional read encountered SQL `NULL`.
        case nullValue

        /// The SQLite storage class could not be converted to the requested type.
        case typeMismatch(actualType: String)

        /// The stored value could not be represented by the requested logical type.
        case invalidValue(actualValue: String)
    }

    /// The zero-based column or argument index.
    public let index: Int

    /// The requested Swift type, when the read requested a typed value.
    public let expectedType: String?

    /// The reason the read failed.
    public let failure: Failure

    /// Creates a structured column-read error.
    ///
    /// - Parameters:
    ///   - index: The zero-based column or argument index.
    ///   - expectedType: The requested Swift type, if any.
    ///   - failure: The reason the read failed.
    public init(index: Int, expectedType: String?, failure: Failure) {
        self.index = index
        self.expectedType = expectedType
        self.failure = failure
    }

    public var errorDescription: String? {
        let location = "value at index \(index)"
        switch failure {
        case .indexOutOfBounds(let valueCount):
            return "Cannot read \(location): index is outside a result containing \(valueCount) values."
        case .nullValue:
            return "Cannot read NULL \(location) as \(expectedType ?? "a non-optional value")."
        case .typeMismatch(let actualType):
            return "Cannot read \(actualType) \(location) as \(expectedType ?? "the requested type")."
        case .invalidValue(let actualValue):
            return "Cannot decode \(actualValue) \(location) as \(expectedType ?? "the requested type")."
        }
    }

    public var description: String {
        errorDescription ?? "Unable to read database value at index \(index)."
    }
}


///
/// Reads the value for a column for a row returned from a select query.
///
/// Used when reading results of a query returned by SQLite.
///
/// Readers use SQLite storage classes consistently for query results and
/// custom-function arguments. Integer reads accept INTEGER and representable
/// REAL values; real reads accept INTEGER and REAL; text reads accept TEXT and
/// UTF-8 BLOB; and BLOB reads accept BLOB and the UTF-8 bytes of TEXT. Other
/// storage-class conversions throw ``XLColumnReadError``.
///
public protocol XLColumnReader {
    
    ///
    /// Determines if the value for a column at a given index contains a NULL value.
    ///
    /// - Parameter index: Index of the column to examine.
    ///
    /// - Returns: `true` if the column value is NULL.
    /// - Throws: ``XLColumnReadError`` if `index` is outside the available values.
    ///
    func isNull(at index: Int) throws -> Bool
    
    ///
    /// Reads an integer value for a column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Integer value for the column.
    /// - Throws: ``XLColumnReadError`` if the value cannot be read as an integer.
    ///
    func readInteger(at index: Int) throws -> Int
    
    ///
    /// Reads a real number for a column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Floating point value for the column.
    /// - Throws: ``XLColumnReadError`` if the value cannot be read as a real number.
    ///
    func readReal(at index: Int) throws -> Double
    
    ///
    /// Reads a text value for the column at a given index
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: String value for the column.
    /// - Throws: ``XLColumnReadError`` if the value cannot be read as text.
    ///
    func readText(at index: Int) throws -> String
    
    ///
    /// Reads a BLOB value for the column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Data value for the column.
    /// - Throws: ``XLColumnReadError`` if the value cannot be read as a BLOB.
    ///
    func readBlob(at index: Int) throws -> Data
}


/// Reads one field from a database result or custom-function argument.
///
/// A field reader binds a column reader to one zero-based index. Literal
/// decoders therefore receive only the field they own and cannot accidentally
/// read a neighboring column by carrying or modifying a separate index.
public struct XLFieldReader {

    /// The zero-based index bound to this field.
    public let index: Int

    let columnReader: any XLColumnReader

    /// Creates a reader for one field in a column-oriented value source.
    ///
    /// - Parameters:
    ///   - reader: The underlying column-oriented value source.
    ///   - index: The zero-based index this field reader owns.
    public init(reader: any XLColumnReader, at index: Int) {
        self.columnReader = reader
        self.index = index
    }

    /// Returns whether this field contains SQL `NULL`.
    public func isNull() throws -> Bool {
        try columnReader.isNull(at: index)
    }

    /// Reads this field as an integer.
    public func readInteger() throws -> Int {
        try columnReader.readInteger(at: index)
    }

    /// Reads this field as a real number.
    public func readReal() throws -> Double {
        try columnReader.readReal(at: index)
    }

    /// Reads this field as text.
    public func readText() throws -> String {
        try columnReader.readText(at: index)
    }

    /// Reads this field as a BLOB.
    public func readBlob() throws -> Data {
        try columnReader.readBlob(at: index)
    }
}


///
/// Reads the value for columns in rows returned by a select query statement.
///
/// A database-provided row reader is borrowed for the duration of one
/// ``XLRowReadable/readRow(reader:)`` call. Do not retain it or capture it in an
/// escaping closure.
///
public protocol XLRowReader {
    
    ///
    /// Reads and returns the value for the current column.
    ///
    /// Columns are read sequentially in order starting at the first column in the result set. This method
    /// should be called multiple times, to read each column in sequence.
    ///
    func column<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T where T: XLLiteral

    /// Reads a value through the static-row compatibility seam.
    ///
    /// The default implementation preserves existing `XLRowReader`
    /// conformances by reopening legacy `XLLiteral` types through `column`.
    /// Contextual-only types fail with a structured migration diagnostic;
    /// generated static layouts decode those types from `dialectValue`
    /// instead.
    func staticColumn<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T

    /// Reads one raw dialect value for a statically described row field.
    ///
    /// Legacy row readers may rely on the default implementation. Database
    /// adapters that support static layouts expose raw values through
    /// ``XLStaticColumnReader`` instead of fabricating a Swift placeholder.
    func dialectValue<Dialect>(
        at index: Int,
        using dialect: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect
}


extension XLRowReader {
    public func staticColumn<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T {
        guard let literalType = T.self as? any XLLiteral.Type else {
            throw XLStaticRowReadError.staticLayoutRequired(
                valueType: String(reflecting: T.self),
                alias: alias.rawValue
            )
        }
        return try _xlReadLegacyStaticColumn(
            literalType,
            expression: expression,
            alias: alias,
            reader: self
        )
    }

    public func dialectValue<Dialect>(
        at index: Int,
        using dialect: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        throw XLStaticRowReadError.rawDialectValuesUnavailable(
            index: index,
            dialect: dialect.descriptor.identity,
            readerType: String(reflecting: type(of: self))
        )
    }
}


/// A column transport that can expose the dialect-owned value required by a
/// static row layout.
public protocol XLStaticColumnReader: XLColumnReader {
    func dialectValue<Dialect>(
        at index: Int,
        using dialect: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect
}


/// Failures at the static row-reading compatibility boundary.
public enum XLStaticRowReadError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case staticLayoutRequired(valueType: String, alias: String)
    case rawDialectValuesUnavailable(
        index: Int,
        dialect: XLDialectIdentifier,
        readerType: String
    )
    case dialectValueTypeMismatch(
        index: Int,
        expected: String,
        actual: String
    )

    public var errorDescription: String? {
        switch self {
        case .staticLayoutRequired(let valueType, let alias):
            return "Property/result slot '\(alias)' has contextual Swift type \(valueType); construct it through a static row layout instead of the legacy SQLReader/sqlDefault path."
        case .rawDialectValuesUnavailable(let index, let dialect, let readerType):
            return "Static result slot at index \(index) requires a raw \(dialect) value, but row reader \(readerType) does not expose dialect values."
        case .dialectValueTypeMismatch(let index, let expected, let actual):
            return "Static result slot at index \(index) expected raw value type \(expected), but the column transport exposes \(actual)."
        }
    }
}


///
/// Introspects a query expression to determine the columns that are used.
///
final class XLColumnsDefinitionRowReader: XLRowReader, XLEncodable {
    
    private var expressions: [any XLEncodable] = []
    private var names: [XLName] = []
    
    func column<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) -> T where T: XLLiteral {
        names.append(alias)
        if expression is any XLQueryStatement {
            expressions.append(XLParenthesis<T>(expression: expression))
        }
        else {
            expressions.append(expression)
        }
        return T.sqlDefault()
    }
    
    func makeSQL(context: inout XLBuilder) {
        context.list(separator: .list) { listBuilder in
            for (name, expression) in zip(names, expressions) {
                listBuilder.listItem { builder in
                    builder.alias(name, expression: expression.makeSQL)
                }
            }
        }
    }
}


/// Reads the columns for one row returned by a select query statement.
///
/// The value stores only a pointer to state borrowed from ``withReader(_:body:)``.
/// Keeping the representation pointer-sized lets the `XLRowReader` existential
/// carry it inline instead of allocating the previous reader class.
struct XLColumnValuesRowReader<Output>: XLRowReader {

    private struct State {
        var count: Int = 0
        let reader: any XLColumnReader
    }

    private let state: UnsafeMutablePointer<State>

    private init(state: UnsafeMutablePointer<State>) {
        self.state = state
    }

    /// Borrows sequential row-reading state for one synchronous operation.
    ///
    /// `body` must not let the supplied reader escape. The pointer remains
    /// valid only until `body` returns or throws.
    @inline(__always)
    static func withReader<Result>(
        _ reader: any XLColumnReader,
        body: (Self) throws -> Result
    ) rethrows -> Result {
        var state = State(reader: reader)
        return try withUnsafeMutablePointer(to: &state) { state in
            try body(Self(state: state))
        }
    }
    
    ///
    /// Reads the value of the current column from the row, then advances the state to the next column.
    ///
    func column<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T where T: XLLiteral {
        try readValue()
    }

    private func readValue<T>() throws -> T where T: XLLiteral {
        let index = state.pointee.count
        defer {
            state.pointee.count += 1
        }
        return try T.init(
            reader: XLFieldReader(
                reader: state.pointee.reader,
                at: index
            )
        )
    }

    func dialectValue<Dialect>(
        at index: Int,
        using dialect: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        guard let staticReader = state.pointee.reader as? any XLStaticColumnReader else {
            throw XLStaticRowReadError.rawDialectValuesUnavailable(
                index: index,
                dialect: dialect.descriptor.identity,
                readerType: String(
                    reflecting: type(of: state.pointee.reader as Any)
                )
            )
        }
        return try staticReader.dialectValue(at: index, using: dialect)
    }

}


private func _xlReadLegacyStaticColumn<Literal, Value>(
    _ literalType: Literal.Type,
    expression: any XLExpression<Value>,
    alias: XLName,
    reader: any XLRowReader
) throws -> Value where Literal: XLLiteral {
    guard let retyped = expression as? any XLExpression<Literal> else {
        preconditionFailure(
            "Reopened literal expression type \(String(reflecting: Literal.self)) does not match \(String(reflecting: Value.self))."
        )
    }
    let literal = try reader.column(retyped, alias: alias)
    guard let value = literal as? Value else {
        preconditionFailure(
            "Reopened literal type \(String(reflecting: Literal.self)) does not match \(String(reflecting: Value.self))."
        )
    }
    return value
}


///
/// Reads rows from a database using an `XLRowReader`.
///
/// The reader passed to ``readRow(reader:)`` is borrowed for that call. An
/// implementation must not store it or capture it in an escaping closure.
///
public protocol XLRowReadable<Row> {
    associatedtype Row
    func readRow(reader: XLRowReader) throws -> Row
}


///
/// An `XLEncodable` type that can be written to a database.
///
public protocol XLRowWritable<Row>: XLEncodable {
    associatedtype Row
}


// MARK: - Result


///
/// Metadata associated with a struct annotated with `@SQLResult`.
///
/// The types and methods defined by this protocol are implemented by macro-generated code.
///
/// The word `...anonymous...` used in method names refers to a defunct implementation detail
/// where column names were anonymized as `c0`, `c1`, ... `cN`. This reduced the length of the SQL
/// string that needed to be parsed, but also reduced readability, so columns now retain their names.
/// The word `...named...` indicates that the result is an
/// identifiable type such as a table, from, join, subquery, or common table, and can be used in an `IN`
/// expression. Examples of results that are unnamed include the set of columns in a `SELECT` statement,
/// and the result of a `UNION`, `INTERSECT`, or `EXCEPT`.
///
public protocol XLResult {
    typealias MetaRowIterator = (XLRowReader) throws -> Self
    
    ///
    /// Duplicate of the struct where each field is forced to be nullable.
    ///
    associatedtype Nullable: XLMetaNullable
    
    ///
    /// Metadata used when the result is returned in a query.
    ///
    associatedtype MetaResult: XLMetaResult
    
    ///
    /// Metadata used when the result is returned with a name.
    ///
    associatedtype MetaNamedResult: XLMetaNamedResult
    
    ///
    /// Metadata used when the result can evaluate to null, such as when the result is used in a left join
    /// expression.
    ///
    associatedtype MetaNullableResult: XLMetaNullableResult
    
    ///
    /// Metadata used when the result is used with a named table that can evaluate to null.
    ///
    associatedtype MetaNullableNamedResult: XLMetaNullableNamedResult
    
    ///
    /// Metadata used when the result is returned by a common table expression.
    ///
    associatedtype MetaCommonTable: XLMetaCommonTable
    
    ///
    /// Reader used to assign values to each field of the result.
    ///
    associatedtype SQLReader: XLRowReadable

    ///
    /// Creates a common table reference.
    ///
    static func makeSQLCommonTable(namespace: XLNamespace, dependency: XLCommonTableDependency) -> MetaCommonTable

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration, iterator: @escaping MetaRowIterator) -> MetaNamedResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult
    
    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    ///
    /// TODO: Remove
    ///
    static func makeSQLAnonymousNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult
}


// MARK: - Table


///
/// Metadata associated with a struct annotated with `SQLTable`.
///
/// Types and methods defined by this protocol are implemented by macro code generation.
///
public protocol XLTable: XLResult {
        
    ///
    /// Metadata used when the table is used as the target destination in a write statement.
    ///
    associatedtype MetaWritableTable: XLMetaWritableTable
    
    ///
    /// Metadata used when the table is used in an insert statement.
    ///
    associatedtype MetaInsert: XLMetaInsert
    
    ///
    /// Metadata used when the table is used in an update statement.
    ///
    associatedtype MetaUpdate: XLMetaUpdate
    
    ///
    /// Metadata used when the table is used in a create statement.
    ///
    associatedtype MetaCreate: XLMetaCreate
    
    ///
    /// Metadata used when a table is used in a create statement with a select query.
    ///
    associatedtype MetaCreateAs: XLMetaCreate

    ///
    /// The name of the underlying SQL table represented by the struct.
    ///
    static func sqlTableName() -> XLQualifiedTableName
    
    ///
    /// Creates metadata for using the struct as a table in a statement.
    ///
    static func makeSQLTable(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaResult

    ///
    /// Creates metadata for using the struct as a table with a name in a statement.
    ///
    static func makeSQLNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNamedResult

    ///
    /// Creates metadata for using the struct as a table in a statement where the table can evaluate to null,
    /// such as when it is used in a left join.
    ///
    static func makeSQLNullableResult(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaNullableResult

    ///
    /// Creates metadata for using the struct as a table with a name in a statement where the table can
    /// evaluate to null.
    ///
    static func makeSQLNullableNamedResult(namespace: XLNamespace, dependency: XLNamedTableDeclaration) -> MetaNullableNamedResult

    ///
    /// Creates metadata for using the struct in an insert statement.
    ///
    static func makeSQLInsert(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable
    
    ///
    /// Creates metadata for using the struct in an update statement.
    ///
    static func makeSQLUpdate(namespace: XLNamespace, dependency: XLTableDeclaration) -> MetaWritableTable
    
    ///
    /// Creates metadata for using the struct in a create statement.
    ///
    static func makeSQLCreate() -> MetaCreate
    
    ///
    /// Creates metadata for using the struct in a create statement with a select query.
    ///
    static func makeSQLCreateAs() -> MetaCreateAs
}


///
/// Maintains a collection of unique names for common table expressions, tables, and parameters.
///
/// Aliases are used to refer to tables, columns and values by names. If an alias is not defined explicitly, one
/// is assigned automatically. Automatically assigned aliases are assigned sequentially in the order in which
/// they are requested.
///
public class XLNamespace {
    
    private var usedAliases: Set<String> = []
    
    private var aliasCount = 0
    
    public var nameFormat: String
    
    private init(nameFormat: String) {
        self.nameFormat = nameFormat
    }

    ///
    /// Creates an alias with a given name.
    ///
    /// Creates and returns an alias with a given name. The alias is tracked to avoid conflicts. If the alias is
    /// not specified then one is assigned automatically using `nextAlias()`.
    ///
    func makeAlias(alias: XLName?) -> XLName {
        let newAlias = alias ?? nextAlias()
        usedAliases.insert(aliasKey(newAlias))
        return newAlias
    }
    
    ///
    /// Creates the next alias in the sequence.
    ///
    func nextAlias() -> XLName {
        var attemptedAliases: Set<String> = []
        while true {
            let alias = XLName(String(format: nameFormat, aliasCount))
            aliasCount += 1
            let key = aliasKey(alias)
            if !usedAliases.contains(key) {
                return alias
            }
            if !attemptedAliases.insert(key).inserted {
                return nextFallbackAlias(stem: alias.rawValue)
            }
        }
    }

    private func aliasKey(_ alias: XLName) -> String {
        alias.rawValue.lowercased()
    }

    private func nextFallbackAlias(stem: String) -> XLName {
        var suffix = 0
        while true {
            let alias = XLName("\(stem)\(suffix)")
            suffix += 1
            if !usedAliases.contains(aliasKey(alias)) {
                return alias
            }
        }
    }
    
    ///
    /// instantiates a namespace used for common table expressions.
    ///
    public static func common() -> XLNamespace {
        XLNamespace(nameFormat: "cte%d")
    }
    
    ///
    /// Instantiates a namespace used for tables.
    ///
    public static func table() -> XLNamespace {
        XLNamespace(nameFormat: "t%d")
    }
    
    ///
    /// Instantiates a namespace used for parameters.
    ///
    public static func parameter() -> XLNamespace {
        XLNamespace(nameFormat: "p%d")
    }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where every field is forced to be optional.
///
/// Implemented by macro.
///
public protocol XLMetaNullable {
    associatedtype Basis
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is used as a normal table in a
/// query.
///
/// Implemented by macro.
///
public protocol XLMetaResult: XLEncodable {
    associatedtype Row
    var _namespace: XLNamespace { get }
    var _dependency: XLTableDeclaration { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is used as a table with a given
/// name in a query.
///
/// Implemented by macro.
///
public protocol XLMetaNamedResult: XLEncodable {
    associatedtype Row
    var _namespace: XLNamespace { get }
    var _dependency: XLNamedTableDeclaration { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is used as a table in a query
/// where the table can resolve to NULL, such as in a LEFT JOIN.
///
/// Implemented by macro.
///
public protocol XLMetaNullableResult: XLEncodable {
    associatedtype Dependency = XLTableDeclaration
    var _namespace: XLNamespace { get }
    var _dependency: Dependency { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct  where the struct is used as a table with a given
/// name in a query, and where the table can resolve to NULL, such as a LEFT JOIN in a common table
/// expression.
///
/// Implemented by macro.
///
public protocol XLMetaNullableNamedResult: XLEncodable {
    associatedtype Dependency = XLTableDeclaration & XLNamedDependency
    var _namespace: XLNamespace { get }
    var _dependency: Dependency { get }
}


///
/// Metadata for a `@SQLTable` or `@SQLResult` struct where the struct is returned from a common
/// table expression.
///
/// Implemented by macro.
///
public protocol XLMetaCommonTable {
    associatedtype Result: XLResult
    var definition: XLCommonTableDependency { get }
}


///
/// Metadata for a `@SQLTable` struct where the table is written to.
///
/// Implemented by macro.
///
public protocol XLMetaWritableTable<Row>: XLEncodable {
    associatedtype Row
    var _table: any XLEncodable { get }
}


///
/// Metadata for a `@SQLTable` struct where the struct is used in an INSERT statement.
///
/// Implemented by macro.
///
public protocol XLMetaInsert<Row>: XLEncodable, XLRowWritable {
    associatedtype Row
    init(_ instance: Row)
}


///
/// Metadata for a `@SQLTable`struct where the struct is used in an UPDATE statement.
///
/// Implemented by macro.
///
public protocol XLMetaUpdate<Row>: XLEncodable, XLRowWritable {
    associatedtype Row
    init()
}


///
/// Metadata for a `@SQLTable` struct where the struct is used in a CREATE statement.
///
public protocol XLMetaCreate: XLEncodable {
    associatedtype Table
}


///
/// A `@SQLTable` or `@SQLResult` struct which contains a set of columns.
///
/// The struct may be named, such as a `@SQLTable` where the columns are defined on a specific table, or
/// unnamed, such as a `@SQLResult` where the columns are returned in a select query.
///
public protocol XLColumnDependency {
    
    ///
    /// Creates a qualified name for a column on the struct.
    ///
    /// For a `@SQLTable` struct this method returns the qualified name of the column including the table
    /// name. For a `@SQLResult` struct this method returns the bare column name.
    ///
    func qualifiedName(forColumn name: XLName) -> XLQualifiedName
}


///
///
/// A dependency which can be identified by an alias which can be used in an IN clause, such as a table,
/// common table, from clause, join clause. Excludes unnamed results such as select columns, UNION,
/// UNION ALL, INTERSECT, and EXCEPT.
///
public protocol XLNamedDependency {
    var alias: XLName { get }
}


///
/// A normal SQL table.
///
public typealias XLTableDeclaration = XLEncodable & XLColumnDependency


///
/// A table with a given name.
///
public typealias XLNamedTableDeclaration = XLEncodable & XLColumnDependency & XLNamedDependency


///
/// A common table expression.
///
public struct XLCommonTableDependency: XLColumnDependency, XLNamedDependency {
    
    public var alias: XLName

    internal var statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }

    public func makeSQL(context: inout XLCommonTablesBuilder) {
        context.commonTable(alias: alias) { context in
            statement.makeSQL(context: &context)
        }
    }
}


///
/// A recursive common table expression.
///
/// A recursive common table expression is a common table expression which contains a reference to itself.
///
/// > Note: Recursive common table expressions are represented by a reference type and therefore require
/// stack allocation.
///
internal class XLRecursiveCommonTableStatement: XLEncodable {
    
    internal var statement: (any XLEncodable)!

    func makeSQL(context: inout XLBuilder) {
        statement.makeSQL(context: &context)
    }
}


///
/// The result of a select statement.
///
public struct XLSelectResultDependency: XLTableDeclaration {
    
    public init() {
        
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedSelectColumnName(column: name)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        
    }
}

///
/// A table used in a FROM clause in a select query.
///
public struct XLFromTableDependency: XLTableDeclaration, XLNamedDependency {

    internal let source: any XLEncodable

    public var alias: XLName

    internal init(source: any XLEncodable, alias: XLName) {
        self.source = source
        self.alias = alias
    }

    public init(qualifiedName: XLQualifiedName, alias: XLName) {
        self.init(source: qualifiedName, alias: alias)
    }

    public init(commonTable: XLCommonTableDependency, alias: XLName) {
        self.init(source: commonTable.alias, alias: alias)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator("AS", left: source.makeSQL, right: alias.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


@available(*, deprecated, renamed: "XLFromTableDependency")
public typealias XLFromCommonTableDependency = XLFromTableDependency


///
/// A table used in a FROM clause in an UPDATE statement.
///
public struct XLUpdateFromTableDependency: XLTableDeclaration, XLNamedDependency {

    public var alias: XLName
    
    public var statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(
            "AS",
            left: { builder in
                builder.parenthesis(contents: statement.makeSQL)
            },
            right: alias.makeSQL
        )
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a UNION clause.
///
public struct XLUnionDependency: XLTableDeclaration {

    public init() {
    }

    public func makeSQL(context: inout XLBuilder) {
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedSelectColumnName(column: name)
    }
}


///
/// Vestigial join-kind enumeration.
///
/// This type is unused by the library — join rendering is driven by the
/// canonical ``Join/Kind``, which covers inner, left, right, full outer, and
/// cross joins. It is retained (deprecated) only for source compatibility and
/// does not receive new cases.
///
@available(*, deprecated, message: "Unused; the canonical join kinds are Join.Kind.")
public enum JoinKind: String {
    case innerJoin = "INNER JOIN"
    case leftJoin = "LEFT JOIN"
}


///
/// A table used in a subquery.
///
public struct XLSubqueryDependency: XLTableDeclaration, XLNamedDependency {
    
    public var alias: XLName

    private let statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func makeSQL(context: inout XLBuilder) {
        context.binaryOperator(
            "AS",
            left: { context in
                context.parenthesis(contents: statement.makeSQL)
            }, 
            right: alias.makeSQL
        )
        
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}


///
/// A table used in a FROM clause in a subquery.
///
public struct XLFromSubqueryDependency: XLTableDeclaration, XLNamedDependency {
    
    public var alias: XLName

    private let statement: any XLEncodable

    public init(alias: XLName, statement: any XLEncodable) {
        self.alias = alias
        self.statement = statement
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis(contents: statement.makeSQL)
    }
    
    public func qualifiedName(forColumn name: XLName) -> XLQualifiedName {
        XLQualifiedTableAliasColumnName(table: alias, column: name)
    }
}
