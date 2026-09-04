---
title: "What's new in v1.5.1"
date: 2026-07-26
description: "v1.5.1 adds @SQLQuery and @SQLQueries to generate cached, type-checked query functions from a plain Swift signature, a typed multi-statement transaction scope, nested result composition, and a @SQLFunction macro for custom SQL functions."
---

v1.5.1 is a macro release. Four additions land: `@SQLQuery`/`@SQLQueries` turn an ordinary Swift function into a cached, database-bound query, `withTransaction(_:)` runs a sequence of typed reads and writes atomically on one connection, a stored property on a result type can now be another result type instead of only a scalar column, and `@SQLFunction` generates the boilerplate for a custom SQL function from its stored properties.

## Declared queries: `@SQLQuery` and `@SQLQueries`

Until now, a query was a value you built with `sql { }` and passed to `makeRequest(with:)`. `@SQLQuery` (issues [#18](https://github.com/lukevanin/swiftql/issues/18) and [#26](https://github.com/lukevanin/swiftql/issues/26)) lets you write the query as a method instead, with the method's own signature driving everything else:

```swift
extension GRDBDatabase {

    @SQLQuery
    func personByExactName(name: String) -> Person? {
        sqlResult { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.name == name)
        }
    }
}

let match = try database.fetchPersonByExactName(name: "John Doe")
```

The macro reads the return type to decide how many rows to fetch: `[Row]` fetches every match, `Row?` fetches zero or one, and a bare `Row` fetches exactly one, throwing `XLQueryCardinalityError.noRowsMatched` or `.moreThanOneRowMatched` if the count is wrong. Argument labels come straight from the function's own parameter list, so `fetchPersonByExactName(name:)` reads and type-checks like any other Swift call.

`@SQLQueries` is the packaging meant for product code. It reads every specification out of a nested `Query` container and generates the executors as members of the database itself, so a query named `personByName` is called as `database.personByName(name:)` rather than `fetchPersonByName`:

```swift
@SQLQueries
extension GRDBDatabase {

    private struct Query {
        func personByName(name: String) -> [Person] {
            sqlResult { schema in
                let person = schema.table(Person.self)
                Select(person)
                From(person)
                Where(person.name == name)
            }
        }
    }
}

let matches = try database.personByName(name: "John Doe")
```

Because the `Query` container is `private`, none of its methods leak into the database's public API. `@SQLQueries` also generates `execute(_:)`, which runs several declared queries in one scope and commits or rolls them back together.

Both macros render their SQL once. The first call for a given database renders the value-free statement, with parameters as named placeholders rather than inline literals, and caches the resulting request in an `XLRenderOnceCache`; every later call reuses it and only builds a fresh argument packet. Because the rendered text never changes between calls, GRDB's own statement cache reuses one physical prepared statement across every invocation, no matter what values it's called with.

That caching is only safe if a parameter value can never end up baked into the cached SQL text, so the macro rejects, at the declaration site, any parameter reference it cannot turn into a named placeholder: a string interpolation, a nested-closure capture, a direct call argument, a local-binding initializer, a hand-constructed binding, a shadowing declaration, member access on a parameter, a collection-typed parameter, or a parameter that's never referenced. For example, this fails to compile:

```swift
Where(person.name == "prefix\(name)")
```

with the diagnostic pointing at `name`: *"used inside a string interpolation in the '@SQLQuery' body, which renders its value into the string rather than binding a placeholder."* Every reference shape the guard does accept, such as `person.name == name`, is one the rewrite can always turn into a placeholder, so there's no path left where a stale value quietly survives into a later call.

## Typed multi-statement transactions

`GRDBDatabase.withTransaction(_:)` (issue [#284](https://github.com/lukevanin/swiftql/issues/284)) runs an ordered sequence of typed requests, reads and writes together, as one atomic unit on a single pinned connection:

```swift
let (workingAgeCount, insertedID) = try database.withTransaction { scope in
    let newHire = Person(id: "txn-scope-a", occupationId: nil, name: "Grace", age: 29)
    try scope.makeRequest(with: sqlInsert(newHire)).execute()
    let promoted = Person(id: "txn-scope-b", occupationId: nil, name: "Harold", age: 45)
    try scope.makeRequest(with: sqlInsert(promoted)).execute()
    let matches = try scope.makeRequest(with: workingAgeQuery).fetchAll()
    return (matches.count, newHire.id)
}
```

The whole closure commits only if it returns normally; a preparation, binding, execution, decoding, or user-thrown failure rolls back every write the closure made. A read inside the scope sees an earlier, still-uncommitted write from the same closure, since both run on the same connection. `@SQLQueries`'s generated `execute(_:)` is sugar over this same primitive, so a declared-query call and a `makeRequest(with:)` call in one `execute(_:)` closure now commit or roll back together.

Calling `withTransaction(_:)` again from inside an already-open body, on the scope or on the original database, throws a catchable `XLTransactionScopeError.nestedTransactionUnsupported` instead of the crash GRDB's own reentrant-write guard would otherwise raise. Nested transactions and savepoints stay unsupported in v1.5.1, and cancellation is checked once, before the transaction opens, not at any point inside the synchronous body.

## Nested result selection

A stored property on an `@SQLTable`/`@SQLResult` type used to have to be a scalar column. In v1.5.1 (issue [#6](https://github.com/lukevanin/swiftql/issues/6)) it can be another `@SQLTable`/`@SQLResult` type instead:

```swift
@SQLTable struct Employee {
    let id: Int
    let name: String
    let companyID: Int
}

@SQLTable struct Company {
    let id: Int
    let title: String
}

@SQLResult struct EmployeeCompany {
    let employee: Employee
    let company: Company
}
```

SQL has no nested row shape, so the generated row-layout factory for `EmployeeCompany` flattens every one of `Employee`'s columns and every one of `Company`'s columns into individually aliased result columns (`employee_id`, `employee_name`, `company_id`, `company_title`), then reconstructs `employee` and `company` from those columns before building `EmployeeCompany`. Nesting composes to any depth, since a composite property's value is itself a row layout that another factory can nest again. The one restriction: a composite property must be non-optional, so representing an absent nested value from an outer join isn't supported yet.

## Custom SQL functions with less boilerplate

A custom SQL function conforms to `XLCustomFunction` by implementing `definition`, `makeSQL(context:)`, and `execute(reader:)`. The first two follow the same shape for every function: one positional argument per stored property, in declaration order. `@SQLFunction` (issue [#25](https://github.com/lukevanin/swiftql/issues/25)) now generates both from the struct's own properties, leaving `execute` as the only part still written by hand:

```swift
@SQLFunction(name: "haversineDistance")
public struct HaversineDistance: XLCustomFunction {

    public typealias T = Double

    private let fromLatitude: any XLExpression<Double>
    private let fromLongitude: any XLExpression<Double>
    private let toLatitude: any XLExpression<Double>
    private let toLongitude: any XLExpression<Double>

    public init(
        fromLatitude: any XLExpression<Double>,
        fromLongitude: any XLExpression<Double>,
        toLatitude: any XLExpression<Double>,
        toLongitude: any XLExpression<Double>
    ) {
        self.fromLatitude = fromLatitude
        self.fromLongitude = fromLongitude
        self.toLatitude = toLatitude
        self.toLongitude = toLongitude
    }

    public static func execute(reader: XLColumnReader) throws -> Double {
        // ... the Haversine formula, unchanged from a hand-written conformer
    }
}
```

`name:` is optional and defaults to the struct's own name. Alongside it, a function whose `makeSQL` calls the new `XLBuilder.customFunctionCall(_:parameters:)` instead of `simpleFunction(name:parameters:)` no longer needs an upfront `GRDBDatabaseBuilder.addFunction` call: `GRDBDatabase` registers it with SQLite the first time a rendered statement calls it, on whichever pooled connection happens to run it. `addFunction` still works exactly as before for functions that keep calling `simpleFunction` directly.

## Migration

None. `@SQLQuery`, `@SQLQueries`, and `@SQLFunction` are new, additive macros, and the one new `XLDatabase.preparedQueryCacheKey` protocol requirement defaults to `nil`, so every existing conformer, including third-party `XLDatabase` adapters, keeps compiling unchanged.

## What's not in yet

`@SQLQuery`/`@SQLQueries` only accept `SELECT`-shaped specifications; a write statement isn't an accepted return shape yet. Collection-typed parameters (`[T]`, `Set`, `Dictionary`) are rejected, since a variable-length `IN` list would change the rendered SQL text with the element count. The generated executor is synchronous. `withTransaction(_:)` doesn't support nested transactions or savepoints. All of these are tracked as follow-up work rather than silently missing behavior.

[Full changelog](https://github.com/lukevanin/swiftql/blob/main/CHANGELOG.md)
[v1.5.1 release](https://github.com/lukevanin/swiftql/releases/tag/v1.5.1)
