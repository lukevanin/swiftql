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

    /// Throws the error a read at `index` reports when a row has `count`
    /// values and `index` is not one of them.
    package static func checkIndex(
        _ index: Int,
        count: Int,
        expectedType: @autoclosure () -> String?
    ) throws {
        guard index < 0 || index >= count else {
            return
        }
        throw XLColumnReadError(
            index: index,
            expectedType: expectedType(),
            failure: .indexOutOfBounds(valueCount: count)
        )
    }

    /// The value at `index`, or the error a read past the end reports.
    package static func value(
        at index: Int,
        in values: [XLSQLiteValue],
        expectedType: String?
    ) throws -> XLSQLiteValue {
        try checkIndex(index, count: values.count, expectedType: expectedType)
        return values[index]
    }

    /// Whether `value` is SQL `NULL`.
    package static func isNull(_ value: XLSQLiteValue) -> Bool {
        if case .null = value {
            return true
        }
        return false
    }

    /// `value` read as an integer: INTEGER, or a REAL that is exactly an
    /// integer in `Int` range (issue #690). A REAL with a fractional part, an
    /// infinity, or a magnitude beyond `Int` is an error, not a truncation.
    /// NULL and every other storage class are errors.
    ///
    /// This is the numeric rule every read path shares. A static layout's
    /// intrinsic fields apply it through `coerced(_:to:)`, so one row reads
    /// the same on either path.
    package static func integer(_ value: XLSQLiteValue, at index: Int) throws -> Int {
        switch value {
        case .integer(let integer):
            guard let result = Int(exactly: integer) else {
                throw typeMismatch(value, at: index, expectedType: "Int")
            }
            return result
        case .real(let real):
            guard let result = Int(exactly: real) else {
                throw typeMismatch(value, at: index, expectedType: "Int")
            }
            return result
        case .null:
            throw nullValue(at: index, expectedType: "Int")
        case .text, .blob:
            throw typeMismatch(value, at: index, expectedType: "Int")
        }
    }

    /// `value` read as a real number: INTEGER or REAL. An INTEGER converts
    /// as SQLite's REAL affinity converts it (issue #690). NULL and every
    /// other storage class are errors.
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

    /// `value` as a value of `storage`, by the numeric rule `integer(_:at:)`
    /// and `real(_:at:)` share, or `nil` when it cannot be (issue #690).
    ///
    /// A value already of `storage` is returned as it is. A REAL that is
    /// exactly an integer becomes the INTEGER, and an INTEGER becomes the
    /// REAL, which is the conversion SQLite applies on write to a column of
    /// INTEGER or REAL affinity. Nothing else converts: TEXT, BLOB, NULL, and
    /// a REAL that is not exactly an `Int` return `nil`.
    package static func coerced(
        _ value: XLSQLiteValue,
        to storage: XLSQLiteStorageClass
    ) -> XLSQLiteValue? {
        if value.storageType == storage {
            return value
        }
        switch (value, storage) {
        case (.real(let real), .integer):
            return Int64(exactly: real).map(XLSQLiteValue.integer)
        case (.integer(let integer), .real):
            return .real(Double(integer))
        default:
            return nil
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
