//
//  SQLiteValueReader.swift
//

import Foundation


/// Reads legacy SwiftQL literals from SQLite dialect values without depending
/// on a database-driver transport.
public struct XLSQLiteValueReader: XLStaticColumnReader {

    public let values: [XLSQLiteValue]

    public init(values: [XLSQLiteValue]) {
        self.values = values
    }

    public func isNull(at index: Int) throws -> Bool {
        XLSQLiteValueReading.isNull(try value(at: index, expectedType: nil))
    }

    public func readInteger(at index: Int) throws -> Int {
        try XLSQLiteValueReading.integer(
            value(at: index, expectedType: "Int"),
            at: index
        )
    }

    public func readReal(at index: Int) throws -> Double {
        try XLSQLiteValueReading.real(
            value(at: index, expectedType: "Double"),
            at: index
        )
    }

    public func readText(at index: Int) throws -> String {
        try XLSQLiteValueReading.text(
            value(at: index, expectedType: "String"),
            at: index
        )
    }

    public func readBlob(at index: Int) throws -> Data {
        try XLSQLiteValueReading.blob(
            value(at: index, expectedType: "Data"),
            at: index
        )
    }

    public func dialectValue<Dialect>(
        at index: Int,
        using _: Dialect
    ) throws -> Dialect.Value where Dialect: XLValueCodingDialect {
        let value = try value(at: index, expectedType: String(reflecting: Dialect.Value.self))
        guard let typed = value as? Dialect.Value else {
            throw XLStaticRowReadError.dialectValueTypeMismatch(
                index: index,
                expected: String(reflecting: Dialect.Value.self),
                actual: String(reflecting: XLSQLiteValue.self)
            )
        }
        return typed
    }

    private func value(at index: Int, expectedType: String?) throws -> XLSQLiteValue {
        try XLSQLiteValueReading.value(at: index, in: values, expectedType: expectedType)
    }
}
