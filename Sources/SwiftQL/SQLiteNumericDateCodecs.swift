import Foundation


/// Structured failures from SwiftQL's numeric SQLite `Date` codec presets.
///
/// These are distinct from ``XLValueCodecError``: they describe why one of
/// this file's encode or decode closures could not produce a value, before
/// that closure's throw is wrapped as `XLValueCodecError.encodingFailed` or
/// `.decodingFailed` with the active codec key and coding context.
public enum XLSQLiteNumericDateCodecError: Error, Equatable, Sendable, LocalizedError {

    /// `Date.timeIntervalSince1970` was NaN or infinite. SQLite has no exact
    /// numeric representation for a non-finite value, and silently storing
    /// `NULL` or a saturated number would change the caller's value.
    case nonFiniteDate(preset: String, value: XLNonFiniteRealValue)

    /// The millisecond count overflowed `Int64` after rounding. This preset
    /// never truncates or wraps a value that does not fit.
    case millisecondsOutOfRange(preset: String, timeIntervalSince1970: Double)

    /// A stored `REAL` value was NaN or infinite when decoding, or a finite
    /// stored value produced a non-finite result once the preset converted
    /// it back to unix seconds (for example, ``XLSQLiteNumericDateCodec/JulianDay``
    /// decoding a very large but finite julian-day number). SQLite bindings
    /// normalize a NaN parameter to SQL `NULL`, but a computed SQL expression
    /// (for example, an overflowing multiplication) can still produce a
    /// stored non-finite `REAL`.
    case nonFiniteStoredValue(preset: String, value: XLNonFiniteRealValue)

    public var errorDescription: String? {
        switch self {
        case .nonFiniteDate(let preset, let value):
            return "Cannot encode a \(value) Date as \(preset): SQLite has no exact numeric representation for a non-finite value."
        case .millisecondsOutOfRange(let preset, let timeIntervalSince1970):
            return "Cannot encode Date(timeIntervalSince1970: \(timeIntervalSince1970)) as \(preset): the millisecond count overflows Int64."
        case .nonFiniteStoredValue(let preset, let value):
            return "Cannot decode \(preset): the stored REAL is \(value), which is not a finite Date."
        }
    }
}


/// Named, versioned SQLite `NUMERIC` storage presets for Foundation `Date`.
///
/// Each preset is a self-contained ``XLValueCodec`` targeting ``XLSQLiteDialect``.
/// None is installed as an implicit default: register the presets an
/// application actually uses with ``XLValueCodecRegistry/registering(_:)``,
/// then select one explicitly, either as a database/query default via
/// `XLValueCodingConfiguration.defaultCodecKeys` or per parameter/result site
/// via `XLValueCodecSelection`/`XLQueryCodecSelection`. There is no
/// property-level codec selection yet (tracked separately); this file only
/// supports database- and query-level selection.
///
/// Unix seconds, Unix milliseconds, and Julian day are three different
/// numbers for the same instant. Treat a change from one preset to another,
/// on a column that already has rows, as a data migration: rewrite the
/// existing values, don't just swap the codec.
///
/// Companion issue #61 defines a text (`ISO-8601`) SQLite `Date` preset. See
/// <doc:NumericDateCodecs> for a side-by-side comparison and migration notes.
public enum XLSQLiteNumericDateCodec {

    /// The stable Swift-value identity shared by every preset in this file.
    /// It does not participate in codec selection or ambiguity grouping
    /// (that is keyed by the Swift `Date` and `XLSQLiteDialect` types); it is
    /// retained metadata describing what the persisted number means.
    public static let valueTypeIdentifier = XLValueTypeIdentifier(
        rawValue: "com.swiftql.date.numeric"
    )

