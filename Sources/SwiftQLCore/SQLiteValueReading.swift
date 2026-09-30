//
//  SQLiteValueReading.swift
//  SwiftQLCore
//
//  How a SQLite value is read as a Swift value, shared by SwiftQL's column
//  readers and the functions this module bundles, so the two cannot read an
//  argument differently (issue #683).
//

import Foundation


package enum XLSQLiteValueReading {

    /// The value at `index`, or the error a read past the end reports.
    package static func value(
        at index: Int,
        in values: [XLSQLiteValue],
        expectedType: String?
    ) throws -> XLSQLiteValue {
        guard values.indices.contains(index) else {
            throw XLColumnReadError(
                index: index,
                expectedType: expectedType,
                failure: .indexOutOfBounds(valueCount: values.count)
            )
        }
        return values[index]
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
