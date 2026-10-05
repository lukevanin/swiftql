//
//  SQLiteValueReader.swift
//

import Foundation


/// Reads legacy SwiftQL literals from SQLite dialect values without depending
/// on a database-driver transport.
///
/// It is a row handle over values in memory, so its column reads are the
/// ones every SQLite row handle shares.
public struct XLSQLiteValueReader: XLStaticColumnReader, XLRowHandle {

    public let values: [XLSQLiteValue]

    public init(values: [XLSQLiteValue]) {
        self.values = values
    }

    /// The number of values, so the reader is an `XLRowHandle` and takes
    /// the five column reads every SQLite row handle shares (issue #678).
    public var columnCount: Int {
        values.count
    }

    public func value(at index: Int) throws -> XLSQLiteValue {
        try XLSQLiteValueReading.value(at: index, in: values, expectedType: nil)
    }

    public func dialectValue<Dialect>(
        at index: Int,
        using _: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        try xlDialectValue(at: index, of: self, as: Dialect.Value.self)
    }
}
