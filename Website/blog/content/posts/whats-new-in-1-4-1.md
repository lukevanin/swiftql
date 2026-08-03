---
title: "What's new in v1.4.1"
date: 2026-07-22
description: "A patch release that rounds out SwiftQL's expression and aggregate coverage: a unified cast API, typed BETWEEN, whole-row COUNT(*), and broader AVG/TOTAL support."
---

v1.4.1 is a patch release. It adds four small pieces of expression and aggregate coverage, extends the combinatorial SQLite test corpus, and moves the Swift 5.9 compatibility matrix onto a pinned toolchain. No migration is required: every change is additive or confined to continuous integration, and the v1.3 public source and runtime contracts are preserved.

## One cast API instead of four names

Earlier versions of SwiftQL expose a cast as a directional method named for its destination: `toInt()`, `toDouble()`, `toString()`, `toData()`. Each one only exists where SQLite allows that particular conversion, so the compiler still rejects a cast that doesn't make sense, but the method name to reach for changes depending on what you're converting to.

```swift
let priceText = product.price.toString()
let ageDouble = person.age.toDouble()
```

v1.4.1 adds `cast(to:)` as the single entry point across the whole Bool, integer, real, text, data, and optional matrix, and the existing directional helpers now delegate through it:

```swift
let priceText = product.price.cast(to: String.self)
let ageDouble = person.age.cast(to: Double.self)
```

Source nullability still carries through the cast, and a direction SQLite doesn't support is still unavailable at compile time. `toInt()`, `toDouble()`, `toString()`, and `toData()` keep working; they're now thin wrappers over `cast(to:)`.

## Counting every row, including the NULL ones

`count()` on a column counts non-NULL values, which is standard SQL but not always what you want. v1.4.1 adds a typed `all()` expression that renders as an unqualified `*`, so `all().count()` produces `COUNT(*)` and counts every input row regardless of NULLs:

```swift
@SQLResult struct InvoiceStats {
    var invoiceCount: Int
}

let query = sql { schema in
    let invoice = schema.table(Invoice.self)
    Select(InvoiceStats.columns(invoiceCount: all().count()))
    From(invoice)
}
```

## Typed BETWEEN and NOT BETWEEN

`isBetween(_:_:)` and `isNotBetween(_:_:)` add SQLite's inclusive range predicate as typed expressions. The value and both bounds have to share the same comparable SwiftQL type, so a mismatched pair is a compile error rather than a runtime surprise:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age.isBetween(18, 65))
}
```

Bounds can be typed bindings instead of literals:

```swift
let minimumAge = XLNamedBindingReference<Int>(name: "minimumAge")
let maximumAge = XLNamedBindingReference<Int>(name: "maximumAge")

let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.age.isNotBetween(minimumAge, maximumAge))
}
```

or columns from the same row, comparing `measurement.value` against `measurement.minimum` and `measurement.maximum` directly. A nullable operand produces an optional `Bool`, matching SQLite: the predicate evaluates to `NULL` when the value is `NULL`, and a `Where` clause excludes that row the same way it excludes any other `NULL` predicate. Each complete predicate renders grouped, so combining it with `&&`, `||`, or `!` preserves SQLite's precedence rather than relying on the reader to work it out.

## TOTAL, and AVG on more numeric types

`total()` adds SQLite's `TOTAL` aggregate for integer, real, and their nullable forms, always returning a non-optional `Double`. It's a deliberate contrast with `sumOrNull()`: where `sumOrNull()` returns `nil` for an empty or all-NULL input, `total()` returns `0.0`.

```swift
@SQLResult struct RevenueStats {
    var revenueSum: Double?
    var revenueTotal: Double
}

let query = sql { schema in
    let invoice = schema.table(Invoice.self)
    Select(
        RevenueStats.columns(
            revenueSum: invoice.amount.sumOrNull(),
            revenueTotal: invoice.amount.total()
        )
    )
    From(invoice)
}
```

`averageOrNull(distinct:)` is now available on integer expressions and on both nullable numeric forms, not just real ones, and still returns `Double?` and renders as plain `AVG(...)`.

## Hardening the Swift 5.9 compatibility matrix

The two Swift 5.9 compatibility cells in CI move off the retiring `macos-14` runner and onto `ubuntu-22.04`, installing the exact official Swift 5.9.2 archive under pinned detached-signature and signing-key verification, and linking a checksum-verified SQLite 3.53.3 build so an older system SQLite can't silently narrow the conformance surface. The full compatibility build and the complete package test suite still run in both committed- and clean-resolution modes.

Alongside the new APIs, the bounded combinatorial SQLite corpus grew from 141 to 168 cases, adding explicit function, aggregate, JSON, `PRINTF`, and cast coverage, each case still running against a real SQLite engine with an independent raw-SQL semantic oracle.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.4.1 release](https://github.com/lukevanin/swiftql/releases/tag/v1.4.1)
