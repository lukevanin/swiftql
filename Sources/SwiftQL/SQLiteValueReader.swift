//
//  SQLiteValueReader.swift
//

import Foundation


/// Reads legacy SwiftQL literals from SQLite dialect values without depending
/// on a database-driver transport.
///
/// It is a row handle over values in memory, and reads its values by the
/// rules every SQLite row handle shares.
public struct XLSQLiteValueReader: XLStaticColumnReader, XLRowHandle {

    public let values: [XLSQLiteValue]

    public init(values: [XLSQLiteValue]) {
        self.values = values
    }

    /// The number of values, so the reader is an `XLRowHandle` (issue #678).
    public var columnCount: Int {
        values.count
    }

    public func value(at index: Int) throws -> XLSQLiteValue {
        try XLSQLiteValueReading.value(at: index, in: values, expectedType: nil)
    }

    // The five column reads are written here, rather than taken from the
    // `XLRowHandle` defaults in SwiftQLCore, so each read checks its index
    // once and runs code compiled for this reader. It serves `fetchOne()`,
    // live queries, and custom-function arguments.

    public func isNull(at index: Int) throws -> Bool {
        XLSQLiteValueReading.isNull(try value(at: index))
    }

    public func readInteger(at index: Int) throws -> Int {
        try XLSQLiteValueReading.integer(
            XLSQLiteValueReading.value(at: index, in: values, expectedType: "Int"),
            at: index
        )
    }

    public func readReal(at index: Int) throws -> Double {
        try XLSQLiteValueReading.real(
            XLSQLiteValueReading.value(at: index, in: values, expectedType: "Double"),
            at: index
        )
    }

    public func readText(at index: Int) throws -> String {
        try XLSQLiteValueReading.text(
            XLSQLiteValueReading.value(at: index, in: values, expectedType: "String"),
            at: index
        )
    }

    public func readBlob(at index: Int) throws -> Data {
        try XLSQLiteValueReading.blob(
            XLSQLiteValueReading.value(at: index, in: values, expectedType: "Data"),
            at: index
        )
    }

    public func dialectValue<Dialect>(
        at index: Int,
        using _: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        try xlDialectValue(at: index, of: self, as: Dialect.Value.self)
    }
}
