//
//  SQLRowHandle.swift
//  SwiftQLCore
//
//  The row a connection's cursor is on, read one column at a time
//  (issue #678). The decoder reads a column through the handle the cursor
//  lends, so no array of dialect values is built for a row first.
//
//  `XLColumnReader` moved here from SwiftQL so that a row handle, declared by
//  a driver that depends on SwiftQLCore alone, can be one.
//

import Foundation


///
/// Reads the value for a column for a row returned from a select query.
///
/// Used when reading results of a query returned by SQLite.
///
/// Readers use SQLite storage classes consistently for query results and
/// custom-function arguments. Integer reads accept INTEGER and representable
/// REAL values; real reads accept INTEGER and REAL; text reads accept TEXT and
/// UTF-8 BLOB; and BLOB reads accept BLOB and the UTF-8 bytes of TEXT. Other
/// storage-class conversions throw `XLColumnReadError`.
///
public protocol XLColumnReader {

    ///
    /// Determines if the value for a column at a given index contains a NULL value.
    ///
    /// - Parameter index: Index of the column to examine.
    ///
    /// - Returns: `true` if the column value is NULL.
    /// - Throws: `XLColumnReadError` if `index` is outside the available values.
    ///
    func isNull(at index: Int) throws -> Bool

    ///
    /// Reads an integer value for a column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Integer value for the column.
    /// - Throws: `XLColumnReadError` if the value cannot be read as an integer.
    ///
    func readInteger(at index: Int) throws -> Int

    ///
    /// Reads a real number for a column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Floating point value for the column.
    /// - Throws: `XLColumnReadError` if the value cannot be read as a real number.
    ///
    func readReal(at index: Int) throws -> Double

    ///
    /// Reads a text value for the column at a given index
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: String value for the column.
    /// - Throws: `XLColumnReadError` if the value cannot be read as text.
    ///
    func readText(at index: Int) throws -> String

    ///
    /// Reads a BLOB value for the column at a given index.
    ///
    /// - Parameter index: Index of the column to read.
    ///
    /// - Returns: Data value for the column.
    /// - Throws: `XLColumnReadError` if the value cannot be read as a BLOB.
    ///
    func readBlob(at index: Int) throws -> Data
}


/// The result row a connection's cursor is positioned on (issue #678).
///
/// A handle reads one column when it is asked for it. SwiftQL decodes a row
/// by reading the handle as an ``XLColumnReader``, so a connection that reads
/// its database's columns directly, such as with `sqlite3_column_int64`,
/// decodes a row without building an array of dialect values for it, and
/// never reads a column the decoder does not ask for. ``copyValues()`` builds
/// that array when a caller needs one.
///
/// A handle is borrowed. It is valid only until the callback that received
/// it returns, or until the stepper that returned it is called again,
/// because the cursor may reuse the row's storage for the next row. Read,
/// decode, or copy what you need before then, and do not keep the handle.
///
/// The column reads follow the storage-class rules ``XLColumnReader``
/// describes. A handle whose `Value` is `XLSQLiteValue` gets all five from
/// ``value(at:)``, and overrides the ones it can read more directly. A handle
/// for another dialect implements them itself.
public protocol XLRowHandle<Value>: XLColumnReader {

    associatedtype Value: XLDialectValue

    /// The number of columns in the row.
    var columnCount: Int { get }

    /// The dialect value of the column at `index`.
    ///
    /// - Throws: `XLColumnReadError` with
    ///   ``XLColumnReadError/Failure/indexOutOfBounds(valueCount:)`` when
    ///   `index` is not a column of the row.
    func value(at index: Int) throws -> Value
}


extension XLRowHandle {

    /// Every column of the row as dialect values, in column order.
    ///
    /// This is the row as the value-level connection members return it. The
    /// array is a copy, so it stays valid after the handle does.
    public func copyValues() throws -> [Value] {
        var values: [Value] = []
        try appendValues(to: &values)
        return values
    }

    /// Appends every column of the row to `values`, so a caller that copies
    /// many rows can reuse one buffer.
    public func appendValues(to values: inout [Value]) throws {
        let count = columnCount
        // Reserving an exact size on every call would defeat the array's
        // geometric growth for a caller that appends many rows to one buffer.
        if values.isEmpty {
            values.reserveCapacity(count)
        }
        for index in 0 ..< count {
            values.append(try value(at: index))
        }
    }
}