    /// `Date` stored as a SQLite `INTEGER` count of milliseconds since the
    /// Unix epoch (1970-01-01T00:00:00Z), rounded to the nearest millisecond
    /// (round-half-away-from-zero).
    ///
    /// - Storage class: `INTEGER`.
    /// - Epoch: 1970-01-01T00:00:00Z, i.e. `Date(timeIntervalSince1970: 0)` encodes to `0`.
    /// - Unit: milliseconds.
    /// - Rounding: sub-millisecond fractions of a second round to the nearest
    ///   millisecond; the maximum round-trip error introduced by this preset
    ///   alone is 0.5 ms.
    /// - Precision loss: any precision finer than one millisecond is
    ///   discarded. `Date` itself is backed by a `Double` of seconds, so
    ///   total round-trip error also includes `Double`'s own representation
    ///   error for the input `Date`.
    /// - Range: encoding throws
    ///   ``XLSQLiteNumericDateCodecError/millisecondsOutOfRange(preset:timeIntervalSince1970:)``
    ///   if the rounded millisecond count does not fit in `Int64`
    ///   (approximately ±292,471,208 years from the epoch); this is far
    ///   outside any date `Foundation` treats as meaningful.
    /// - Ordering: numeric `INTEGER` ordering matches chronological ordering,
    ///   including negative values for dates before the epoch.
    /// - Indexing: a standard SQLite index on this column sorts correctly
    ///   with no zero-padding or fixed-width formatting required, unlike a
    ///   text preset.
    /// - Non-finite input: encoding a `Date` whose `timeIntervalSince1970` is
    ///   NaN or infinite throws
    ///   ``XLSQLiteNumericDateCodecError/nonFiniteDate(preset:value:)``.
    /// - Storage-class coercion: decoding a value SQLite did not store as
    ///   `INTEGER` (for example, because the destination column's declared
    ///   type affinity let a `REAL` or `TEXT` value through) throws
    ///   `XLValueCodecError.storageMismatch` before this preset's decode
    ///   closure runs. Declare the destination column `INTEGER` to avoid
    ///   affinity-driven coercion.
    public enum UnixMilliseconds {

        public static let key = XLValueCodecKey(
            id: "com.swiftql.date.unix-milliseconds",
            version: 1
        )

        public static let storageIdentifier = XLValueStorageIdentifier(
            rawValue: XLSQLiteStorageClass.integer.rawValue
        )

        public static let codec: XLValueCodec<Date, XLSQLiteDialect> = XLValueCodec(
            key: key,
            valueTypeIdentifier: XLSQLiteNumericDateCodec.valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storageIdentifier,
            encode: { date, _, _ in
                let seconds = date.timeIntervalSince1970
                guard let nonFinite = XLNonFiniteRealValue(seconds) else {
                    let roundedMilliseconds = (seconds * 1000)
                        .rounded(.toNearestOrAwayFromZero)
                    guard let milliseconds = Int64(exactly: roundedMilliseconds) else {
                        throw XLSQLiteNumericDateCodecError.millisecondsOutOfRange(
                            preset: key.id,
                            timeIntervalSince1970: seconds
                        )
                    }
                    return .integer(milliseconds)
                }
                throw XLSQLiteNumericDateCodecError.nonFiniteDate(
                    preset: key.id,
                    value: nonFinite
                )
            },
            decode: { value, _, _ in
                guard case .integer(let milliseconds) = value else {
                    // Unreachable: `XLValueCodec.decode` already validated the
                    // storage class matches `storageIdentifier` before this
                    // closure runs. A domain error here would misrepresent
                    // what actually happened, so fail loudly on the broken
                    // invariant instead.
                    preconditionFailure(
                        "\(key) decode received a non-integer value after storage validation."
                    )
                }
                return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            }
        )
    }

    /// `Date` stored as a SQLite `REAL` count of seconds since the Unix epoch
    /// (1970-01-01T00:00:00Z) — the same value `Date.timeIntervalSince1970`
    /// returns.
    ///
    /// - Storage class: `REAL`.
    /// - Epoch: 1970-01-01T00:00:00Z, i.e. `Date(timeIntervalSince1970: 0)` encodes to `0.0`.
    /// - Unit: seconds, with the full fractional (subsecond) precision a
    ///   `Double` carries.
    /// - Rounding: none. The `Double` seconds value is stored as-is.
    /// - Precision loss: SQLite's `REAL` is an IEEE 754 double, the same
    ///   representation `Date` uses internally, so this preset introduces no
    ///   additional loss beyond `Double`'s own ~15-17 significant decimal
    ///   digits; round-trip error is at the unit-in-the-last-place level and
    ///   grows slowly as magnitude grows further from the epoch.
    /// - Range: any finite `Double` seconds value is representable; there is
    ///   no overflow case for this preset.
    /// - Ordering: numeric `REAL` ordering matches chronological ordering,
    ///   including negative values for dates before the epoch.
    /// - Indexing: a standard SQLite index on this column sorts correctly
    ///   with no zero-padding or fixed-width formatting required, unlike a
    ///   text preset.
    /// - Non-finite input: encoding a `Date` whose `timeIntervalSince1970` is
    ///   NaN or infinite throws
    ///   ``XLSQLiteNumericDateCodecError/nonFiniteDate(preset:value:)``. This
    ///   also protects against SQLite's own binding behavior, which would
    ///   otherwise normalize a bound NaN to SQL `NULL`.
    /// - Storage-class coercion: decoding a value SQLite did not store as
    ///   `REAL` throws `XLValueCodecError.storageMismatch` before this
    ///   preset's decode closure runs. Declare the destination column `REAL`
    ///   to avoid affinity-driven coercion (an `INTEGER`-affinity column can
    ///   silently store a whole-number `REAL` as `INTEGER`).
    public enum UnixSeconds {

