# Numeric Date Codecs

Store Foundation `Date` values as SQLite `INTEGER` or `REAL` numbers.

## Overview

<doc:CustomTypes> introduces the v1.2 contextual value-codec API with a small,
doc-only `Date` example. This article documents three named, versioned,
production `Date` presets that SwiftQL ships for `XLSQLiteDialect`, all
defined in `XLSQLiteNumericDateCodec`:

- ``XLSQLiteNumericDateCodec/UnixMilliseconds``: `INTEGER` milliseconds since
  the Unix epoch.
- ``XLSQLiteNumericDateCodec/UnixSeconds``: `REAL` seconds since the Unix
  epoch (the same value `Date.timeIntervalSince1970` returns).
- ``XLSQLiteNumericDateCodec/JulianDay``: `REAL` Julian day number, using the
  same linear relationship SQLite's own `julianday()` function uses.

None of the three is installed as an implicit default. Property-level codec
selection (choosing a codec per table column without repeating a selector at
every call site) is tracked separately and is not available yet; select a
preset at the database level (`defaultCodecKeys`) or explicitly per parameter
and result site with `XLValueCodecSelection`.

A companion preset for storing `Date` as SQLite `TEXT` (ISO-8601) is tracked
separately. See <doc:CustomTypes> for the general contextual-codec API this
article builds on.

## Choose a preset

Unix seconds, Unix milliseconds, and Julian day are three different numbers
for the same instant. Register only the presets an application actually uses,
and treat switching a column from one preset to another as a data migration,
not a configuration change:

<!-- test: XLDocumentationTests.testDocumentationNumericDateCodecs -->
```swift
import Foundation
import SwiftQL

let numericDateRegistry = try XLValueCodecRegistry()
    .registeringSQLiteNumericDateCodecs()
let numericDateCoding = try XLValueCodingConfiguration(
    registry: numericDateRegistry
)
```

`registeringSQLiteNumericDateCodecs()` registers all three presets without
picking a default, so encoding or decoding a `Date` still requires an
explicit selector:

<!-- test: XLDocumentationTests.testDocumentationNumericDateCodecs -->
```swift
let numericDialect = XLSQLiteDialect()
let numericDateContext = XLValueCodingContext(
    site: .parameter,
    path: XLValueCodingPath("event.loggedAt")
)

do {
    _ = try numericDateCoding.encode(
        Date(timeIntervalSince1970: 0),
        using: numericDialect,
        context: numericDateContext
    )
} catch let error as XLValueCodecError {
    // .ambiguousCodec: three registered presets, no default, no selector.
    print(error)
}
```

Select one preset explicitly, either per call:

<!-- test: XLDocumentationTests.testDocumentationNumericDateCodecs -->
```swift
let loggedAt = Date(timeIntervalSince1970: 1_700_000_000.25)

let millisecondsValue = try numericDateCoding.encode(
    loggedAt,
    using: numericDialect,
    context: numericDateContext,
    selection: XLValueCodecSelection(
        explicitCodecKey: XLSQLiteNumericDateCodec.UnixMilliseconds.key
    )
)
// .integer(1_700_000_000_250)

let secondsValue = try numericDateCoding.encode(
    loggedAt,
    using: numericDialect,
    context: numericDateContext,
    selection: XLValueCodecSelection(
        explicitCodecKey: XLSQLiteNumericDateCodec.UnixSeconds.key
    )
)
// .real(1_700_000_000.25)

let julianDayValue = try numericDateCoding.encode(
    loggedAt,
    using: numericDialect,
    context: numericDateContext,
    selection: XLValueCodecSelection(
        explicitCodecKey: XLSQLiteNumericDateCodec.JulianDay.key
    )
)
// .real(19675231.483622685...)
```

or once for an entire database, by listing exactly one preset's key in
`defaultCodecKeys`:

<!-- test: XLDocumentationTests.testDocumentationNumericDateCodecs -->
```swift
let secondsOnlyRegistry = try XLValueCodecRegistry()
    .registering(XLSQLiteNumericDateCodec.UnixSeconds.codec)
let secondsOnlyCoding = try XLValueCodingConfiguration(
    registry: secondsOnlyRegistry,
    defaultCodecKeys: [XLSQLiteNumericDateCodec.UnixSeconds.key]
)
let defaultEncodedSeconds = try secondsOnlyCoding.encode(
    loggedAt,
    using: numericDialect,
    context: numericDateContext
)
// .real(1_700_000_000.25), no selector required
```

Two numeric presets can coexist in the same schema; each column keeps its own
codec identity, selected explicitly at that column's parameter and result
sites, exactly as the two-codec example in <doc:CustomTypes> shows for the
doc-only `Date` codec.

### Storage, precision, and range

