import Foundation
import SwiftQLCore


/// Named SQLite `TEXT` codecs for Foundation `Date`.
///
/// Every codec built here stores a fixed-width, zero-padded
/// `YYYY-MM-DDTHH:MM:SS[.fff...][Z|±HH:MM]` string derived from a proleptic
/// Gregorian calendar pinned to UTC internally, with only the *rendered*
/// offset controlled by ``XLDateTextFormat``. No formatter, calendar, or time
/// zone is read from process-global or user-default state: every value that
/// affects the encoded bytes is either a fixed constant below or an explicit
/// field on `XLDateTextFormat`.
///
/// ## Storage and indexing
///
/// The standard preset's text is fixed-width (24 bytes: 4-digit year through
/// millisecond precision, `Z` offset) and every field is zero-padded, so
/// SQLite's default `BINARY` text collation orders it identically to
/// chronological order for every date in the supported range. A custom
/// format only preserves that property when it also keeps every field
/// fixed-width and zero-padded with a fixed offset; SwiftQL does not verify
/// this for a caller-supplied format, so treat lexicographic ordering of a
/// custom format as unproven until you have checked it yourself.
///
/// ## Migration
///
/// Changing `fractionalSecondDigits`, `utcOffsetSeconds`, or
/// `usesZuluDesignatorForUTC` changes the bytes this codec produces. Give the
/// new format's codec a new ``XLValueCodecKey`` (or bump the version of an
/// existing one) and migrate stored rows explicitly; SwiftQL never reformats
/// existing text on your behalf.
///
/// ## SQLite date/time functions
///
/// The standard preset's `YYYY-MM-DDTHH:MM:SS.SSSZ` text is one of the
/// time-string formats SQLite's `date`, `time`, `datetime`, `julianday`, and
/// `strftime` functions parse directly, so it can be passed to those
/// functions, and to `<`, `<=`, `>`, `>=`, `BETWEEN`, and `ORDER BY`, without
/// a dialect conversion expression. A custom format built from
/// ``XLDateTextFormat`` stays directly usable as long as it keeps the
/// `YYYY-MM-DDTHH:MM:SS[.SSS][Z|±HH:MM]` field order and separators, which is
/// everything `XLDateTextFormat` can express; it only varies fractional
/// digits and the fixed offset. Wiring an SQL-level `julianday`/`strftime`
/// conversion helper into SwiftQL's expression builders is out of scope for
/// this codec and tracked separately from value coding.
public enum XLDateTextCodec {

    /// The stable Swift-value identity shared by every codec this type
    /// builds. It never changes: the codec key is what distinguishes one
    /// stored representation from another.
    public static let valueTypeIdentifier = XLValueTypeIdentifier(
        rawValue: "swiftql.value.foundation-date"
    )

    /// The standard preset's stable key: UTC, millisecond precision, `Z`
    /// designator. Bump the version, or mint a new id, before changing the
    /// format this key names.
    public static let standardKey = XLValueCodecKey(
        id: "swiftql.codec.date-text.iso8601",
        version: 1
    )

    /// The standard preset's fixed format: UTC, millisecond precision, `Z`.
    public static let standardFormat: XLDateTextFormat = {
        // Fixed literal inputs; this initializer cannot fail for them.
        try! XLDateTextFormat(
            fractionalSecondDigits: 3,
            utcOffsetSeconds: 0,
            usesZuluDesignatorForUTC: true
        )
    }()

    /// The earliest `Date` the standard preset (and any format using its
    /// four-digit year field) can represent: `0001-01-01T00:00:00.000Z`.
    public static let minimumSupportedDate: Date = {
        try! decode(
            "0001-01-01T00:00:00.000Z",
            format: standardFormat,
            context: xlSupportedDateBoundsContext
        )
    }()

    /// The latest `Date` the standard preset (and any format using its
    /// four-digit year field) can represent, truncated to millisecond
    /// precision: `9999-12-31T23:59:59.999Z`.
    public static let maximumSupportedDate: Date = {
        try! decode(
            "9999-12-31T23:59:59.999Z",
            format: standardFormat,
            context: xlSupportedDateBoundsContext
        )
    }()

