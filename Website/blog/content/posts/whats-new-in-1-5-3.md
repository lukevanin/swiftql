---
title: "What's new in v1.5.3"
date: 2026-07-28
description: "v1.5.3 adds five SQLite value-codec presets, Date/JSON/UUID, and a per-property @SQLCodec attribute, all built on the existing v1.2 codec registry with no required migration."
---

v1.5.3 adds five codec presets and a property-level attribute macro, all built on the contextual value-codec registry that shipped in v1.2 (#188). Nothing in this release changes an existing public API, a persisted representation, or codec-selection precedence, so no migration is required to pick it up.

## `@SQLCodec`: two properties, two conventions, one type

Before this release, giving two properties of the same Swift type different storage conventions meant either two wrapper types or a codec key repeated by hand at every call site. `@SQLCodec(key)` (#66) puts the choice on the property itself:

```swift
@SQLTable
struct InvoiceRecord: Equatable {
    let id: Int

    @SQLCodec(decimalDateCodecKey)
    let filedAt: Date

    @SQLCodec(integerDateCodecKey)
    let reviewedAt: Date
}
```

`filedAt` and `reviewedAt` are both `Date`. The attribute does not wrap either property, and it does not touch `InvoiceRecord`'s Swift type, its memberwise initializer, or its `Equatable`/`Codable` conformance. It emits the codec key as metadata: a `_swiftQLPropertyCodecKeys` dictionary keyed by column name, plus a generated `staticResultField(...)` convenience per annotated property that already supplies `selection: .explicit(key)`. Callers building a `staticRowLayout` never repeat the key by hand. Selection still resolves through the same explicit/query/default precedence v1.2 established; `@SQLCodec` only supplies the "explicit" input at one more site.

## JSON columns via `XLJSONValueCodec`

SQLite has no native JSON column type, so `XLJSONValueCodec` (#65) is a factory that converts an application `Codable` value to `TEXT` or `BLOB` bytes:

```swift
struct CustomerProfile: Codable, Equatable {
    var name: String
    var tags: [String]
    var address: ContactAddress?
    var contact: ContactMethod
    var loyaltyPoints: Int
}

let profileTextCodec = XLJSONValueCodec.text(
    key: profileTextKey,
    valueTypeIdentifier: profileType
) as XLValueCodec<CustomerProfile, XLSQLiteDialect>

let profileBlobCodec = XLJSONValueCodec.blob(
    key: profileBlobKey,
    valueTypeIdentifier: profileType
) as XLValueCodec<CustomerProfile, XLSQLiteDialect>
```

Each call to `XLJSONCodecConfiguration` snapshots the relevant `JSONEncoder`/`JSONDecoder` strategies (key and date encoding, key sorting) once, as an immutable `Sendable` value. There is no shared encoder or decoder instance and no process-global JSON configuration to synchronize. `TEXT` and `BLOB` are distinct, non-interchangeable storage identities for the same `Codable` type, so registering both and later choosing the wrong one for a stored column fails with `XLValueCodecError.storageMismatch` rather than silently reinterpreting the bytes. Malformed or incompatible data raises a structured `XLValueCodecError` wrapping the underlying `EncodingError`/`DecodingError`, never a default value.

## Three numeric `Date` presets

`XLSQLiteNumericDateCodec` (#62) adds three named presets for storing `Date` as a SQLite number instead of text:

```swift
let numericDateRegistry = try XLValueCodecRegistry()
    .registeringSQLiteNumericDateCodecs()
let numericDateCoding = try XLValueCodingConfiguration(
    registry: numericDateRegistry
)

let loggedAt = Date(timeIntervalSince1970: 1_700_000_000.25)

try numericDateCoding.encode(
    loggedAt, using: dialect, context: context,
    selection: XLValueCodecSelection(
        explicitCodecKey: XLSQLiteNumericDateCodec.UnixMilliseconds.key
    )
)
// .integer(1_700_000_000_250)
```

`UnixMilliseconds` stores an `INTEGER` rounded to the nearest millisecond and rejects values that would overflow `Int64`. `UnixSeconds` stores a `REAL` equal to `Date.timeIntervalSince1970` as-is. `JulianDay` stores a `REAL` using the same linear relationship SQLite's own `julianday()` function uses. None of the three is an implicit default: encoding a `Date` without an explicit selector or a registered database default throws `.ambiguousCodec`. Every preset rejects a non-finite `Date` at encode time and a non-finite stored `REAL` at decode time with a structured error.

## `XLDateTextCodec`: a standard `Date`-as-`TEXT` preset

`XLDateTextCodec` (#61) covers the case most applications previously hand-wrote: a versioned, SQLite-compatible `Date`-as-`TEXT` codec.

```swift
let standardDateRegistry = try XLValueCodecRegistry()
    .registering(XLDateTextCodec.standard)
let standardDateCoding = try XLValueCodingConfiguration(
    registry: standardDateRegistry,
    defaultCodecKeys: [XLDateTextCodec.standardKey]
)

try standardDateCoding.encode(
    Date(timeIntervalSince1970: 1_700_000_000.123),
    using: XLSQLiteDialect(),
    context: context
)
// .text("2023-11-14T22:13:20.123Z")
```

The standard preset fixes the proleptic-Gregorian calendar, UTC offset, and millisecond fractional precision, and produces a `Z`-suffixed `YYYY-MM-DDTHH:MM:SS.SSSZ` string that SQLite's `date`/`time`/`datetime`/`julianday`/`strftime` functions and comparison operators already parse, without a dialect conversion expression. Because the text is fixed-width and zero-padded, SQLite's default `BINARY` collation orders it the same as chronological order for every year in the supported range, `0001` through `9999`. A `Date` outside that range fails to encode with a structured error rather than being silently clamped. Applications that need a different fixed offset or fractional precision, but not a different locale or calendar, build a named codec from an explicit `XLDateTextFormat` with `XLDateTextCodec.custom(key:format:)` instead of writing encode/decode closures by hand.

## UUID text and blob presets

`XLUUIDValueCodec.text` and `.blob` (#192) mean `UUID` never needs an application-owned wrapper or a hand-written codec:

```swift
let uuidRegistry = try XLValueCodecRegistry()
    .registering(XLUUIDValueCodec.text)
    .registering(XLUUIDValueCodec.blob)
let uuidCoding = try XLValueCodingConfiguration(registry: uuidRegistry)

let publicID = try uuidCodecDatabase.contextualBinding(
    UUID.self,
    expressedAs: String.self,
    named: "publicID",
    selection: XLValueCodecSelection(
        explicitCodecKey: XLUUIDValueCodec.text.identity.key
    )
)
```

`.text` stores the canonical lowercase hyphenated string; `.blob` stores the canonical 16-byte RFC 4122 binary layout. Both target the same `(UUID, sqlite)` value/dialect pair, so they always agree on equality (case-insensitive text decode, canonicalized lowercase encode), but they can never both be installed as the database default at once, and they sort differently: `.text` orders by lexicographic byte order over the hyphenated string, `.blob` by byte order over the raw RFC 4122 bytes, and neither matches UUID creation order. Malformed input, invalid text, or a `BLOB` of the wrong length surfaces as a structured `XLUUIDValueCodecError` carrying codec and property context.

## What's out of scope for this release

The changelog is explicit about three boundaries. `@SQLCodec` selects among codecs already registered with the configuration passed to `staticResultField`; it does not register one itself, so an unregistered key fails the same way an explicit selection fails elsewhere. The numeric and text `Date` codecs stay in the value-coding layer and add no SQL-level `julianday`/`strftime` expression-builder helper. And PostgreSQL's native `UUID`/`JSONB`/timestamp mappings, tracked separately as #137, are untouched: these five presets are SQLite-specific, and a future PostgreSQL dialect module will supply its own mapping for the same Swift domain types without changing anything added here.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.5.3 release](https://github.com/lukevanin/swiftql/releases/tag/v1.5.3)