/// The SQLite storage-class reads, from ``XLRowHandle/value(at:)``. Each read
/// checks the index against ``XLRowHandle/columnCount`` first, then asks for
/// that one column, so a handle that implements only `value(at:)` reads no
/// column the decoder does not ask for.
extension XLRowHandle where Value == XLSQLiteValue {

    public func isNull(at index: Int) throws -> Bool {
        XLSQLiteValueReading.isNull(try sqliteValue(at: index, expectedType: nil))
    }

    public func readInteger(at index: Int) throws -> Int {
        try XLSQLiteValueReading.integer(
            sqliteValue(at: index, expectedType: "Int"),
            at: index
        )
    }

    public func readReal(at index: Int) throws -> Double {
        try XLSQLiteValueReading.real(
            sqliteValue(at: index, expectedType: "Double"),
            at: index
        )
    }

    public func readText(at index: Int) throws -> String {
        try XLSQLiteValueReading.text(
            sqliteValue(at: index, expectedType: "String"),
            at: index
        )
    }

    public func readBlob(at index: Int) throws -> Data {
        try XLSQLiteValueReading.blob(
            sqliteValue(at: index, expectedType: "Data"),
            at: index
        )
    }

    /// The value at `index`, with an out-of-bounds read reported for the
    /// type the caller asked for before ``value(at:)`` is called, so a
    /// handle's own `value(at:)` never sees an index outside the row.
    private func sqliteValue(at index: Int, expectedType: String?) throws -> XLSQLiteValue {
        try XLSQLiteValueReading.checkIndex(index, count: columnCount, expectedType: expectedType)
        return try value(at: index)
    }
}


/// A row handle over values already in memory.
///
/// The connection contract's default row-handle members lend one per row of
/// ``XLDatabaseDriverConnection/forEachRow(_:_:)``, so a connection that
/// streams only values still serves a reader of handles.
///
/// Its column reads follow ``XLColumnReader``'s SQLite storage-class rules
/// when `Value` is `XLSQLiteValue`. A value of any other dialect has no
/// storage class those rules know, so reading it throws
/// ``XLColumnReadError/Failure/typeMismatch(actualType:)`` naming its
/// storage type; read it with ``value(at:)`` instead.
public struct XLValuesRowHandle<Value: XLDialectValue>: XLRowHandle {

    /// The row's values, in column order.
    public let values: [Value]

    public init(_ values: [Value]) {
        self.values = values
    }

    public var columnCount: Int {
        values.count
    }

    public func value(at index: Int) throws -> Value {
        try checked(index, expectedType: nil)
    }

    public func isNull(at index: Int) throws -> Bool {
        XLSQLiteValueReading.isNull(try sqliteValue(at: index, expectedType: nil))
    }

    public func readInteger(at index: Int) throws -> Int {
        try XLSQLiteValueReading.integer(
            sqliteValue(at: index, expectedType: "Int"),
            at: index
        )
    }

    public func readReal(at index: Int) throws -> Double {
        try XLSQLiteValueReading.real(
            sqliteValue(at: index, expectedType: "Double"),
            at: index
        )
    }

    public func readText(at index: Int) throws -> String {
        try XLSQLiteValueReading.text(
            sqliteValue(at: index, expectedType: "String"),
            at: index
        )
    }

    public func readBlob(at index: Int) throws -> Data {
        try XLSQLiteValueReading.blob(
            sqliteValue(at: index, expectedType: "Data"),
            at: index
        )
    }

    private func checked(_ index: Int, expectedType: String?) throws -> Value {
        try XLSQLiteValueReading.checkIndex(index, count: values.count, expectedType: expectedType)
        return values[index]
    }

    /// The value at `index` as a SQLite value. The type is checked at run
    /// time because the handle is generic over every dialect's value. SwiftQL
    /// decodes a SQLite `XLValuesRowHandle` through `XLSQLiteValueReader`
    /// instead, so its requests do not pay this cast per column.
    private func sqliteValue(at index: Int, expectedType: String?) throws -> XLSQLiteValue {
        let value = try checked(index, expectedType: expectedType)
        if let value = value as? XLSQLiteValue {
            return value
        }
        throw XLColumnReadError(
            index: index,
            expectedType: expectedType,
            failure: .typeMismatch(actualType: String(describing: value.storageType))
        )
    }
}


/// A row handle owns only its values, which every dialect's value type keeps
/// `Sendable`.
extension XLValuesRowHandle: Sendable {}
