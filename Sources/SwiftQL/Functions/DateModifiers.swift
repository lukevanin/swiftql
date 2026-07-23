//
//  DateModifiers.swift
//
//
//  Created by Luke Van In on 2025/07/23.
//

import Foundation


///
/// A modifier applied to a SQLite date-and-time function.
///
/// SQLite's `date`, `time`, `datetime`, `julianday`, `unixepoch`, and
/// `strftime` functions accept an ordered list of modifiers that transform the
/// time value from left to right. A modifier renders as a single quoted string
/// literal argument, so it is escaped through the same text formatter as any
/// other string and cannot inject SQL.
///
/// Order is significant: `.months(1)` followed by `.startOfMonth` is not the
/// same as the reverse, so this type is always applied through the ordered
/// variadic arguments of the date functions rather than an unordered set.
///
/// The named members and factory methods cover the modifiers that are
/// available in every SQLite release the library validates against
/// (3.42.0 and later). The input-interpretation modifiers `unixepoch`,
/// `julianday`, and `auto` are not modelled as named members because their
/// availability and exact behaviour vary by release; a caller that targets a
/// known SQLite version can still express them with ``init(_:)``.
///
/// https://www.sqlite.org/lang_datefunc.html#modifiers
///
public struct XLDateModifier: Hashable, Sendable {

    ///
    /// The exact modifier text rendered into the SQL statement.
    ///
    public let rawValue: String

    ///
    /// Names a modifier by its exact SQLite text.
    ///
    /// The text is rendered as a quoted string literal, so it cannot inject
    /// SQL. Use this only for modifiers that are not already provided as a
    /// named member or factory method; a value SQLite does not recognise fails
    /// when the statement is prepared or stepped.
    ///
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    // MARK: - Relative offsets

    /// Adds `count` days to the time value. A negative value subtracts.
    public static func days(_ count: Int) -> XLDateModifier {
        offset(count, unit: "days")
    }

    /// Adds `count` hours to the time value. A negative value subtracts.
    public static func hours(_ count: Int) -> XLDateModifier {
        offset(count, unit: "hours")
    }

    /// Adds `count` minutes to the time value. A negative value subtracts.
    public static func minutes(_ count: Int) -> XLDateModifier {
        offset(count, unit: "minutes")
    }

    /// Adds `count` seconds to the time value. A negative value subtracts.
    public static func seconds(_ count: Int) -> XLDateModifier {
        offset(count, unit: "seconds")
    }

    /// Adds `count` months to the time value. A negative value subtracts.
    public static func months(_ count: Int) -> XLDateModifier {
        offset(count, unit: "months")
    }

    /// Adds `count` years to the time value. A negative value subtracts.
    public static func years(_ count: Int) -> XLDateModifier {
        offset(count, unit: "years")
    }

    // MARK: - Anchoring

    /// Shifts the time value back to the start of the day (00:00:00).
    public static let startOfDay = XLDateModifier("start of day")

    /// Shifts the time value back to midnight on the first day of the month.
    public static let startOfMonth = XLDateModifier("start of month")

    /// Shifts the time value back to midnight on the first day of the year.
    public static let startOfYear = XLDateModifier("start of year")

    ///
    /// Advances the time value to the next date whose day of week matches
    /// `day`, where 0 is Sunday and 6 is Saturday. If the time value already
    /// falls on `day`, it is left unchanged.
    ///
    public static func weekday(_ day: Int) -> XLDateModifier {
        XLDateModifier("weekday \(day)")
    }

    // MARK: - Rounding

    ///
    /// Rounds a month or year offset up when the resulting day would overflow
    /// the target month. Added in SQLite 3.42.0.
    ///
    public static let ceiling = XLDateModifier("ceiling")

    ///
    /// Rounds a month or year offset down when the resulting day would overflow
    /// the target month. Added in SQLite 3.42.0.
    ///
    public static let floor = XLDateModifier("floor")

    // MARK: - Time zone

    /// Interprets the preceding time value as UTC and converts it to local time.
    public static let localTime = XLDateModifier("localtime")

    /// Interprets the preceding time value as local time and converts it to UTC.
    public static let utc = XLDateModifier("utc")

    // MARK: - Subsecond precision

    ///
    /// Renders fractional seconds in the output of `time`, `datetime`, and
    /// `strftime`. Added in SQLite 3.42.0.
    ///
    public static let subsecond = XLDateModifier("subsec")

    // MARK: - Rendering

    ///
    /// Formats a signed relative offset. SQLite accepts an optional leading
    /// sign; an explicit one is emitted so a positive offset reads the same way
    /// a negative one does.
    ///
    private static func offset(_ count: Int, unit: String) -> XLDateModifier {
        let sign = count < 0 ? "" : "+"
        return XLDateModifier("\(sign)\(count) \(unit)")
    }
}
