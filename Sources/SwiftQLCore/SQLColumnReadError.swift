//
//  SQLColumnReadError.swift
//  SwiftQLCore
//
//  Why a value could not be read from a row or from a function's arguments.
//
//  Moved from SwiftQL (issue #683): the bundled `regexp`, now in this module,
//  reports an argument it cannot read with this error, as it always has.
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