        public static let key = XLValueCodecKey(
            id: "com.swiftql.date.unix-seconds",
            version: 1
        )

        public static let storageIdentifier = XLValueStorageIdentifier(
            rawValue: XLSQLiteStorageClass.real.rawValue
        )

        public static let codec: XLValueCodec<Date, XLSQLiteDialect> = XLValueCodec(
            key: key,
            valueTypeIdentifier: XLSQLiteNumericDateCodec.valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storageIdentifier,
            encode: { date, _, _ in
                let seconds = date.timeIntervalSince1970
                if let nonFinite = XLNonFiniteRealValue(seconds) {
                    throw XLSQLiteNumericDateCodecError.nonFiniteDate(
                        preset: key.id,
                        value: nonFinite
                    )
                }
                return .real(seconds)
            },
            decode: { value, _, _ in
                guard case .real(let seconds) = value else {
                    // Unreachable: storage class is validated before this
                    // closure runs. A domain error here would misrepresent
                    // what actually happened, so fail loudly on the broken
                    // invariant instead.
                    preconditionFailure(
                        "\(key) decode received a non-real value after storage validation."
                    )
                }
                if let nonFinite = XLNonFiniteRealValue(seconds) {
                    throw XLSQLiteNumericDateCodecError.nonFiniteStoredValue(
                        preset: key.id,
                        value: nonFinite
                    )
                }
                return Date(timeIntervalSince1970: seconds)
            }
        )
    }

    /// `Date` stored as a SQLite `REAL` Julian day number, using the same
    /// linear relationship SQLite's own `julianday()` function uses:
    /// `julianDay = unixSeconds / 86400.0 + 2440587.5`.
    ///
    /// - Storage class: `REAL`.
    /// - Epoch: the Julian day count itself is astronomical (day 0 is
    ///   -4713-11-24T12:00:00Z, proleptic Gregorian); `2440587.5` is the
    ///   Julian day number of the Unix epoch, so
    ///   `Date(timeIntervalSince1970: 0)` encodes to `2440587.5`.
    /// - Unit: days, with a fractional part for the time of day.
    /// - Rounding: none. The computed `Double` is stored as-is.
    /// - Precision loss: adding the `2440587.5` day offset consumes several
    ///   bits of the `Double` mantissa that would otherwise represent
    ///   sub-day precision, so this preset loses more precision than
    ///   ``UnixSeconds`` for the same input, on the order of microseconds
    ///   near the present day. It matches the numeric convention `julianday()`
    ///   already uses, which is the point of choosing it.
    /// - Range: encoding accepts any finite `Double` seconds value (the
    ///   corresponding julian-day number never overflows a `Double`).
    ///   Decoding is narrower: converting a stored julian-day number back to
    ///   unix seconds multiplies by 86,400, so a stored value large enough to
    ///   overflow that multiplication throws
    ///   ``XLSQLiteNumericDateCodecError/nonFiniteStoredValue(preset:value:)``
    ///   rather than returning a `Date` backed by a non-finite time interval.
    ///   This bound is far outside any date a real application would store.
    /// - Ordering: numeric `REAL` ordering matches chronological ordering.
    ///   Julian day numbers for real-world dates stay positive; only dates
    ///   before -4713-11-24 would produce a negative value.
    /// - Indexing: a standard SQLite index on this column sorts correctly
    ///   with no zero-padding or fixed-width formatting required, unlike a
    ///   text preset.
    /// - Non-finite input: encoding a `Date` whose `timeIntervalSince1970` is
    ///   NaN or infinite throws
    ///   ``XLSQLiteNumericDateCodecError/nonFiniteDate(preset:value:)``.
    /// - Storage-class coercion: decoding a value SQLite did not store as
    ///   `REAL` throws `XLValueCodecError.storageMismatch` before this
    ///   preset's decode closure runs.
    public enum JulianDay {

