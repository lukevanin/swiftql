//
//  DateFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


///
/// The subsecond modifier for the legacy ``unixepoch(date:modifiers:)``
/// constructor.
///
/// New code should prefer the ordered ``XLDateModifier`` surface, which covers
/// the full modifier set and preserves the left-to-right order SQLite applies.
/// This unordered type is retained for source compatibility.
///
public enum XLDateFunctionModifiers: String {

    case subseconds = "subsec"
}


///
/// Converts a date string to a Unix timestamp, applying an unordered set of
/// modifiers.
///
/// New code should prefer ``XLExpression/unixEpoch(_:)``, which takes ordered
/// ``XLDateModifier`` values.
///
public func unixepoch(date: String, modifiers: Set<XLDateFunctionModifiers>) -> some XLExpression<TimeInterval> {
    var parameters: [any XLExpression] = []
    parameters.append(date)
    let sortedModifiers = modifiers.map { $0.rawValue }.sorted()
    for modifier in sortedModifiers {
        parameters.append(modifier)
    }
    return XLFunction(name: "unixepoch", parameters: parameters)
}


extension XLExpression {

    public func toUnixTimestamp() -> some XLExpression<Int> where T == String {
        return XLFunction(name: "unixepoch", parameters: [self])
    }
}


extension XLExpression {

    public func toUnixTimestamp() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        return XLFunction(name: "unixepoch", parameters: [self])
    }
}


// MARK: - Date and time constructors


extension XLExpression {