    /// The versioned, SQLite-compatible standard preset: UTC, millisecond
    /// precision, `Z` designator, canonical zero-padded output.
    ///
    /// Register this codec's key in a database's `defaultCodecKeys` to make
    /// it the database-wide default for `Date`, or select it explicitly with
    /// `XLValueCodecSelection(explicitCodecKey:)` at a call site.
    public static var standard: XLValueCodec<Date, XLSQLiteDialect> {
        custom(
            key: standardKey,
            valueTypeIdentifier: valueTypeIdentifier,
            format: standardFormat
        )
    }

    /// Builds a named, paired Date-as-TEXT codec from an explicit immutable
    /// format.
    ///
    /// Two calls with equal `format` values behave identically; nothing here
    /// depends on `Locale.current`, `TimeZone.current`, or any other
    /// process-local default. Give each distinct `(key, format)` pairing its
    /// own stable `key` — reusing a key for a different format silently
    /// changes what already-stored text means.
    ///
    /// - Parameters:
    ///   - key: The codec's stable, versioned identity.
    ///   - valueTypeIdentifier: The stable identity of the Swift value's
    ///     persisted meaning. Reuse ``valueTypeIdentifier`` so multiple named
    ///     `Date` codecs remain interchangeable database defaults for the
    ///     same conceptual value, distinguished only by `key`.
    ///   - format: The immutable formatting configuration.
    public static func custom(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier = XLDateTextCodec.valueTypeIdentifier,
        format: XLDateTextFormat
    ) -> XLValueCodec<Date, XLSQLiteDialect> {
        XLValueCodec<Date, XLSQLiteDialect>(
            key: key,
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(
                rawValue: XLSQLiteStorageClass.text.rawValue
            ),
            encode: { date, _, context in
                .text(try encode(date, format: format, context: context))
            },
            decode: { value, _, context in
                guard case .text(let text) = value else {
                    throw XLDateTextCodecError.unexpectedStorage(
                        XLValueStorageIdentifier(rawValue: value.storageType.rawValue)
                    )
                }
                return try decode(text, format: format, context: context)
            }
        )
    }

    // MARK: - Encoding

