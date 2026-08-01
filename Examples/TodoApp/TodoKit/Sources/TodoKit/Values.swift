import Foundation

import SwiftQL

/// A `UUID` column.
///
/// SwiftQL binds five intrinsic Swift types — `Bool`, `Int`, `Double`,
/// `String`, and `Data`. Anything else reaches SQLite through a type that
/// says how to read it, bind it, and write it as a literal. `XLCustomType`
/// is that protocol, and conforming to `XLComparable` on top of it is what
/// makes `==`, `<`, and friends available in a `Where` clause.
///
/// The stored form is the lowercase hyphenated spelling SwiftQL's own
/// ``XLUUIDValueCodec/text`` codec uses, so a database written by the demo
/// reads the same as one written through the codec registry.
public struct TodoUUID: XLCustomType, XLComparable, Hashable, Sendable {

    public enum ReadError: Error, LocalizedError {
        case notAUUID(String)

        public var errorDescription: String? {
            switch self {
            case .notAUUID(let text):
                return "\(text) is not a UUID."
            }
        }
    }

    public typealias T = Self

    public let wrappedValue: UUID

    public init(_ wrappedValue: UUID) {
        self.wrappedValue = wrappedValue
    }

    public init() {
        self.init(UUID())
    }

    public init(reader: XLFieldReader) throws {
        let text = try reader.readText()
        guard let value = UUID(uuidString: text) else {
            throw ReadError.notAUUID(text)
        }
        wrappedValue = value
    }

    public func bind(context: inout XLBindingContext) {
        context.bindText(value: storedText)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.text(storedText)
    }

    public static func sqlDefault() -> TodoUUID {
        TodoUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }

    private var storedText: String {
        wrappedValue.uuidString.lowercased()
    }
}

/// A `Date` column.
///
/// Stored as the ISO 8601 spelling SwiftQL's own ``XLDateTextCodec/standard``
/// codec uses: `YYYY-MM-DDTHH:MM:SS.SSSZ`, always UTC. That format sorts
/// correctly as text, which is what lets a due date drive `OrderBy` and an
/// overdue comparison without a conversion in Swift.
public struct TodoDate: XLCustomType, XLComparable, Hashable, Sendable {

    public enum ReadError: Error, LocalizedError {
        case notADate(String)

        public var errorDescription: String? {
            switch self {
            case .notADate(let text):
                return "\(text) is not an ISO 8601 date."
            }
        }
    }

    public typealias T = Self

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    public let wrappedValue: Date

    public init(_ wrappedValue: Date) {
        self.wrappedValue = wrappedValue
    }

    public init(reader: XLFieldReader) throws {
        let text = try reader.readText()
        guard let value = Self.formatter.date(from: text) else {
            throw ReadError.notADate(text)
        }
        wrappedValue = value
    }

    public func bind(context: inout XLBindingContext) {
        context.bindText(value: storedText)
    }

    public func makeSQL(context: inout XLBuilder) {
        context.text(storedText)
    }

    public static func sqlDefault() -> TodoDate {
        TodoDate(Date(timeIntervalSince1970: 0))
    }

    private var storedText: String {
        Self.formatter.string(from: wrappedValue)
    }
}

/// A to-do's priority.
///
/// `XLEnum` gives a raw-representable enum the same standing as its raw
/// value: a column, a result, a literal, or a bound parameter.
public enum TodoPriority: Int, XLEnum, CaseIterable, Sendable {

    public typealias T = Self

    case low = 0
    case normal = 1
    case high = 2

    public static func sqlDefault() -> TodoPriority {
        .normal
    }
}