    ///
    /// Renders the `date(...)` function over this text time value, applying the
    /// modifiers in order. The result is a `YYYY-MM-DD` text expression.
    ///
    public func date(_ modifiers: XLDateModifier...) -> some XLExpression<String> where T == String {
        XLFunction(name: "date", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    ///
    /// Renders the `time(...)` function over this text time value, applying the
    /// modifiers in order. The result is an `HH:MM:SS` text expression.
    ///
    public func time(_ modifiers: XLDateModifier...) -> some XLExpression<String> where T == String {
        XLFunction(name: "time", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    ///
    /// Renders the `datetime(...)` function over this text time value, applying
    /// the modifiers in order. The result is a `YYYY-MM-DD HH:MM:SS` text
    /// expression, so `.months(1)` or `.startOfMonth` compute relative dates.
    ///
    public func datetime(_ modifiers: XLDateModifier...) -> some XLExpression<String> where T == String {
        XLFunction(name: "datetime", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    ///
    /// Renders the `julianday(...)` function over this text time value,
    /// applying the modifiers in order. The result is the fractional number of
    /// days since noon in Greenwich on November 24, 4714 B.C., so subtracting
    /// two `julianDay` expressions yields the number of days between them.
    ///
    public func julianDay(_ modifiers: XLDateModifier...) -> some XLExpression<Double> where T == String {
        XLFunction(name: "julianday", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    ///
    /// Renders the `unixepoch(...)` function over this text time value,
    /// applying the modifiers in order. The result is the number of seconds
    /// since 1970-01-01 00:00:00 UTC. It is a `TimeInterval` rather than an
    /// `Int` because the `.subsecond` modifier makes SQLite return fractional
    /// seconds, which an integer result could not represent.
    ///
    public func unixEpoch(_ modifiers: XLDateModifier...) -> some XLExpression<TimeInterval> where T == String {
        XLFunction(name: "unixepoch", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    ///
    /// Renders the `strftime(format, ...)` function over this text time value,
    /// applying the modifiers in order. The `format` string uses SQLite's
    /// substitution tokens such as `%Y`, `%m`, and `%d`.
    ///
    public func strftime(_ format: String, _ modifiers: XLDateModifier...) -> some XLExpression<String> where T == String {
        XLFunction(name: "strftime", parameters: strftimeParameters(format: format, value: self, modifiers: modifiers))
    }
}


extension XLExpression {

    /// The optional-preserving overload of ``date(_:)``.
    public func date(_ modifiers: XLDateModifier...) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLFunction(name: "date", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    /// The optional-preserving overload of ``time(_:)``.
    public func time(_ modifiers: XLDateModifier...) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLFunction(name: "time", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    /// The optional-preserving overload of ``datetime(_:)``.
    public func datetime(_ modifiers: XLDateModifier...) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLFunction(name: "datetime", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    /// The optional-preserving overload of ``julianDay(_:)``.
    public func julianDay(_ modifiers: XLDateModifier...) -> some XLExpression<Optional<Double>> where T == Optional<String> {
        XLFunction(name: "julianday", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    /// The optional-preserving overload of ``unixEpoch(_:)``.
    public func unixEpoch(_ modifiers: XLDateModifier...) -> some XLExpression<Optional<TimeInterval>> where T == Optional<String> {
        XLFunction(name: "unixepoch", parameters: dateParameters(value: self, modifiers: modifiers))
    }

    /// The optional-preserving overload of ``strftime(_:_:)``.
    public func strftime(_ format: String, _ modifiers: XLDateModifier...) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLFunction(name: "strftime", parameters: strftimeParameters(format: format, value: self, modifiers: modifiers))
    }
}


// MARK: - Date components


extension XLExpression {

    /// The four-digit year (`%Y`) of this text time value.
    public func year() -> some XLExpression<Int> where T == String {
        component("%Y")
    }

    /// The month (`%m`, 1-12) of this text time value.
    public func month() -> some XLExpression<Int> where T == String {
        component("%m")
    }

    /// The day of the month (`%d`, 1-31) of this text time value.
    public func day() -> some XLExpression<Int> where T == String {
        component("%d")
    }

    /// The hour (`%H`, 0-23) of this text time value.
    public func hour() -> some XLExpression<Int> where T == String {
        component("%H")
    }

    /// The minute (`%M`, 0-59) of this text time value.
    public func minute() -> some XLExpression<Int> where T == String {
        component("%M")
    }

    /// The whole second (`%S`, 0-59) of this text time value.
    public func second() -> some XLExpression<Int> where T == String {
        component("%S")
    }

    /// The day of the year (`%j`, 1-366) of this text time value.
    public func dayOfYear() -> some XLExpression<Int> where T == String {
        component("%j")
    }

    /// The day of the week (`%w`, 0 = Sunday ... 6 = Saturday).
    public func dayOfWeek() -> some XLExpression<Int> where T == String {
        component("%w")
    }

    /// The week of the year (`%W`, 00-53) of this text time value.
    public func weekOfYear() -> some XLExpression<Int> where T == String {
        component("%W")
    }
}


extension XLExpression {

    /// The optional-preserving overload of ``year()``.
    public func year() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%Y")
    }

    /// The optional-preserving overload of ``month()``.
    public func month() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%m")
    }

    /// The optional-preserving overload of ``day()``.
    public func day() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%d")
    }

    /// The optional-preserving overload of ``hour()``.
    public func hour() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%H")
    }

    /// The optional-preserving overload of ``minute()``.
    public func minute() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%M")
    }

    /// The optional-preserving overload of ``second()``.
    public func second() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%S")
    }

    /// The optional-preserving overload of ``dayOfYear()``.
    public func dayOfYear() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%j")
    }

    /// The optional-preserving overload of ``dayOfWeek()``.
    public func dayOfWeek() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%w")
    }

    /// The optional-preserving overload of ``weekOfYear()``.
    public func weekOfYear() -> some XLExpression<Optional<Int>> where T == Optional<String> {
        component("%W")
    }
}


// MARK: - Rendering helpers


///
/// Builds the argument list for a date-and-time function: the time value
/// followed by each modifier's rendered text, in order.
///
private func dateParameters(value: any XLExpression, modifiers: [XLDateModifier]) -> [any XLExpression] {
    var parameters: [any XLExpression] = [value]
    for modifier in modifiers {
        parameters.append(modifier.rawValue)
    }
    return parameters
}


///
/// Builds the argument list for `strftime`: the format string, the time value,
/// then each modifier's rendered text, in order.
///
private func strftimeParameters(format: String, value: any XLExpression, modifiers: [XLDateModifier]) -> [any XLExpression] {
    var parameters: [any XLExpression] = [format, value]
    for modifier in modifiers {
        parameters.append(modifier.rawValue)
    }
    return parameters
}


extension XLExpression where T == String {

    ///
    /// Extracts one integer date component with `strftime` and reinterprets the
    /// text result as an integer, so `column.year()` reads as an `Int`.
    ///
    fileprivate func component(_ format: String) -> some XLExpression<Int> {
        XLTypeCastExpression(
            type: "INTEGER",
            expression: XLFunction<String>(name: "strftime", parameters: [format, self])
        )
    }
}


extension XLExpression where T == Optional<String> {

    /// The optional-preserving component extractor. `strftime` returns NULL for
    /// a NULL time value, and `CAST(NULL AS INTEGER)` preserves it.
    fileprivate func component(_ format: String) -> some XLExpression<Optional<Int>> {
        XLTypeCastExpression(
            type: "INTEGER",
            expression: XLFunction<Optional<String>>(name: "strftime", parameters: [format, self])
        )
    }
}