    static func encode(
        _ date: Date,
        format: XLDateTextFormat,
        context: XLValueCodingContext
    ) throws -> String {
        let rawInterval = date.timeIntervalSince1970
        guard rawInterval.isFinite else {
            throw XLDateTextCodecError.unsupportedDate(date)
        }

        // Round to the configured precision, in exact integer "ticks" since
        // the epoch, before extracting calendar fields — instead of
        // truncating a `Double` nanosecond component, or flooring to a whole
        // second when there is no fractional component to display. `Date`
        // stores time as a `Double` count of seconds; at magnitudes far from
        // the epoch the nearest representable `Double` to an "obvious"
        // fractional value (for example `1_700_000_000.123`) already lands a
        // few hundred nanoseconds below it. Rounding to the nearest tick, at
        // whatever precision this format keeps, recovers the intended tick
        // because that residual is far smaller than half a tick. Integer
        // (not floating-point) tick arithmetic keeps the whole-second/
        // fractional-tick split exact and consistently rounded — including
        // carrying a tick that rounds up into the next second, and rounding
        // (not flooring) to the nearest whole second when
        // `fractionalSecondDigits == 0`. See ``XLDateTextFormat`` for the
        // precision/date-range tradeoff this implies.
        let scale = xlPowerOfTen(format.fractionalSecondDigits)
        let scaledInterval = rawInterval * Double(scale)
        guard scaledInterval.isFinite, abs(scaledInterval) < 9e18 else {
            throw XLDateTextCodecError.unsupportedDate(date)
        }
        let totalTicks = Int64(scaledInterval.rounded(.toNearestOrAwayFromZero))
        let scale64 = Int64(scale)
        let (wholeSecondsTicks, fractionTicks64) = xlFloorDivMod(totalTicks, scale64)
        let fractionTicks = Int(fractionTicks64)

        var calendar = xlDateTextCalendar
        calendar.timeZone = xlFixedTimeZone(offsetSeconds: format.utcOffsetSeconds)
        let components = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(wholeSecondsTicks))
        )
        guard
            let era = components.era, era == xlCommonEra,
            let year = components.year, (1...9999).contains(year),
            let month = components.month,
            let day = components.day,
            let hour = components.hour,
            let minute = components.minute,
            let second = components.second
        else {
            throw XLDateTextCodecError.unsupportedDate(date)
        }

        var text = "\(xlZeroPadded(year, width: 4))-\(xlZeroPadded(month, width: 2))-\(xlZeroPadded(day, width: 2))"
        text += "T\(xlZeroPadded(hour, width: 2)):\(xlZeroPadded(minute, width: 2)):\(xlZeroPadded(second, width: 2))"

        if format.fractionalSecondDigits > 0 {
            text += ".\(xlZeroPadded(fractionTicks, width: format.fractionalSecondDigits))"
        }

        text += xlOffsetSuffix(
            offsetSeconds: format.utcOffsetSeconds,
            usesZuluDesignatorForUTC: format.usesZuluDesignatorForUTC
        )
        return text
    }

    // MARK: - Decoding

    static func decode(
        _ text: String,
        format: XLDateTextFormat,
        context: XLValueCodingContext
    ) throws -> Date {
        guard let fields = xlParseDateText(text) else {
            throw XLDateTextCodecError.invalidText(text)
        }
        // A named codec is a deterministic representation: text this codec
        // did not itself produce (a different fractional-digit count or a
        // different fixed offset) is rejected rather than silently accepted,
        // so drift away from the codec's configured format surfaces as a
        // decode error instead of hiding inside a "valid enough" parse.
        guard
            fields.fractionDigitCount == format.fractionalSecondDigits,
            fields.offsetSeconds == format.utcOffsetSeconds
        else {
            throw XLDateTextCodecError.invalidText(text)
        }

        var calendar = xlDateTextCalendar
        calendar.timeZone = xlFixedTimeZone(offsetSeconds: fields.offsetSeconds)

        var components = DateComponents()
        components.year = fields.year
        components.month = fields.month
        components.day = fields.day
        components.hour = fields.hour
        components.minute = fields.minute
        components.second = fields.second
        components.nanosecond = fields.nanosecond

        guard let date = calendar.date(from: components) else {
            throw XLDateTextCodecError.invalidText(text)
        }

        // `Calendar.date(from:)` normalizes out-of-range fields (for example
        // day 32) instead of failing. Re-deriving components from the
        // resulting date and comparing catches that silent normalization so
        // invalid calendar dates are reported, not rounded forward.
        let roundTrip = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard
            roundTrip.year == fields.year,
            roundTrip.month == fields.month,
            roundTrip.day == fields.day,
            roundTrip.hour == fields.hour,
            roundTrip.minute == fields.minute,
            roundTrip.second == fields.second
        else {
            throw XLDateTextCodecError.invalidText(text)
        }

        return date
    }
}


/// The proleptic Gregorian/ISO-8601 "AD"/"CE" era index. A `.year` component
/// alone is ambiguous at the year-1 boundary: one second before
/// `0001-01-01T00:00:00Z` also reports `year == 1`, in era `0` ("BC")
/// instead of era `1`. Checking the era alongside the year is what actually
/// rejects dates before the supported range.
private let xlCommonEra = 1


/// Used only to compute ``XLDateTextCodec/minimumSupportedDate`` and
/// ``XLDateTextCodec/maximumSupportedDate`` at initialization time; never
/// surfaced to a caller.
private let xlSupportedDateBoundsContext = XLValueCodingContext(
    site: .configuration,
    path: XLValueCodingPath("swiftql.date-text.supported-bounds")
)


/// A fixed, locale-independent proleptic Gregorian calendar. `Calendar` is an
/// immutable value type; a mutable local copy (its `timeZone` set per call)
/// is taken from this constant, never shared or mutated concurrently.
private let xlDateTextCalendar: Calendar = {
    var calendar = Calendar(identifier: .iso8601)
    // A fixed zero-second offset is guaranteed to succeed, unlike an
    // identifier lookup, which depends on the platform time zone database
    // containing an entry named "UTC".
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()


/// Compiled once and reused: `NSRegularExpression` performs no internal
/// mutation while matching, so sharing a compiled pattern across calls and
/// threads is safe, unlike a shared `DateFormatter`.
///
/// The `Z`/`±HH:MM` offset suffix is mandatory, not optional: every codec
/// this file builds always renders one (see `xlOffsetSuffix`), and text with
/// no offset at all is genuinely ambiguous about the instant it names rather
/// than merely differently formatted, so it is rejected instead of parsed.
private let xlDateTextPattern: NSRegularExpression = {
    // Fixed, hand-verified literal pattern; this initializer cannot fail.
    try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$"#
    )
}()


