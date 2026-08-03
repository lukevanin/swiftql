---
title: "What's new in v1.3.0"
date: 2026-07-20
description: "SwiftQL 1.3.0 adds no new public API; it backs the existing SQLite surface with a versioned conformance inventory, a real-database correctness corpus, and a live-query stress suite."
---

SwiftQL 1.3.0 changes no public syntax and needs no migration. The milestone instead builds the evidence that the v1.2 surface does what it claims: a versioned conformance inventory, a bounded combinatorial corpus, a correctness suite against a real Northwind database, a live-query stress suite, and an internal research prototype for build-time query validation.

## A versioned conformance inventory

Issue [#190](https://github.com/lukevanin/swiftql/issues/190) adds a canonical inventory of SwiftQL's public SQLite surface, generated deterministically into a report rather than maintained by hand. Each record carries a support status, so "supported" means something specific: deterministic rendering plus a successful prepare against a real, version-identified SQLite engine, not just that the Swift compiles.

| Status | Records |
| --- | ---: |
| Supported | 97 |
| Capability-gated | 2 |
| Intentionally unsupported | 1 |
| Unimplemented | 5 |
| **Total** | **105** |

Of 141 evidence records backing those 105 features, 89 exercise real SQLite, all captured against one recorded SQLite 3.51.0 environment. The inventory and its generated report live under `Tests/SwiftQLSQLiteConformanceFixtures/` and `Conformance/SQLite/`, and CI regenerates the report from the same source data on every change.

## A bounded combinatorial corpus

Issue [#191](https://github.com/lukevanin/swiftql/issues/191) adds 141 stable generated test cases that combine joins, subqueries, common table expressions, grouping, and bindings, plus a deliberately broken renderer kept as a negative control so the suite proves it can fail. Deterministic manifests and runtime provenance record exactly which combinations ran, so the corpus stays reviewable instead of quietly growing into a claim of exhaustive SQL coverage.

## Real-database correctness against Northwind

Issue [#254](https://github.com/lukevanin/swiftql/issues/254) adds an immutable Northwind SQLite snapshot and 18 correctness scenarios covering joins, aggregates, subqueries, compound queries, common table expressions, decoding, CRUD, and rollback behavior. Several of these cross-check a typed SwiftQL statement against the same query written as raw GRDB SQL, so the test fails if the two ever diverge:

```swift
let joinedStatement = sql { schema in
    let orders = schema.table(NorthwindCorpusOrder.self)
    let customers = schema.table(NorthwindCorpusCustomer.self)
    let employees = schema.table(NorthwindCorpusEmployee.self)
    let details = schema.table(NorthwindCorpusOrderDetail.self)
    let products = schema.table(NorthwindCorpusProduct.self)
    Select(NorthwindCorpusOrderLine.columns(
        orderID: orders.orderID,
        customerID: customers.customerID,
        companyName: customers.companyName,
        employeeID: employees.employeeID,
        employeeLastName: employees.lastName,
        productID: products.productID,
        productName: products.productName,
        unitPrice: details.unitPrice,
        quantity: details.quantity,
        discount: details.discount
    ))
    From(orders)
    Join.Inner(customers, on: customers.customerID == orders.customerID)
    Join.Inner(employees, on: employees.employeeID == orders.employeeID)
    Join.Inner(details, on: details.orderID == orders.orderID)
    Join.Inner(products, on: products.productID == details.productID)
    Where(orders.orderID == SQLiteNorthwindConformanceFixtures.sentinelOrderID)
    OrderBy(products.productID.ascending())
}
```

The test fetches this statement through SwiftQL, fetches the equivalent hand-written SQL through GRDB directly, and asserts the two row sets are equal. Nothing here is new syntax; it is the five-table join SwiftQL already supported, now pinned against real data instead of a fixture.

## A live-query stress suite

Issue [#255](https://github.com/lukevanin/swiftql/issues/255) adds 12 stable cases exercising live queries under concurrent writes, invalidation, delivery, cancellation, transient `SQLITE_BUSY` retries, and isolation across separate databases. This is the same `publish()`/`publishOne()` surface from 1.1.0's retry policy, now checked under contention rather than only in isolation.

## Internal research: build-time query validation

Issue [#132](https://github.com/lukevanin/swiftql/issues/132) adds a research prototype that prepares static query descriptors ahead of time against the checked-in Northwind snapshot, using a read-only validation connection that finalizes every prepared statement and emits a reproducible report. It is internal research, not a public validator, build plugin, macro, schema system, or v1.3 API, and it does not change how a running application prepares or executes a statement on its own connection.

## Migration

None. v1.3 preserves the v1.2 public source and runtime contracts and adds only conformance evidence, correctness and stress coverage, an internal research artifact, and refreshed documentation.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.3.0 release](https://github.com/lukevanin/swiftql/releases/tag/v1.3.0)
