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
        if case .null = try value(at: index, expectedType: nil) {
            return true
        }
        return false
    }

    public func readInteger(at index: Int) throws -> Int {
        let value = try value(at: index, expectedType: "Int")
        switch value {
        case .integer(let integer):
            guard let result = Int(exactly: integer) else {
                throw XLSQLiteValueReading.typeMismatch(value, at: index, expectedType: "Int")
            }
            return result
        case .real(let real):
            let truncated = real.rounded(.towardZero)
            let upperBound = -Double(Int64.min)
            guard
                truncated.isFinite,
                truncated >= Double(Int64.min),
                truncated < upperBound
            else {
                throw XLSQLiteValueReading.typeMismatch(value, at: index, expectedType: "Int")
            }
            return Int(Int64(truncated))
        case .null:
            throw XLSQLiteValueReading.nullValue(at: index, expectedType: "Int")
        case .text, .blob:
            throw XLSQLiteValueReading.typeMismatch(value, at: index, expectedType: "Int")
        }
    }

    public func readReal(at index: Int) throws -> Double {
        let value = try value(at: index, expectedType: "Double")
        switch value {
        case .integer(let integer):
            return Double(integer)
        case .real(let real):
            return real
        case .null:
            throw XLSQLiteValueReading.nullValue(at: index, expectedType: "Double")
        case .text, .blob:
            throw XLSQLiteValueReading.typeMismatch(value, at: index, expectedType: "Double")
        }
    }

    public func readText(at index: Int) throws -> String {
        try XLSQLiteValueReading.text(
            value(at: index, expectedType: "String"),
            at: index
        )
    }

    public func readBlob(at index: Int) throws -> Data {
        let value = try value(at: index, expectedType: "Data")
        switch value {
        case .blob(let blob):
            return blob
        case .text(let text):
            return Data(text.utf8)
        case .null:
            throw XLSQLiteValueReading.nullValue(at: index, expectedType: "Data")
        case .integer, .real:
            throw XLSQLiteValueReading.typeMismatch(value, at: index, expectedType: "Data")
        }
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
