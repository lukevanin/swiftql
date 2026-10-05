//
//  SQLiteValueReading.swift
//  SwiftQLCore
//
//  How a SQLite value is read as a Swift value, shared by SwiftQL's column
//  readers, the row handles a connection lends (issue #678), and the
//  functions this module bundles, so none of them can read a value
//  differently (issue #683).
//

import Foundation


package enum XLSQLiteValueReading {

    /// The error a read at `index` reports when a row has `count` values and
    /// `index` is not one of them, or `nil` when it is.
    package static func indexOutOfBounds(
        _ index: Int,
        count: Int,
        expectedType: String?
    ) -> XLColumnReadError? {
        guard index < 0 || index >= count else {
            return nil
        }
        return XLColumnReadError(
            index: index,
            expectedType: expectedType,
            failure: .indexOutOfBounds(valueCount: count)
        )
    }

    /// The value at `index`, or the error a read past the end reports.
    package static func value(
        at index: Int,
        in values: [XLSQLiteValue],
        expectedType: String?
    ) throws -> XLSQLiteValue {
        if let error = indexOutOfBounds(index, count: values.count, expectedType: expectedType) {
            throw error
        }
        return values[index]
    }

    /// Whether `value` is SQL `NULL`.
    package static func isNull(_ value: XLSQLiteValue) -> Bool {
        if case .null = value {
            return true
        }
        return false
    }

    /// `value` read as an integer: INTEGER, or a REAL whose truncation fits
    /// in `Int64`. NULL and every other storage class are errors.
    package static func integer(_ value: XLSQLiteValue, at index: Int) throws -> Int {
        switch value {
        case .integer(let integer):
            guard let result = Int(exactly: integer) else {
                throw typeMismatch(value, at: index, expectedType: "Int")
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
                throw typeMismatch(value, at: index, expectedType: "Int")
            }
            return Int(Int64(truncated))
        case .null:
            throw nullValue(at: index, expectedType: "Int")
        case .text, .blob:
            throw typeMismatch(value, at: index, expectedType: "Int")
        }
    }

    /// `value` read as a real number: INTEGER or REAL. NULL and every other
    /// storage class are errors.
    package static func real(_ value: XLSQLiteValue, at index: Int) throws -> Double {
        switch value {
        case .integer(let integer):
            return Double(integer)
        case .real(let real):
            return real
        case .null:
            throw nullValue(at: index, expectedType: "Double")
        case .text, .blob:
            throw typeMismatch(value, at: index, expectedType: "Double")
        }
    }

    /// `value` read as a BLOB: BLOB, or the UTF-8 bytes of TEXT. NULL and
    /// every other storage class are errors.
    package static func blob(_ value: XLSQLiteValue, at index: Int) throws -> Data {
        switch value {
        case .blob(let blob):
            return blob
        case .text(let text):
            return Data(text.utf8)
        case .null:
            throw nullValue(at: index, expectedType: "Data")
        case .integer, .real:
            throw typeMismatch(value, at: index, expectedType: "Data")
        }
    }

    /// `value` read as text: TEXT, or a BLOB holding UTF-8. NULL and every
    /// other storage class are errors rather than silent conversions.
    package static func text(_ value: XLSQLiteValue, at index: Int) throws -> String {
        switch value {
        case .text(let text):
            return text
        case .blob(let blob):
            guard let text = String(data: blob, encoding: .utf8) else {
                throw typeMismatch(value, at: index, expectedType: "String")
            }
            return text
        case .null:
            throw nullValue(at: index, expectedType: "String")
        case .integer, .real:
            throw typeMismatch(value, at: index, expectedType: "String")
        }
    }

    /// The error for a NULL read as a non-optional `expectedType`.
    package static func nullValue(at index: Int, expectedType: String) -> XLColumnReadError {
        XLColumnReadError(index: index, expectedType: expectedType, failure: .nullValue)
    }

    /// The error for a value whose storage class cannot be read as
    /// `expectedType`.
    package static func typeMismatch(
        _ value: XLSQLiteValue,
        at index: Int,
        expectedType: String
    ) -> XLColumnReadError {
        XLColumnReadError(
            index: index,
            expectedType: expectedType,
            failure: .typeMismatch(actualType: storageClassName(value))
        )
    }

    /// SQLite's name for the storage class of `value`.
    package static func storageClassName(_ value: XLSQLiteValue) -> String {
        switch value {
        case .null:
            return "NULL"
        case .integer:
            return "INTEGER"
        case .real:
            return "REAL"
        case .text:
            return "TEXT"
        case .blob:
            return "BLOB"
        }
    }
}
