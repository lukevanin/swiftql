//
//  SQLRowReading.swift
//  SwiftQL
//
//  Reading one row's values back out of a database: what a column reader is
//  asked for, what it can refuse, and how a row is assembled from columns.
//
//  Split out of SQLMeta.swift (issue #559). Foundation-only -- nothing here
//  knows about SQL, only about values arriving positionally.
//

import Foundation


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

    /// Reads a value whose type is statically known to be a literal.
    ///
    /// This is the same seam as ``staticColumn(_:alias:)``, restricted to a
    /// `T` that already conforms to ``XLLiteral``. Generated row readers name
    /// one concrete type per column, so the compiler selects this requirement
    /// for every literal column and the unconstrained requirement only for a
    /// contextual one.
    ///
    /// The distinction is a performance one. The unconstrained requirement
    /// must find the literal conformance at run time and reopen the
    /// expression as a parameterised existential; this requirement receives
    /// the conformance statically and reads the value directly. It is a
    /// requirement, and not an overload in an extension, because the
    /// generated code calls it on a protocol-typed reader: an extension
    /// member cannot win a dispatch that resolves through the witness table.
    func staticColumn<T>(
        _ expression: any XLExpression<T>,
        alias: XLName
    ) throws -> T where T: XLLiteral

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
    ) throws -> T where T: XLLiteral {
        try column(expression, alias: alias)
    }

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

    /// The output column aliases captured while replaying a projection's
    /// ``XLRowReadable/readRow(reader:)``, in projection order.
    ///
    /// A `RETURNING` clause reuses these names to render an unqualified column
    /// list, because SQLite rejects table-qualified names in `RETURNING`.
    var columnNames: [XLName] { names }

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
