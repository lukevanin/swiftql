---
title: "What's new in v1.4.5"
date: 2026-07-24
description: "SwiftQL v1.4.5 rounds out join coverage with NATURAL, USING, RIGHT, and FULL OUTER JOIN, adds MATERIALIZED hints and scalar common table expressions, and drops the XLResult requirement from compound queries."
---

SwiftQL v1.4.5 rounds out two areas that were previously incomplete: join coverage and common table expressions. Every change in this release is additive, so existing queries compile and render unchanged.

## Every SQL join form

Earlier versions covered `INNER` and `LEFT JOIN`. This release adds `NATURAL JOIN`, `USING (columns...)`, `RIGHT JOIN`, and `FULL OUTER JOIN`, plus completes `CROSS JOIN` coverage on `QueryBuilder`.

`NATURAL JOIN` needs no `ON` or `USING` clause at all:

```swift
let statement = sql { schema in
    let passport = schema.table(PassportTable.self)
    let citizen = schema.table(CitizenTable.self)
    Select(PassportCitizenRow.columns(name: citizen.fullName, country: passport.country))
    From(passport)
    Join.Natural(citizen)
}
```

`USING` takes a column list instead of a boolean expression:

```swift
Join.Inner(citizen, using: "id")
```

`RIGHT JOIN` keeps the joined (right-hand) table non-nullable and instead makes the `FROM` table optional, since a right join can produce a `FROM` row with no match. That means the `FROM` table has to be declared with `schema.nullableTable`:

```swift
let statement = sql { schema in
    let company = schema.nullableTable(CompanyTable.self)
    let employee = schema.table(EmployeeTable.self)
    Select(RightJoinRow.columns(company: company.name, employee: employee.name))
    From(company)
    Join.Right(employee, on: employee.companyId == company.id)
}
```

`FULL OUTER JOIN` needs both sides nullable, unlike `LEFT` or `RIGHT JOIN`, where only one side is:

```swift
let company = schema.nullableTable(CompanyTable.self)
let employee = schema.nullableTable(EmployeeTable.self)
Select(FullOuterRow.columns(company: company.name, employee: employee.name))
From(company)
Join.FullOuter(employee, on: employee.companyId == company.id)
```

`RIGHT JOIN` and `FULL OUTER JOIN` require SQLite 3.39.0 (2022-06) or later, since that's the SQLite version that added them. The previously broken `Join.Outer`, which rendered an invalid bare `OUTER JOIN`, stays removed in favor of `Join.Left` and `Join.FullOuter`.

## MATERIALIZED hints on common table expressions

`XLSchema.commonTable` and its recursive counterparts now take a `materialization` parameter:

```swift
let cte = schema.commonTable(materialization: .materialized) { s in
    let company = s.table(CompanyTable.self)
    return select(company).from(company)
}
```

That renders `WITH cte0 AS MATERIALIZED (...)`. Leaving the parameter out keeps the previous `alias AS (...)` form, so no existing call site needs to change.

## Scalar common table expressions without a wrapper type

Before this release, a CTE that produces a single scalar column still needed a one-property `@SQLResult` struct to carry it. `scalarCommonTable` and `scalarCommonTableExpression` remove that requirement:

```swift
let statement = sql { schema in
    let cte = schema.scalarCommonTableExpression(Int.self) { inner in
        let number = inner.table(NumberRow.self)
        Select(number.value)
        From(number)
    }
    let output = schema.table(cte)
    With(cte)
    Select(output.value)
    From(output)
    OrderBy(output.value.ascending())
}
```

The CTE renders an explicit column list (`cte0(value) AS (...)`) rather than changing the label SQLite gives the column in a plain scalar `SELECT`. `SQLScalarResult` still works as a source-compatible shim for code written against the old pattern.

## Compound queries over bare types

`UNION`, `UNION ALL`, `INTERSECT`, and `EXCEPT` previously required `Row: XLResult` on both branches. They now reuse the first branch's row reader instead, so a compound query over a literal type composes without a wrapper:

```swift
let number = schema.table(NumberRow.self)
let statement = select(number.value).from(number)
    .unionAll { select(number.value).from(number) }
let rows: [Int] = try database.makeRequest(with: statement).fetchAll()
```

## Internal rewrite: recursive CTE construction

The internal machinery for building a recursive CTE moved from a mutable completion cell to `XLRecursiveCommonTableDraft`, a value-semantic, two-phase draft. The self-reference passed into a recursive CTE's body now comes from its reserved alias, and if the body throws, the draft rolls back to its declared state so it can be retried. `recursiveCommonTable` and `recursiveCommonTableExpression` keep the same signatures and render byte-for-byte identical SQL, so this is invisible from calling code.

## Migration

None required. Every change in v1.4.5 is additive.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.4.5 release](https://github.com/lukevanin/swiftql/releases/tag/v1.4.5)