private struct XLParsedDateTextFields {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int
    let nanosecond: Int
    /// The number of fractional-second digits actually present in the
    /// parsed text (`0` when there was no `.` component at all), as opposed
    /// to `nanosecond`, which is always zero-padded out to nine digits.
    let fractionDigitCount: Int
    let offsetSeconds: Int
}


private func xlParseDateText(_ text: String) -> XLParsedDateTextFields? {
    let range = NSRange(text.startIndex..., in: text)
    guard let match = xlDateTextPattern.firstMatch(in: text, range: range) else {
        return nil
    }

    func group(_ index: Int) -> String? {
        guard let matchRange = Range(match.range(at: index), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    guard
        let yearText = group(1), let year = Int(yearText),
        let monthText = group(2), let month = Int(monthText),
        let dayText = group(3), let day = Int(dayText),
        let hourText = group(4), let hour = Int(hourText),
        let minuteText = group(5), let minute = Int(minuteText),
        let secondText = group(6), let second = Int(secondText)
    else {
        return nil
    }
    guard year >= 1, (1...12).contains(month), hour < 24, minute < 60, second < 60 else {
        return nil
    }

    var nanosecond = 0
    var fractionDigitCount = 0
    if let fractionText = group(7) {
        let padded = fractionText + String(repeating: "0", count: 9 - fractionText.count)
        guard let parsed = Int(padded) else {
            return nil
        }
        nanosecond = parsed
        fractionDigitCount = fractionText.count
    }

    var offsetSeconds = 0
    if let offsetText = group(8), offsetText != "Z" {
        let sign = offsetText.hasPrefix("-") ? -1 : 1
        let digits = offsetText.dropFirst()
        let hourPart = digits.prefix(2)
        let minutePart = digits.suffix(2)
        guard
            let offsetHour = Int(hourPart),
            let offsetMinute = Int(minutePart),
            offsetHour < 24, offsetMinute < 60
        else {
            return nil
        }
        offsetSeconds = sign * (offsetHour * 3600 + offsetMinute * 60)
    }

    return XLParsedDateTextFields(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        nanosecond: nanosecond,
        fractionDigitCount: fractionDigitCount,
        offsetSeconds: offsetSeconds
    )
}


private func xlFixedTimeZone(offsetSeconds: Int) -> TimeZone {
    // A fixed-offset zone never has a daylight-saving transition, so this
    // always succeeds for the range `XLDateTextFormat` accepts. The fallback
    // is itself a fixed offset (not an identifier lookup) so it carries no
    // platform time zone database dependency either.
    TimeZone(secondsFromGMT: offsetSeconds) ?? TimeZone(secondsFromGMT: 0)!
}


private func xlOffsetSuffix(offsetSeconds: Int, usesZuluDesignatorForUTC: Bool) -> String {
    if offsetSeconds == 0, usesZuluDesignatorForUTC {
        return "Z"
    }
    let sign = offsetSeconds < 0 ? "-" : "+"
    let magnitude = abs(offsetSeconds)
    let hours = magnitude / 3600
    let minutes = (magnitude % 3600) / 60
    return "\(sign)\(xlZeroPadded(hours, width: 2)):\(xlZeroPadded(minutes, width: 2))"
}


private func xlZeroPadded(_ value: Int, width: Int) -> String {
    let text = String(value)
    guard text.count < width else {
        return text
    }
    return String(repeating: "0", count: width - text.count) + text
}


private func xlPowerOfTen(_ exponent: Int) -> Int {
    var result = 1
    for _ in 0 ..< exponent {
        result *= 10
    }
    return result
}


/// Floor division and its matching (always nonnegative, less than
/// `divisor`) remainder, for a positive `divisor`. Swift's built-in `/` and
/// `%` truncate toward zero, which would give a negative pre-epoch tick a
/// negative or wraparound-invalid remainder instead of a valid "ticks into
/// this second" value.
private func xlFloorDivMod(_ value: Int64, _ divisor: Int64) -> (Int64, Int64) {
    let quotient = value / divisor
    let remainder = value % divisor
    guard remainder != 0, (remainder < 0) != (divisor < 0) else {
        return (quotient, remainder)
    }
    return (quotient - 1, remainder + divisor)
}
