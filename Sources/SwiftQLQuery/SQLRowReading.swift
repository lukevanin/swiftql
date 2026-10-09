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


// `XLColumnReadError` is declared in SwiftQLCore (issue #683), so the
// bundled `regexp` there can report an argument it cannot read.
//
// `XLColumnReader` is declared in SwiftQLCore too (issue #678), so a row
// handle a connection lends can be one, and the decoder reads its columns
// without first copying the row into an array of values.


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
package struct XLColumnValuesRowReader<Output>: XLRowReader {

    private struct State {
        var count: Int = 0
        let reader: any XLColumnReader
        /// How this row's raw dialect values are read, found by the first
        /// raw read and kept for the rest of the row.
        var rawReader: RawReader?
    }

    /// Where a static row layout's raw dialect values come from.
    private enum RawReader {
        case staticReader(any XLStaticColumnReader)
        case rowHandle(any XLRowHandle)
        case unavailable
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
    package static func withReader<Result>(
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
    package func column<T>(
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

    package func dialectValue<Dialect>(
        at index: Int,
        using dialect: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        switch rawReader() {
        case .staticReader(let staticReader):
            return try staticReader.dialectValue(at: index, using: dialect)
        case .rowHandle(let handle):
            return try xlDialectValue(at: index, of: handle, as: Dialect.Value.self)
        case .unavailable:
            throw XLStaticRowReadError.rawDialectValuesUnavailable(
                index: index,
                dialect: dialect.descriptor.identity,
                readerType: String(
                    reflecting: type(of: state.pointee.reader as Any)
                )
            )
        }
    }

    /// Finds how this row's raw values are read on the first raw read, so a
    /// row with several raw columns casts its reader once.
    ///
    /// A row handle from a driver built on SwiftQLCore alone cannot conform
    /// to `XLStaticColumnReader`, which is SwiftQL's, but it carries the
    /// dialect's values itself (issue #678). The explicit protocol is asked
    /// first, so a reader that is both reads through its own conformance.
    private func rawReader() -> RawReader {
        if let rawReader = state.pointee.rawReader {
            return rawReader
        }
        let reader = state.pointee.reader
        let rawReader: RawReader
        if let staticReader = reader as? any XLStaticColumnReader {
            rawReader = .staticReader(staticReader)
        }
        else if let handle = reader as? any XLRowHandle {
            rawReader = .rowHandle(handle)
        }
        else {
            rawReader = .unavailable
        }
        state.pointee.rawReader = rawReader
        return rawReader
    }
}


/// The raw value at `index` of a row handle, as the dialect value type a
/// static row layout expects (issue #678).
///
/// An index outside the row is reported with the expected type, before the
/// handle is asked for it, and a handle whose values are another dialect's
/// fails with ``XLStaticRowReadError/dialectValueTypeMismatch(index:expected:actual:)``.
/// Every row handle's raw read goes through here: SwiftQL's own handles call
/// it from their ``XLStaticColumnReader`` conformance, and
/// `XLColumnValuesRowReader` calls it for a handle from outside SwiftQL.
package func xlDialectValue<Handle, Expected>(
    at index: Int,
    of handle: Handle,
    as _: Expected.Type
) throws -> Expected where Handle: XLRowHandle {
    try XLSQLiteValueReading.checkIndex(
        index,
        count: handle.columnCount,
        expectedType: String(reflecting: Expected.self)
    )
    let value = try handle.value(at: index)
    guard let typed = value as? Expected else {
        throw XLStaticRowReadError.dialectValueTypeMismatch(
            index: index,
            expected: String(reflecting: Expected.self),
            actual: String(reflecting: Handle.Value.self)
        )
    }
    return typed
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