| Preset | Storage | Epoch | Unit | Rounding | Range |
|---|---|---|---|---|---|
| `UnixMilliseconds` | `INTEGER` | 1970-01-01T00:00:00Z → `0` | milliseconds | nearest ms, round-half-away-from-zero | throws past `Int64` millisecond overflow (≈ ±292,471,208 years) |
| `UnixSeconds` | `REAL` | 1970-01-01T00:00:00Z → `0.0` | seconds | none | any finite `Double` |
| `JulianDay` | `REAL` | 1970-01-01T00:00:00Z → `2440587.5` | fractional days | none | any finite `Double` |

`UnixMilliseconds` loses sub-millisecond precision by design (maximum 0.5 ms
round-trip error from rounding alone). `UnixSeconds` is nearly lossless: its
`REAL` storage is the same IEEE 754 double `Date` already uses internally, so
round-trip error stays at the unit-in-the-last-place level. `JulianDay` loses
more precision than `UnixSeconds` for the same instant, because adding the
`2440587.5` day offset consumes mantissa bits that would otherwise represent
sub-day precision — that cost buys direct compatibility with `julianday()`,
covered below.

All three presets store `Date` as a native SQLite number, so a standard index
on the column sorts in chronological order with no zero-padding or
fixed-width formatting, unlike a text preset (see
[Comparison with the text preset](#comparison-with-the-text-preset)).

### Non-finite, overflow, and malformed values

Every preset rejects a non-finite `Date` (`timeIntervalSince1970` is NaN or
infinite) at encode time, and rejects a non-finite stored `REAL` at decode
time, with a structured
``XLSQLiteNumericDateCodecError/nonFiniteDate(preset:value:)`` or
``XLSQLiteNumericDateCodecError/nonFiniteStoredValue(preset:value:)``
wrapped as `XLValueCodecError.encodingFailed`/`.decodingFailed`.
`UnixMilliseconds` additionally rejects a millisecond count that would
overflow `Int64` with
``XLSQLiteNumericDateCodecError/millisecondsOutOfRange(preset:timeIntervalSince1970:)``.
None of the three presets truncates, saturates, or silently changes a value
that does not fit.

A value SQLite stored under a different storage class than the selected
preset declares — for example, `TEXT` that a mismatched or absent column
affinity let through into a column meant for `UnixMilliseconds` — fails with
`XLValueCodecError.storageMismatch` before that preset's decode closure runs.
Declare each destination column with the exact matching SQLite type
(`INTEGER` for `UnixMilliseconds`, `REAL` for `UnixSeconds` and `JulianDay`)
to avoid affinity-driven coercion in the first place.

## SQLite date/time-function interoperability

Each preset's stored number relates to SQLite's `julianday()`/`datetime()`
family differently, and interoperating with them uses ordinary SQL
expressions — no additional codec machinery:

`JulianDay` stores exactly the numeric convention `date()`/`datetime()`
already expect for a bare `REAL` argument, so no modifier is needed:

```sql
SELECT datetime(dueDateJulianDay), date(dueDateJulianDay) FROM invoice;
```

`UnixSeconds` needs the `'unixepoch'` modifier, since SQLite's date functions
otherwise treat a bare numeric argument as a Julian day number, not Unix
seconds:

```sql
SELECT datetime(loggedAtSeconds, 'unixepoch') FROM event;
```

`UnixMilliseconds` needs both a conversion to seconds and the `'unixepoch'`
modifier:

```sql
SELECT datetime(loggedAtMilliseconds / 1000.0, 'unixepoch') FROM event;
```

## Comparison with the text preset

A companion ISO-8601 `TEXT` preset (tracked separately) stores `Date` as a
formatted string. The numeric presets in this article trade that format's
human readability for properties a `TEXT` column does not get for free:

- **Ordering**: a numeric column sorts chronologically using SQLite's normal
  numeric comparison. A `TEXT` column sorts chronologically only if every
  stored string uses the same fixed-width, zero-padded format; an
  inconsistently formatted string column produces lexicographic, not
  chronological, order.
- **Indexing**: the same numeric-vs-lexicographic distinction applies to any
  index built on the column.
- **Interoperability**: `julianday()`/`datetime()` consume a numeric column
  directly (`JulianDay` needs no modifier at all; `UnixSeconds` and
  `UnixMilliseconds` need the modifiers shown above). A `TEXT` column needs
  its stored format to be one SQLite's date parser already recognizes.
- **Storage size**: an `INTEGER` or `REAL` value is typically smaller on disk
  than a formatted date-time string.

Migrating an existing column between the text preset and a numeric preset, or
between two numeric presets, is a data migration: rewrite every stored value
under the new codec's rules, and do not select the new codec for a column
that still holds values encoded under the old one. The presets' distinct
`XLValueCodecKey`s exist so that kind of mismatch fails structurally
(`XLValueCodecError.storageMismatch` or a decode failure) instead of being
silently misinterpreted.