        /// The Julian day number of the Unix epoch (1970-01-01T00:00:00Z).
        public static let unixEpochJulianDay: Double = 2_440_587.5

        /// The number of seconds in one day, used to convert between Unix
        /// seconds and a fractional Julian day count.
        public static let secondsPerDay: Double = 86_400

        public static let key = XLValueCodecKey(
            id: "com.swiftql.date.julian-day",
            version: 1
        )

        public static let storageIdentifier = XLValueStorageIdentifier(
            rawValue: XLSQLiteStorageClass.real.rawValue
        )

        public static let codec: XLValueCodec<Date, XLSQLiteDialect> = XLValueCodec(
            key: key,
            valueTypeIdentifier: XLSQLiteNumericDateCodec.valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: storageIdentifier,
            encode: { date, _, _ in
                let seconds = date.timeIntervalSince1970
                if let nonFinite = XLNonFiniteRealValue(seconds) {
                    throw XLSQLiteNumericDateCodecError.nonFiniteDate(
                        preset: key.id,
                        value: nonFinite
                    )
                }
                let julianDay = seconds / secondsPerDay + unixEpochJulianDay
                if let nonFinite = XLNonFiniteRealValue(julianDay) {
                    throw XLSQLiteNumericDateCodecError.nonFiniteDate(
                        preset: key.id,
                        value: nonFinite
                    )
                }
                return .real(julianDay)
            },
            decode: { value, _, _ in
                guard case .real(let julianDay) = value else {
                    // Unreachable: storage class is validated before this
                    // closure runs. A domain error here would misrepresent
                    // what actually happened, so fail loudly on the broken
                    // invariant instead.
                    preconditionFailure(
                        "\(key) decode received a non-real value after storage validation."
                    )
                }
                if let nonFinite = XLNonFiniteRealValue(julianDay) {
                    throw XLSQLiteNumericDateCodecError.nonFiniteStoredValue(
                        preset: key.id,
                        value: nonFinite
                    )
                }
                let seconds = (julianDay - unixEpochJulianDay) * secondsPerDay
                // The stored julian-day REAL was finite, but converting a
                // sufficiently large finite value back to unix seconds can
                // still overflow to infinity. Fail structurally instead of
                // returning a Date backed by a non-finite time interval.
                if let nonFinite = XLNonFiniteRealValue(seconds) {
                    throw XLSQLiteNumericDateCodecError.nonFiniteStoredValue(
                        preset: key.id,
                        value: nonFinite
                    )
                }
                return Date(timeIntervalSince1970: seconds)
            }
        )
    }
}


extension XLValueCodecRegistry {

    /// Registers every numeric SQLite `Date` preset defined by
    /// ``XLSQLiteNumericDateCodec``: ``XLSQLiteNumericDateCodec/UnixMilliseconds``,
    /// ``XLSQLiteNumericDateCodec/UnixSeconds``, and
    /// ``XLSQLiteNumericDateCodec/JulianDay``.
    ///
    /// This is a convenience for applications that want every preset
    /// available for explicit per-database, per-query, or per-parameter
    /// selection. It never adds a default: none of these presets becomes the
    /// implicit codec for `Date` just by being registered. Pass one preset's
    /// key in `defaultCodecKeys`, or select a preset explicitly with
    /// `XLValueCodecSelection`/`XLQueryCodecSelection`, before encoding or
    /// decoding a `Date` without an explicit selector.
    public func registeringSQLiteNumericDateCodecs() throws -> Self {
        try self
            .registering(XLSQLiteNumericDateCodec.UnixMilliseconds.codec)
            .registering(XLSQLiteNumericDateCodec.UnixSeconds.codec)
            .registering(XLSQLiteNumericDateCodec.JulianDay.codec)
    }
}
