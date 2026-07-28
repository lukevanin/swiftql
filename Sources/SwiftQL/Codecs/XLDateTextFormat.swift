import Foundation


/// Deterministic failures raised while encoding or decoding a Date-as-TEXT
/// codec built from ``XLDateTextFormat``.
///
/// These are the errors thrown by the codec's own `encode`/`decode` closures.
/// `XLValueCodec` wraps them with codec identity and coding-path context as
/// `XLValueCodecError.encodingFailed` / `.decodingFailed` before they reach a
/// caller, so this type only needs to describe what went wrong locally.
public enum XLDateTextCodecError: Error, Equatable, Sendable, LocalizedError {

    /// The stored text does not match the fixed grammar this codec parses.
    case invalidText(String)

    /// The dialect value was not the storage class this codec expects.
    case unexpectedStorage(XLValueStorageIdentifier)

    /// Encoding could not produce text for this `Date`: either
    /// `date.timeIntervalSince1970` is not finite, or its proleptic-Gregorian
    /// year (in the codec's fixed offset) falls outside the codec's fixed
    /// four-digit year range (`0001`...`9999`).
    case unsupportedDate(Date)

    /// `XLDateTextFormat` was asked for a fractional-second digit count
    /// outside `0...9`.
    case unsupportedPrecision(fractionalSecondDigits: Int)

    /// `XLDateTextFormat` was asked for a UTC offset that is not a whole
    /// number of minutes strictly between -24h and +24h.
    case unsupportedOffsetSeconds(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidText(let text):
            return "\"\(text)\" does not match the configured Date TEXT grammar."
        case .unexpectedStorage(let storage):
            return "Expected SQLite TEXT storage, received \(storage)."
        case .unsupportedDate(let date):
            return "\(date) is not finite, or falls outside the supported year range 0001...9999."
        case .unsupportedPrecision(let digits):
            return "Fractional-second precision \(digits) is not in 0...9."
        case .unsupportedOffsetSeconds(let seconds):
            return "UTC offset \(seconds) seconds is not a valid fixed offset."
        }
    }
}


/// Explicit, immutable formatting rules for one Date-as-TEXT representation.
///
/// A format never reads `TimeZone.current`, `Locale.current`, or any other
/// process- or user-dependent default: every rule that affects the encoded
/// bytes is a value stored on this struct. Two codecs built from equal
/// formats always produce byte-identical text for the same `Date`.
///
/// The offset is a fixed number of seconds, not a named `TimeZone` identifier.
/// Named zones observe daylight-saving transitions, which would make the same
/// wall-clock offset text mean different instants on different days; a fixed
/// offset keeps the encoded text a deterministic function of the `Date` alone.
public struct XLDateTextFormat: Hashable, Sendable {

    /// Number of fractional-second digits retained in encoded text.
    ///
    /// `0` omits the fractional component and its separating `.` entirely.
    /// Encoding rounds to the nearest tick at this precision (carrying into
    /// the next second when a value rounds up to a full second), rather than
    /// truncating. See ``XLDateTextCodec`` for why rounding, not truncation,
    /// is what makes an ordinary millisecond-resolution `Date` round-trip.
    public let fractionalSecondDigits: Int

    /// The fixed UTC offset, in seconds, embedded in encoded text.
    ///
    /// `0` is UTC. There is no default derived from the running process's
    /// current time zone: callers state the offset their storage format
    /// requires. Must be a whole number of minutes: the encoded `±HH:MM`
    /// suffix can only express minute granularity, so a sub-minute offset
    /// would compute wall-clock fields with a shift the rendered suffix
    /// cannot represent, silently breaking the round trip.
    public let utcOffsetSeconds: Int

    /// Whether an offset of `0` is rendered as the literal `Z` designator
    /// instead of `+00:00`.
    public let usesZuluDesignatorForUTC: Bool

    /// Creates an immutable Date-as-TEXT format.
    ///
    /// - Parameters:
    ///   - fractionalSecondDigits: Digits of fractional-second precision
    ///     retained in encoded text, `0...9`. Defaults to `3` (milliseconds).
    ///   - utcOffsetSeconds: The fixed UTC offset embedded in encoded text,
    ///     strictly between -24h and +24h and a whole number of minutes.
    ///     Defaults to `0` (UTC).
    ///   - usesZuluDesignatorForUTC: Whether a `0`-second offset renders as
    ///     `Z`. Defaults to `true`.
    /// - Throws: ``XLDateTextCodecError/unsupportedPrecision(fractionalSecondDigits:)``
    ///   or ``XLDateTextCodecError/unsupportedOffsetSeconds(_:)`` for values
    ///   outside their supported ranges.
    public init(
        fractionalSecondDigits: Int = 3,
        utcOffsetSeconds: Int = 0,
        usesZuluDesignatorForUTC: Bool = true
    ) throws {
        guard (0...9).contains(fractionalSecondDigits) else {
            throw XLDateTextCodecError.unsupportedPrecision(
                fractionalSecondDigits: fractionalSecondDigits
            )
        }
        guard
            utcOffsetSeconds > -86_400,
            utcOffsetSeconds < 86_400,
            utcOffsetSeconds % 60 == 0
        else {
            throw XLDateTextCodecError.unsupportedOffsetSeconds(utcOffsetSeconds)
        }
        self.fractionalSecondDigits = fractionalSecondDigits
        self.utcOffsetSeconds = utcOffsetSeconds
        self.usesZuluDesignatorForUTC = usesZuluDesignatorForUTC
    }
}
