---
title: "What's new in v1.4.3"
date: 2026-07-23
description: "SwiftQL v1.4.3 adds typed constructors for SQLite's date and time functions, with an ordered modifier type and integer component accessors."
---

SwiftQL v1.4.3 gives text time values a full set of typed constructors for SQLite's date and time functions, replacing the single `unixepoch`-only surface that shipped before.

## Constructors for `date`, `time`, `datetime`, `julianday`, `unixepoch`, and `strftime`

Any `String` or `String?` expression that holds an ISO-8601 time value now has `date`, `time`, `datetime`, `julianDay`, `unixEpoch`, and `strftime` methods. Each takes zero or more `XLDateModifier` values:

```swift
let firstOfNextMonth = sql { _ in
    Select("2026-07-19 12:30:45".datetime(.months(1), .startOfMonth))
}
```

This renders `datetime('2026-07-19 12:30:45', '+1 months', 'start of month')`. SQLite applies modifiers left to right, and the Swift argument order matches, so `.months(1)` followed by `.startOfMonth` reads the same way it evaluates: add a month, then snap to the start of that month.

## `XLDateModifier`

The modifiers themselves are a new ordered type, `XLDateModifier`, covering everything available in SQLite 3.42.0 and later:

- Relative offsets: `.days(_:)`, `.hours(_:)`, `.minutes(_:)`, `.seconds(_:)`, `.months(_:)`, `.years(_:)`, each taking a signed count
- Anchoring: `.startOfDay`, `.startOfMonth`, `.startOfYear`, `.weekday(_:)`
- `.ceiling`, `.floor`, `.localTime`, `.utc`, `.subsecond`

A modifier renders as a quoted string literal, so it can't inject SQL. A few input-interpretation modifiers whose availability varies by SQLite release (`unixepoch`, `julianday`, `auto`) aren't exposed as named members; they stay reachable through `XLDateModifier(_:)` for callers who know their target version:

```swift
date.date(XLDateModifier("unixepoch"))
// date(:date, 'unixepoch')
```

## Date component accessors

`year()`, `month()`, `day()`, `hour()`, `minute()`, `second()`, `dayOfYear()`, `dayOfWeek()`, and `weekOfYear()` extract a single component as an `Int`, reinterpreting the matching `strftime` substitution:

```swift
date.year()
// CAST(strftime('%Y', :date) AS INTEGER)
```

An optional receiver preserves `NULL` throughout — every constructor and component accessor above has a `String?`-in, `T?`-out overload.

Date comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`) and julian-day subtraction (`-`) needed no new operators at all: they reuse the library's existing generic `XLComparable` and floating-point operators over the results of these constructors, since ISO-8601 text already sorts chronologically.

```swift
date.julianDay() - date.julianDay(.days(-1))
// (julianday(:date) - julianday(:date, '-1 days'))
```

## A behavior change: `unixEpoch(_:)` returns `TimeInterval`

The new `unixEpoch(_:)` constructor returns `TimeInterval` rather than `Int`. Once `.subsecond` is in the modifier list, SQLite returns fractional seconds, which an `Int` result can't represent, so the return type has to accommodate the whole modifier surface rather than just the no-modifier case.

This only affects the new spelling. The legacy `unixepoch(date:modifiers:)` function and `toUnixTimestamp()` method are both untouched and keep returning `Int` for their no-modifier case, so existing call sites keep compiling and behaving as before.

## Conformance

The `syntax.expression.date-functions` record in the SQLite conformance inventory moves from `partial` to `supported`, backed by new rendering and real-SQLite execution evidence. That takes the inventory's supported-feature count from 96 to 97 out of 105 tracked records, with evidence records going from 139 to 141.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.4.3 release](https://github.com/lukevanin/swiftql/releases/tag/v1.4.3)
