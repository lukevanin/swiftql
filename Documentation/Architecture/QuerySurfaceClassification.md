# Query-construction surface classification

**Status:** analysis only, 20 October 2026. Issue #316. Nothing is deleted,
moved, or renamed by this note.

**Baseline:** `version/2.0` at `66b9fa18` (pull request #830, the module split).
Every current path and symbol below was checked against that commit. The left
column of the first table is the exception: it quotes the issue's old links.

SwiftQL builds the same `XLQuery*Statement` values from two spellings: the
`sql { schema in ... }` result builders, and the functional and fluent syntax
(`select(p).from(p).where(...)`). Both consume the same `XLSchema` and the same
`@SQLTable` and `@SQLResult` metadata. Removal therefore cannot be scoped by
file or by name. This note classifies every public symbol of the
query-construction surface so that the extraction issues can work from one
list.

It feeds #318 (parity), #319 (seams), #321 (port to FluentQL), #322 (move to
DynamicQL), #323 (removal), #324 (test migration), #325 (documentation), and
#33 (naming). It coordinates with #217 and #357, and it is part of the #326
tracker.

## How to read this note

Each symbol gets one disposition.

| Disposition | Meaning | Destination |
| --- | --- | --- |
| **functional/fluent** | An alternative spelling of a statement whose structure is known at compile time. | FluentQL (#320, #321) |
| **runtime builder** | Assembles a statement whose structure is decided at run time. | DynamicQL (#357, #322) |
| **result builder** | A clause token, builder, or entry point of `sql { }`. | stays in SwiftQL |
| **shared** | Used by both spellings, or by something that is neither. Companion packages must still reach it. | stays in SwiftQL |
| **delete** | Deprecated, with a replacement that already exists. Deleted outright, neither moved nor ported. | removed under #323 |

The issue names four dispositions. **delete** is the fifth, for the deprecated
`result(_:)` and `subquery(alias:_:)` overloads, which the issue asks to
confirm are deleted rather than moved.

Rule from the issue: a **functional/fluent** row names the result-builder
spelling that replaces it, or links a gap issue. Where the replacement exists
but a compiling test has not yet proved it, the row links #318.

Paths in the tables are under `Sources/` unless they start with another
directory.

## Where the issue's links live now

The issue's links predate #830, and some predate earlier splits. `Sources/SwiftQL`
now holds only the GRDB adapter and the DocC catalog.

| Issue link | Now |
| --- | --- |
| `Sources/SwiftQL/SQLFunctionalSyntax.swift` | `Sources/SwiftQLQuery/SQLFunctionalSyntax.swift` (every dialect: `XLSchema`, `with`, `select`, `update`, `insert`, `create`, `delete`, `result`) and `Sources/SwiftQLSQLite/SQLFunctionalSyntax+SQLite.swift` (`sqlQuery`, `sqlUpdate`, `sqlInsert`, `sqlCreate`, the `subquery` family, `XLSQLiteSchema`, `XLSchema.init()`) |
| `Sources/SwiftQL/Statements` | `Sources/SwiftQLQuery/Statements`, plus the chain methods that take an expression, which are generated per dialect into `Sources/SwiftQLSQLite/Generated/SQLiteQueryStatements.swift` and `SQLiteWriteStatements.swift`, and `Sources/SwiftQLSQLite/Statements/SQLDataChangingStatements+SQLite.swift` |
| `Sources/SwiftQL/Builders` | `Sources/SwiftQLQuery/Builders` (`QueryBuilder.swift`, `InsertBuilder.swift`), `Sources/SwiftQLSQLite/Builders/QueryBuilder+SQLite.swift`, and the generated `Sources/SwiftQLSQLite/Generated/SQLiteQueryBuilder.swift` |
| `Sources/SwiftQL/SQLStatements.swift:677`, `:707` | `Sources/SwiftQLQuery/SQLQueryClauses.swift` (`Limit` and `Offset`). The statements file was split in #559. The `init(unchecked:)` initializers no longer exist; see [Limit and Offset](#limit-and-offset-type-erasure). |
| `Sources/SwiftQL/Operators/InOperator.swift:15`, `:26` | `Sources/SwiftQLSQLite/Generated/SQLiteInOperator.swift`, generated from `scripts/dialect-surface/Templates/InOperator.swift.template` |
| `subqueryExpression(statement:)` | `Sources/SwiftQLSQLite/Expression Builder/SQLQueryExpressionBuilder+SQLite.swift` (free functions) and `Sources/SwiftQLQuery/Expression Builder/SQLQueryExpressionBuilder.swift` (`XLSchema` methods) |
| `Sources/SwiftQL/SwiftQL.docc` | unchanged |

The generated files are written by `scripts/dialect-surface/generate.py` from
`scripts/dialect-surface/Templates/*.template`, with the dialects in
`scripts/dialect-surface/dialects.json`. Two templates and their output are
wholly one disposition:

- `QueryStatements.swift.template` and `WriteStatements.swift.template`
  generate only fluent chain methods and the scalar `select`. They are
  **functional/fluent**.
- `QueryBuilder.swift.template` generates only `QueryBuilder` members. It is
  **runtime builder**.

`InOperator.swift.template` mixes both: its plain-closure overloads are
fluent and its builder overloads stay. `Clauses.swift.template` generates the
result-builder tokens and stays.

## What the sweep found

1. **Three chained-only features have no result-builder spelling.** `RETURNING`
   (C-28), `ON CONFLICT` (C-29), and `WITH ... UPDATE` (C-27) are reachable
   only through the chained methods. Filed as
   [#834](https://github.com/lukevanin/swiftql/issues/834),
   [#835](https://github.com/lukevanin/swiftql/issues/835), and
   [#836](https://github.com/lukevanin/swiftql/issues/836). #323 must not remove
   those chained methods until they close.
2. **`init(unchecked:)` is gone.** #822 replaced it with an SPI initializer that
   the generated surface also uses. The decision is below.
3. **#317 is closed.** The plain-closure and builder `in(expression:)`
   overloads now coexist, told apart by the closure's arity.
4. **`sqlInsert(_ row:)` has a production caller.**
   `Sources/SwiftQL/GRDBDatabase+InsertBatch.swift` calls it in `insertRendered`,
   the batch insert's per-row fallback. The README, `SKILL.md`, and the DocC
   catalog also depend on it.
5. **Five statement types are produced only by the fluent chain:**
   `XLQueryUnionStatement`, `XLInsertOnConflictStatement`, and the three
   `...ReturningStatement` types. The issue says statement types stay. The
   on-conflict and returning types gain a result-builder producer if #834 and
   #835 land. The builder's
   compound selects end in `XLQuerySelectStatement`, so `XLQueryUnionStatement`
   never gains one and is reachable only through FluentQL and the #319 seam.
6. **The `iterator:` requirements of `XLResult` are not dead after `result(_:)`
   goes.** `@SQLResult`'s generated `columns(...)` calls
   `makeSQLAnonymousResult(namespace:dependency:iterator:)`. Deleting
   `result(_:)` removes a caller of that requirement, not the requirement (#90
   owns it).
7. **Clause ordering is tested only on the chain.** The negative compile-fail
   fixtures for `HAVING` without `GROUP BY`, `OFFSET` without `LIMIT`, and
   `WHERE` after `ORDER BY` all call chain methods. See
   [Generator and compile-fail gates](#generator-and-compile-fail-gates).
8. **A seam already exists.** `@_spi(XLDialectSurface)` is how the per-dialect
   `SwiftQLSQLite` module builds clauses and statements out of the
   dialect-neutral `SwiftQLQuery` module. #319 can extend a precedent rather
   than start one.

## Disposition tally

Counts are rows, not declarations: a row groups the overloads of one symbol.
Columns are the sections below (A free functions, B `XLSchema` members, C chained
methods, D runtime builders, E closure overloads, F types that stay).

| Disposition | A | B | C | D | E | F | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| functional/fluent | 22 | 9 | 29 | 0 | 3 | 0 | 63 |
| runtime builder | 0 | 0 | 0 | 6 | 0 | 0 | 6 |
| result builder | 0 | 7 | 0 | 0 | 5 | 1 | 13 |
| shared | 3 | 8 | 0 | 0 | 0 | 8 | 19 |
| delete | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| **Total** | 28 | 24 | 29 | 6 | 8 | 9 | 104 |

Of the 63 functional/fluent rows, three (C-27, C-28, C-29) have no result-builder
spelling and carry a gap issue. Every other functional/fluent row names a
spelling that exists in the tree; P-1 to P-3 list where a compiling test is still
needed.

## A. Free functions

Rows A-01 to A-28. The SQLite spellings are in
`SwiftQLSQLite/SQLFunctionalSyntax+SQLite.swift` unless a row says otherwise;
the dialect-neutral ones are in `SwiftQLQuery/SQLFunctionalSyntax.swift`.

| ID | Symbol | Disposition | Result-builder spelling, or why it stays |
| --- | --- | --- | --- |
| A-01 | `sqlQuery(builder:)` | functional/fluent | `sql { schema in ... }`, which is `sql(builder:)` with `@XLQueryExpressionBuilder` (`SwiftQLSQLite/Expression Builder/SQLQueryExpressionBuilder+SQLite.swift`). Another dialect: `sql(dialect:builder:)`. `@SQLQuery` specifications are already written with `sql` (or `sqlResult`). |
| A-02 | `sqlUpdate(builder:)` | functional/fluent | `sql(builder:)` with `@XLUpdateExpressionBuilder` |
| A-03 | `sqlInsert(builder:)` | functional/fluent | `sql(builder:)` with `@XLInsertExpressionBuilder` |
| A-04 | `sqlCreate(builder:)` | functional/fluent | `sql(builder:)` with `@XLCreateExpressionBuilder` |
| A-05 | `sqlInsert(_ row:)` | shared | Stays under the same spelling. See [the whole-row constructors](#sqlinsert_-row-and-sqlcreate_-table). |
| A-06 | `sqlCreate(_ table:)` | shared | Stays under the same spelling. Same section. |
| A-07 | `select(_:)` taking an `XLStaticRowReadable` layout | functional/fluent | `Select(layout)` |
| A-08 | `select(_:)` taking an `XLRowReadable & XLDialectBound` projection | functional/fluent | `Select(projection)` |
| A-09 | `select(_:)` taking `any XLSQLiteExpression<T>` (scalar; `SwiftQLSQLite/Generated/SQLiteQueryStatements.swift`). Not in the issue's list, which says "both overloads"; this is the third. | functional/fluent | `Select(expression)` or `Select { expression }` (`SwiftQLSQLite/Generated/SQLiteClauses.swift`) |
| A-10 | `update(_:set:)` | functional/fluent | `Update(table)` then `Setting(...)` |
| A-11 | `update(_:)` | functional/fluent | `Update(table)` |
| A-12 | `insert(_:)` | functional/fluent | `Insert(table)` |
| A-13 | `insert(_:or:)` (`SwiftQLSQLite/Statements/SQLDataChangingStatements+SQLite.swift`) | functional/fluent | `Insert(table, or: action)` (`SwiftQLSQLite/SQLWriteStatements+SQLite.swift`) |
| A-14 | `replace(_:)` (same file) | functional/fluent | `Replace(table)` (`SwiftQLSQLite/SQLWriteStatements+SQLite.swift`; the insert builder's blocks are in `SwiftQLSQLite/Expression Builder/SQLInsertExpressionBuilder+SQLite.swift`) |
| A-15 | `create(_:)` | functional/fluent | `Create(meta)` |
| A-16 | `delete(_:)` | functional/fluent | `Delete(table)` |
| A-17 | `with(_:)` variadic | functional/fluent | `With(...)` (`SwiftQLQuery/SQLSelectStatements.swift`) |
| A-18 | `with(_:)` single common table | functional/fluent | `With(_:)` |
| A-19 | `subquery(alias:_:)`, `XLResult` row, returns `MetaNamedResult` | functional/fluent | `subqueryExpression(alias:statement:)`. The builder form is constrained to `XLTable` and returns `MetaResult`; see parity candidate P-1 (#318). |
| A-20 | `nullableSubquery(alias:_:)` | functional/fluent | `nullableSubqueryExpression(alias:statement:)` |
| A-21 | `subquery(alias:_:)` over an `XLMetaNullable` row, already `@available(*, deprecated)` and unselectable | delete | `nullableSubqueryExpression(alias:statement:)`. The builder's own `XLMetaNullable` form of `subqueryExpression` is a separate symbol and stays. |
| A-22 | `subquery(_:)`, scalar, closure takes a schema | functional/fluent | `subqueryExpression(statement:)`; on Swift 6.1 and later `sql(statement:)` also works |
| A-23 | `subquery(_:)`, scalar, closure takes no schema | functional/fluent | `subqueryExpression { ... }` |
| A-24 | `subquery(_:)`, optional scalar, closure takes a schema | functional/fluent | `subqueryExpression(statement:)` optional form |
| A-25 | `subquery(_:)`, optional scalar, closure takes no schema | functional/fluent | `subqueryExpression { ... }` optional form |
| A-26 | `result(_ builder:)`, deprecated | delete | `@SQLResult`'s generated `columns(...)`, which the deprecation message names. See [`result(_:)`](#result_). |
| A-27 | `result(_ iterator:)`, deprecated | delete | Same. |
| A-28 | `XLTableStatement` (protocol; `From` and `Join` conform) | shared | A marker protocol of the result-builder tokens. |

The issue says "the four `subquery(...)` overloads". The SQLite surface now has
six free functions named `subquery` (A-19 and A-21 to A-25) and the separately
named `nullableSubquery` (A-20). All seven are listed.

## B. `XLSchema` members

`XLSchema` itself stays: `sql { schema in ... }` depends on it. Members are in
`SwiftQLQuery/SQLFunctionalSyntax.swift` unless a row says otherwise. The
closure-taking members are functional-only; each has a builder-attributed twin
in `SwiftQLQuery/Expression Builder/` or `SwiftQLQuery/Statements/`.

| ID | Member | Disposition | Result-builder spelling, or why it stays |
| --- | --- | --- | --- |
| B-01 | `init(dialect:)`, `init(parent:)` | shared | The scope of every statement; `init(parent:)` nests a subquery body. |
| B-02 | `init()` and `XLSQLiteSchema` (`SwiftQLSQLite/SQLFunctionalSyntax+SQLite.swift`) | shared | The SQLite spelling of the scope. |
| B-03 | `table(_:as:)` for an `XLTable`, for an `XLMetaCommonTable`, and for an `XLScalarCommonTable` | shared | Source of every `From(...)` operand. |
| B-04 | `nullableTable(_:as:)` for a table and for a common table | shared | Operand of `Join.Left` and `From` for right and full joins. |
| B-05 | `into(_:as:)` | shared | The write target of `Update` and `Delete`; `GettingStarted` teaches it for result builders. |
| B-06 | `create(_:)` | shared | Operand of `Create(...)`. |
| B-07 | `excluded(_:)` | shared | The `excluded` pseudo table of an upsert. Only the chained upsert (C-29) reaches it today; #835 gives it a builder home. |
| B-08 | `binding(of:as:)` | shared | Named bindings in either spelling. |
| B-09 | `commonTable(alias:materialization:statement:)` taking a statement value, `XLTable` | functional/fluent | `commonTableExpression { schema in ... }` (B-12). A statement already built can be passed through a closure value. |
| B-10 | `commonTable(alias:materialization:statement:)` taking a closure, `XLResult` | functional/fluent | `commonTableExpression(alias:materialization:statement:)` (B-12) |
| B-11 | `recursiveCommonTable(_:alias:materialization:statement:)` | functional/fluent | `recursiveCommonTableExpression(_:alias:materialization:statement:)` (B-13) |
| B-12 | `commonTableExpression(alias:materialization:statement:)` (`SwiftQLQuery/Expression Builder/SQLQueryExpressionBuilder.swift`) | result builder | stays |
| B-13 | `recursiveCommonTableExpression(_:alias:materialization:statement:)` | result builder | stays |
| B-14 | `from(as:statement:)` (doc comment says "Insert"; it builds the `UPDATE ... FROM` source) | functional/fluent | `fromExpression(as:statement:)` (B-15) |
| B-15 | `fromExpression(as:statement:)` (`SwiftQLQuery/Expression Builder/SQLUpdateExpressionBuilder.swift`) | result builder | stays |
| B-16 | `subquery(alias:_:)`, schema method, `XLResult` | functional/fluent | `subqueryExpression(alias:statement:)`; see P-1 (#318) |
| B-17 | `nullableSubquery(alias:_:)`, schema method | functional/fluent | `nullableSubqueryExpression(alias:statement:)` |
| B-18 | `subquery(_:)`, scalar and optional scalar, schema methods (two) | functional/fluent | `subqueryExpression(statement:)` schema methods |
| B-19 | `subqueryExpression(...)`, schema methods: table, scalar, optional scalar (three) | result builder | stays |
| B-20 | `nullableSubqueryExpression(alias:statement:)`, schema method | result builder | stays |
| B-21 | `scalarCommonTable(_:alias:column:materialization:statement:)` (`SwiftQLQuery/Statements/SQLScalarCommonTable.swift`) | functional/fluent | `scalarCommonTableExpression(...)` (B-23) |
| B-22 | `recursiveScalarCommonTable(...)` (same file) | functional/fluent | `recursiveScalarCommonTableExpression(...)` (B-24) |
| B-23 | `scalarCommonTableExpression(...)` | result builder | stays |
| B-24 | `recursiveScalarCommonTableExpression(...)` | result builder | stays |

The twins forward to the same private construction as the functional members
(`makeRecursiveCommonTable`, and `scalarCommonTable`), so the rendered SQL is
shared by construction.

## C. Chained statement methods

Methods are on the types in `SwiftQLQuery/Statements/`. A method that takes an
expression is generated per dialect into `SwiftQLSQLite/Generated/`, and the
row says so. The statement and components types themselves stay (see
[F](#f-types-and-requirements-that-stay)).

| ID | Methods | Receiver | Disposition | Result-builder spelling |
| --- | --- | --- | --- | --- |
| C-01 | `from(_:)` (named; nullable named) | `XLQuerySelectStatement` | functional/fluent | `From(_:)` |
| C-02 | `innerJoin(_:)`, `crossJoin(_:)` | `XLQueryTableStatement` | functional/fluent | `Join.Inner(_:)`, `Join.Cross(_:)` |
| C-03 | `innerJoin(_:using:)`, `leftJoin(_:using:)` | `XLQueryTableStatement` | functional/fluent | `Join.Inner(_:using:)`, `Join.Left(_:using:)` |
| C-04 | `naturalJoin(_:)`, `naturalLeftJoin(_:)` | `XLQueryTableStatement` | functional/fluent | `Join.Natural(_:)`, `Join.NaturalLeft(_:)` |
| C-05 | `innerJoin(_:on:)`, `leftJoin(_:on:)` (generated) | `XLQueryTableStatement` | functional/fluent | `Join.Inner(_:on:)` or `Join(_:on:)`, `Join.Left(_:on:)` |
| C-06 | `rightJoin(_:on:)`, `fullOuterJoin(_:on:)` (generated) | `XLQueryTableStatement` | functional/fluent | `Join.Right(_:on:)`, `Join.FullOuter(_:on:)` |
| C-07 | `where(_:)` (generated) | `XLQueryTableStatement` | functional/fluent | `Where(_:)` |
| C-08 | `groupBy(_:)` (generated) | table, where | functional/fluent | `GroupBy(_:)` |
| C-09 | `having(_:)` (generated) | `XLQueryGroupByStatement` | functional/fluent | `Having(_:)` |
| C-10 | `orderBy(_:)` | table, where, group-by, having, union | functional/fluent | `OrderBy(_:)` |
| C-11 | `limit(_:)` (generated) | table, where, group-by, having, union, order-by | functional/fluent | `Limit(_:)` |
| C-12 | `offset(_:)` (generated) | `XLQueryLimitStatement` | functional/fluent | `Offset(_:)` |
| C-13 | `union`, `unionAll`, `intersect`, `except` | `XLSimpleSelectQueryStatement` | functional/fluent | `Union()`, `UnionAll()`, `Intersect()`, `Except()` followed by the next `Select`. See P-3. |
| C-14 | `values(_:)` (two: `MetaInsert`, row) | `XLInsertTableStatement` | functional/fluent | `Values(_:)` (two) |
| C-15 | `select(_:)` (two) | `XLInsertTableStatement` | functional/fluent | `Select(_:)` after `Insert(_:)` |
| C-16 | `from(_:)` | `XLInsertSelectStatement` | functional/fluent | `From(_:)` |
| C-17 | `innerJoin(_:)`, `crossJoin(_:)`, and generated `innerJoin(_:on:)`, `leftJoin(_:on:)` | `XLInsertSelectTableStatement` | functional/fluent | `Join...` tokens |
| C-18 | `where`, `groupBy`, `having`, `orderBy`, `limit`, `offset` | the `XLInsertSelect*` statements (generated except `orderBy`) | functional/fluent | `Where`, `GroupBy`, `Having`, `OrderBy`, `Limit`, `Offset` |
| C-19 | `set(_:)` (two: `XLMetaUpdate` value, closure) | `XLUpdateTableStatement` | functional/fluent | `Setting(_:)`, `Setting(table, closure)` |
| C-20 | `from(_:)` | `XLUpdateSetStatement` | functional/fluent | `From(_:)` |
| C-21 | `where(_:)` (generated) | `XLUpdateSetStatement`, `XLUpdateFromStatement` | functional/fluent | `Where(_:)` |
| C-22 | `where(_:)` (generated) | `XLDeleteTableStatement` | functional/fluent | `Where(_:)` |
| C-23 | `as(builder:)` | `XLCreateTableStatement` | functional/fluent | `As(builder:)`. A result-builder test exists in `Tests/SQLTests/ExpressionBuilder/SQLCreateExpressionBuilderTests.swift`. The documentation still points readers at the functional form; that is #318 and #325. |
| C-24 | `select(_:)` (three: layout, projection, scalar) | `XLWithStatement` | functional/fluent | `With(...)` then `Select(...)` |
| C-25 | `insert(_:)`, `replace(_:)` | `XLWithStatement` | functional/fluent | `With(...)` then `Insert(...)` or `Replace(...)` |
| C-26 | `delete(_:)` | `XLWithStatement` | functional/fluent | `With(...)` then `Delete(...)` |
| C-27 | `update(_:)`, `update(_:set:)` | `XLWithStatement` | functional/fluent | **None.** `XLDialectUpdateExpressionBuilder` has no `With` block. Gap [#836](https://github.com/lukevanin/swiftql/issues/836). |
| C-28 | `returning(_:)` (two on each of insert, update, delete) | `XLInsertStatement`, `XLUpdateStatement`, `XLDeleteStatement` | functional/fluent | **None.** `Returning` is not an `XLDialectClause` and no builder accepts it. Gap [#834](https://github.com/lukevanin/swiftql/issues/834). |
| C-29 | `onConflict(_:)`, `onConflict(_:doUpdate:)`, `onConflictDoNothing(_:)` | `XLInsertTableValuesStatement` | functional/fluent | **None.** `OnConflict` is not an `XLDialectClause` and no builder accepts it. Gap [#835](https://github.com/lukevanin/swiftql/issues/835). |

C-28 and C-29 are not in the issue's list. They were found because the sweep
read every extension on the statement types, not only the methods named in the
issue.

## D. Runtime builders

`QueryBuilder` and `InsertBuilder` leave for DynamicQL (#357, #322), not
FluentQL. They exist for statements whose structure is decided at run time.

| ID | Symbol | Disposition | Notes |
| --- | --- | --- | --- |
| D-01 | `XLDialectQueryBuilder` and its dialect-neutral members: `init(select:)` (three), `with(_:)` (two), `from(_:)` (two), `innerJoin(_:using:)`, `leftJoin(_:using:)`, `naturalJoin`, `naturalLeftJoin`, `crossJoin`, `orderBy(_:)`, `build()` (`SwiftQLQuery/Builders/QueryBuilder.swift`) | runtime builder | `build()` returns `any XLDialectQueryStatement` and throws on a missing `FROM` or an offset without a limit. |
| D-02 | `QueryBuilder<Row>` typealias (`SwiftQLSQLite/Builders/QueryBuilder+SQLite.swift`) | runtime builder | |
| D-03 | The SQLite-typed members: `init(select:)`, `innerJoin(_:on:)` (two), `leftJoin(_:on:)` (four), `rightJoin(_:on:)` (two), `fullOuterJoin(_:on:)` (two), `and(_:)` (two), `or(_:)` (two), `groupBy(_:)`, `limit(_:)`, `offset(_:)` (`SwiftQLSQLite/Generated/SQLiteQueryBuilder.swift`) | runtime builder | The `Bool` and `Optional<Bool>` pairs are the clearest statement of how a nullable condition is typed. #322 must keep them. |
| D-04 | `_dialectSurfaceJoin`, `_dialectSurfaceAnd`, `_dialectSurfaceOr`, `_dialectSurfaceGroupBy`, `_dialectSurfaceLimit`, `_dialectSurfaceOffset` (SPI members of the builder) | runtime builder | They exist only so the generated D-03 members can reach the builder. They move with it. |
| D-05 | `InsertBuilder<Row>` (`SwiftQLQuery/Builders/InsertBuilder.swift`) | runtime builder | `build()` throws on a missing `Values`. |
| D-06 | `AbstractXLQueryStatement`, `AbstractXLInsertStatement` (internal) | runtime builder | Only the two builders construct them. DynamicQL can return `XLQuerySelectStatement(components:)` and `XLInsertTableValuesStatement(components:)` instead, which are SPI-public. |

## E. Closure overloads that share a name with a builder form

| ID | Symbol | Disposition | Result-builder spelling, or why it stays |
| --- | --- | --- | --- |
| E-01 | `in(expression:)` taking a plain `() -> statement` closure, non-optional operand (`SwiftQLSQLite/Generated/SQLiteInOperator.swift`) | functional/fluent | `in { schema in ... }` (E-03). See [`in(expression:)`](#inexpression-and-the-correlated-case). |
| E-02 | `in(expression:)` plain closure, `T == Optional<Wrapped>`, returns `Optional<Bool>` | functional/fluent | `in { schema in ... }` optional form (E-04) |
| E-03 | `in(expression:)` with `@XLDialectQueryExpressionBuilder`, non-optional | result builder | stays |
| E-04 | `in(expression:)` with `@XLDialectQueryExpressionBuilder`, optional (added by #317) | result builder | stays |
| E-05 | `notIn(expression:)` plain closure, non-optional and optional (two) | functional/fluent | `notIn { schema in ... }` (E-06) |
| E-06 | `notIn(expression:)` with `@XLDialectQueryExpressionBuilder`, non-optional and optional (two) | result builder | stays |
| E-07 | `subqueryExpression(statement:)` free functions (`SwiftQLSQLite/Expression Builder/SQLQueryExpressionBuilder+SQLite.swift`): table, nullable table, scalar (two), optional scalar (two), and `nullableSubqueryExpression` | result builder | stays. Every overload is `@XLQueryExpressionBuilder`. The plain-closure twin is the differently named `subquery(_:)` (A-19 to A-25), so nothing shadows it. |
| E-08 | `sql(alias:statement:)` and `sql(statement:)` as a subquery, six overloads under `#if compiler(>=6.1)` (same file) | result builder | stays; they forward to E-07 |

`commonTable(statement:)` (the issue's fourth name) is rows B-09 and B-10; its
builder twin is `commonTableExpression` (B-12).

## F. Types and requirements that stay

None of these is removable under #323.

| ID | Symbol | Disposition | Notes |
| --- | --- | --- | --- |
| F-01 | `XLQueryStatementComponents`, `XLInsertStatementComponents`, `XLUpdateStatementComponents`, `XLDeleteStatementComponents`, `XLCreateTableStatementComponents` | shared | The values both spellings build. |
| F-02 | The `XLQuery*Statement`, `XLInsert*Statement`, `XLUpdate*Statement`, `XLDelete*Statement`, `XLCreate*Statement`, and `XLWithStatement` families and their protocols (`XLQueryStatement`, `XLDialectQueryStatement`, `XLSimpleSelectQueryStatement`, `XLInsertStatement`, `XLUpdateStatement`, `XLDeleteStatement`, `XLCreateStatement`) | shared | Most are produced by the result builders as well. |
| F-03 | `XLQueryUnionStatement`, `XLInsertOnConflictStatement`, `XLInsertReturningStatement`, `XLUpdateReturningStatement`, `XLDeleteReturningStatement`, `XLReturningStatement` | shared | Produced only by the fluent chain today (finding 5). The on-conflict and returning types gain a producer when #834 and #835 close; `XLQueryUnionStatement` does not. |
| F-04 | `Returning`, `OnConflict`, `XLConflictResolution` | shared | Public clause types used only by the chain today. They are the natural tokens for #834 and #835. |
| F-05 | `XLSelectResultDependency` and the `makeSQLAnonymousResult` and `makeSQLAnonymousNamedResult` requirements of `XLResult`, including the `iterator:` variants | shared | `@SQLResult`'s generated `columns(...)` uses the `iterator:` variant (`Tests/SQLMacrosTests/SQLTests.swift`). #90 owns retiring them. |
| F-06 | `XLNamespace`, `XLName`, `XLCommonTableDependency`, `XLFromTableDependency`, `XLSubqueryDependency`, `XLUpdateFromTableDependency`, `XLExcludedTableDependency` | shared | The dependency model both spellings use. |
| F-07 | `XLMetaResult`, `XLMetaNamedResult`, `XLMetaNullableResult`, `XLMetaNullableNamedResult`, `XLMetaCommonTable`, `XLMetaWritableTable`, `XLMetaInsert`, `XLMetaUpdate`, `XLMetaCreate`, `XLResult`, `XLTable` | shared | What `@SQLTable` and `@SQLResult` generate. |
| F-08 | `XLQueryPartialUnion` | shared | A result-builder accumulator. |
| F-09 | `sqlResult(_:)` (`SwiftQLSQLite/SQLQueryPeerMacroSupport.swift`) | result builder | The `@SQLQuery` type-check anchor; it takes `@XLQueryExpressionBuilder`. The macro also lists `sqlQuery` in `reservedParameterNames` (`SQLMacros/SQLQueryMacro.swift`), which #323 updates. |

### The result-builder surface that stays

Context, not counted above. Everything here is **result builder**.

- Builders: `XLDialectQueryExpressionBuilder` (SQLite: `XLQueryExpressionBuilder`),
  `XLDialectInsertExpressionBuilder` (`XLInsertExpressionBuilder`),
  `XLDialectUpdateExpressionBuilder` (`XLUpdateExpressionBuilder`),
  `XLDialectDeleteExpressionBuilder` (`XLDeleteExpressionBuilder`),
  `XLCreateExpressionBuilder`, `XLScalarExpressionBuilder`, and
  `XLOrderingTermsBuilder`.
- Entry points: `sql(builder:)` for query, update, insert, delete, and create
  in `SwiftQLSQLite/Expression Builder/`, and `sql(dialect:builder:)` for the
  same five in `SwiftQLQuery/Expression Builder/`.
- Tokens: `Select`, `From`, `Join` and its factories, `Where`, `GroupBy`,
  `Having`, `OrderBy`, `Ascending`, `Descending`, `Limit`, `Offset`, `Union`,
  `UnionAll`, `Intersect`, `Except`, `With`, `Update`, `Setting`, `Insert`,
  `Replace`, `Values`, `Create`, `As`, `Delete`, and `XLDialectClause`.

Each clause token in the third list is used in at least one test under `Tests/`
at the baseline.

## Decisions on the named questions

### `sqlInsert(_ row:)` and `sqlCreate(_ table:)`

**Decision: both stay in SwiftQL, under their current spellings.** The issue
asks whether they stay "under a builder-neutral spelling". They already are
neutral: the labelled `(builder:)` overloads (A-03, A-04) are the functional
ones, and the unlabelled ones take a value and name no query spelling. No
rename is needed. #33 owns any later naming change; neither carries the `XL`
prefix.

Evidence, counted with `git grep -o -E` at the baseline over `README.md`,
`SKILL.md`, the DocC catalog, `Documentation`, `Examples`, `Benchmarks`,
`IntegrationTests`, `Tests`, and `Conformance`:

| Spelling | Occurrences |
| --- | --- |
| `sqlInsert(row)` (unlabelled) | about 290 |
| `sqlInsert { ... }` or `sqlInsert(builder:)` | 2 |
| `sqlCreate(Type.self)` (unlabelled) | about 164 |
| `sqlCreate { ... }` or `sqlCreate(builder:)` | 1 |
| `sqlQuery { ... }` | about 74 |
| `sql { ... }` | about 771 |

The unlabelled forms are the README quick start, the `SKILL.md` agent guide, and
most of the test corpus, whichever query spelling the surrounding test uses.
`Sources/SwiftQL/GRDBDatabase+InsertBatch.swift` calls `sqlInsert(row)` in
production code (`insertRendered`). They are shared infrastructure, not syntax.

Today they are built on the functional constructors:
`sqlInsert(_:)` calls `insert(table).values(...)` and `sqlCreate(_:)` calls
`create(table)`. #323 must rebuild them on the components API
(`XLInsertStatementComponents`, `XLCreateTableStatementComponents`) so they do
not depend on the free functions it deletes. That work needs the components
initializers. `XLCreateTableStatementComponents.init` is internal to
`SwiftQLQuery`, so `SwiftQLSQLite` needs at least `package` access to it
(S-03); `XLInsertStatementComponents.init` is already `package` (S-01).
Rendered SQL, including `CREATE TABLE IF NOT EXISTS`, must not change.

### `result(_:)`

A-26 and A-27 are **deleted outright**, not moved. Each is marked
`@available(*, deprecated, message: "Use the .columns() method on the table object instead.")`.
The replacement, `@SQLResult`'s generated `columns(...)`, exists and is what the
documentation teaches. `SQLDocumentationCatalogTests` already asserts that no
documentation file uses `result {`. The only remaining caller is
`Tests/SQLTests/SQLSyntaxWriteStatementTests.swift` (two lines), which #324
rewrites. Deleting the functions does not delete `XLSelectResultDependency` or
the `iterator:` requirements (F-05).

### `Limit` and `Offset` type erasure

The issue asks whether the behaviour behind `init(unchecked:)` is still
required once the builders move.

What exists now. `init(unchecked:)` was removed by #822 (commit `ace4a7ef`). In
its place `Limit` and `Offset` in `SwiftQLQuery/SQLQueryClauses.swift` each have
one `@_spi(XLDialectSurface) public init(_dialectSurface count: any XLExpression)`.
Their doc comments still say the initializer is used "by QueryBuilder's
type-erased API".

Two kinds of caller reach it:

1. The generated, typed initializers in `SwiftQLSQLite/Generated/SQLiteClauses.swift`
   (`Limit(_ count: any XLSQLiteExpression<Int>)`, the `@XLScalarExpressionBuilder`
   form, and the same for `Offset`), and the generated chain methods
   `limit(_:)` and `offset(_:)` (C-11, C-12). These stay or travel with
   FluentQL, and the result-builder tokens need the initializer regardless.
2. `QueryBuilder`'s `limit(_:)` and `offset(_:)`, which take an untyped
   `any XLSQLiteExpression` and reach it through `_dialectSurfaceLimit` and
   `_dialectSurfaceOffset` (D-03, D-04). SQLite validates at execution time that
   the value evaluates to an integer.

**Recorded answer.** The initializer is still required, because callers of
kind 1 exist, and it must stay `any XLExpression`-typed for any SPI client. The
*type-erased public API* (a `limit` that accepts any expression) is required
only by `QueryBuilder` and moves with D-03. The two doc comments must be
rewritten when #322 lands, since #322 forbids comments in SwiftQL that refer to
`QueryBuilder`. The fate (stay as a supported seam, move behind the #319 seam,
or remove) is #322's to pick; this note recommends **stay, as a seam item** (see
S-14), because FluentQL and DynamicQL are both external clients of it.

### `in(expression:)` and the correlated case

#317 is closed. The plain-closure overloads (E-01, E-02, E-05) and the builder
overloads (E-03, E-04, E-06) coexist. The builder overloads take a closure over
a schema; the plain ones take a closure over nothing, so the arity separates
them and no argument label is needed.

The builder overloads open an *independent* scope, so their schema restarts
aliases at `t0` and bindings at `p0`. The documentation says a correlated query
should use the plain, no-schema closure. The builder replacement for a
correlated query is to ignore the closure's own schema and build the inner
tables from `XLSchema(parent: outerSchema)` inside the builder body. That
works, but it is the awkward way round: `subqueryExpression(statement:)` has a
no-schema *builder* overload and `in` does not. Candidate P-2 (#318).

### The `XLSchema` closure members

B-09 to B-11, B-14, B-21, and B-22 can be ported to FluentQL as thin extensions
that forward a closure value to the builder-attributed twin. A result-builder
attribute applies only to a closure *literal*, so forwarding a closure
*parameter* compiles and renders the same SQL. They need no seam beyond the
twin. B-16 to B-18 differ: the plain form is generic over `XLResult` and returns
`MetaNamedResult`, and the twin is generic over `XLTable` and returns
`MetaResult` (P-1).

## Parity candidates for #318

These are signature-level observations. A signature existing is not proof, so
each needs a compiling test, which is #318's job. They are not filed as new
issues because none needs a decision to be made first.

- **P-1.** `subquery(alias:_:)` (A-19, B-16) accepts any `XLResult` and returns
  `MetaNamedResult`. `subqueryExpression(alias:statement:)` accepts only
  `XLTable` and returns `MetaResult`. Check a `@SQLResult` row as a subquery
  source, and `Join.Inner(_:on:)` against a non-nullable builder subquery (`Join`
  takes an `XLMetaNamedResult`). A comment in
  `Tests/SQLTests/SQLSyntaxCompoundSelectTests.swift` says the builder "has no
  LEFT JOIN component", although `Join.Left` exists; the comment looks stale.
- **P-2.** A no-schema builder overload of `in` and `notIn` (E-01, E-05), to
  match `subqueryExpression { ... }`.
- **P-3.** The builder's compound operators take an inline `Select`. The chained
  `union { ... }` (C-13) takes any already-built statement. Combining two
  statements built elsewhere has no builder token.

## Gap issues filed

| Issue | Gap | Row |
| --- | --- | --- |
| [#834](https://github.com/lukevanin/swiftql/issues/834) | `RETURNING` in `sql { }` insert, update, and delete | C-28 |
| [#835](https://github.com/lukevanin/swiftql/issues/835) | `ON CONFLICT` in `sql { }` insert | C-29 |
| [#836](https://github.com/lukevanin/swiftql/issues/836) | `WITH` in the `sql { }` update builder | C-27 |

Each is in milestone v2.0 with labels `enhancement` and `P3`, and each says it
is part of the #318 matrix. #323 must not remove C-27, C-28, or C-29 before they
close.

## Seams the companion packages need (input to #319)

This lists what the ported fluent code and the runtime builders touch that is
not plain `public` API today. It does not decide stable versus `@_spi`; that is
#319. "Today" is the access level at the baseline.

`SwiftQLQuery` and `SwiftQLSQLite` are separate library products. The
dialect-neutral members below live in `SwiftQLQuery`. FluentQL's SQLite
spellings, and DynamicQL's, would also need `SwiftQLSQLite`.

### Already reachable

| Member | Today | Used by |
| --- | --- | --- |
| `init(components:)` of every statement struct (`XLQuerySelectStatement`, `XLQueryTableStatement`, ..., `XLInsertTableStatement`, ..., `XLUpdateTableStatement`, ..., `XLDeleteTableStatement`, `XLDeleteWhereStatement`, `XLInsertOnConflictStatement`) | `@_spi(XLDialectSurface) public` | fluent chain, builders |
| `XLQueryStatementComponents.init(commonTables:select:components:)` | `@_spi(XLDialectSurface) public` | `select`, `with(...).select` |
| `XLQueryStatementComponents.append(_:)`, `appending(_:)`; `XLInsertStatementComponents.appending(_:)`; `XLUpdateStatementComponents.appending(_:)`; `XLCreateTableStatementComponents.appending(_:)` | `public` | chain, builders |
| `XLDeleteStatementComponents.init(commonTables:delete:components:)` | `public` | `delete`, `with(...).delete` |
| `XLWithStatement.init(_dialectSurface:)`, `.commonTables` | `@_spi(XLDialectSurface) public`, `public` | `with(...)` |
| `Join.init(_dialectSurfaceKind:table:constraint:)`; `Where`, `GroupBy`, `Having`, `Limit`, `Offset`, `Ascending`, `Descending` `init(_dialectSurface:)`; `Select.init(_dialectSurface:)`; `With.init(_dialectSurface:)`; `OnConflict._dialectSurfaceDoUpdate` | `@_spi(XLDialectSurface) public` | generated surface, chain, builders |
| `From`, `Select`, `Update`, `Setting`, `Insert`, `Values`, `Create`, `Delete`, `Returning` initializers | `public` | chain, builders |
| `XLCommonTableDependency.init`, `XLFromTableDependency.init`, `XLSubqueryDependency.init`, `XLUpdateFromTableDependency.init`, `XLExcludedTableDependency.init`, `XLSelectResultDependency.init` | `public` | `XLSchema` members, free `subquery` |
| `XLNamespace.table()`, `.common()`, `.parameter()` | `public` | free `subquery`, free `nullableSubquery` |
| `XLInValueExpression.init`, `XLBinaryOperatorExpression.init` | `public` | `in`, `QueryBuilder.build()` |
| The `make*` meta factories on `XLResult` and `XLTable` | `public` (protocol requirements) | every constructor |

### Not reachable today

| ID | Member | Today | Needed by | Why |
| --- | --- | --- | --- | --- |
| S-01 | `XLInsertStatementComponents.init(commonTables:insert:components:)` | `package` | FluentQL: `insert`, `insert(_:or:)`, `replace`, `with(...).insert`; DynamicQL: `InsertBuilder` | An external package cannot call a `package` initializer. `SwiftQLSQLite` can, so `sqlInsert(_ row:)` needs no new access. |
| S-02 | `XLUpdateStatementComponents.init(commonTables:update:components:)` | internal | FluentQL: `update`, `update(_:set:)`, `with(...).update` | |
| S-03 | `XLCreateTableStatementComponents.init(create:components:)`, and the memberwise initializers of `XLCreateTableStatement` and `XLCreateTableAsStatement` | internal | FluentQL: `create`, `as(builder:)`; SwiftQL: `sqlCreate(_ table:)` | `sqlCreate(_:)` lives in `SwiftQLSQLite` and is rebuilt on this initializer under #323, so it needs at least `package` access. |
| S-04 | `XLQueryStatementComponents.init(commonTables:reader:components:)` | internal | FluentQL: `union`, `unionAll`, `intersect`, `except` | |
| S-05 | `BooleanClause` and its construction | internal | FluentQL compound methods | The branch check for `ORDER BY`, `LIMIT`, `OFFSET`, `WITH`, and a nested compound lives here. A seam must keep it, so it cannot be bypassed. |
| S-06 | `Join.init(kind:table:using:)` | internal | FluentQL `innerJoin(_:using:)`, `leftJoin(_:using:)`; DynamicQL `QueryBuilder` | The SPI initializer takes a constraint expression, not a `USING` list. |
| S-07 | `OrderBy.init(terms:)` taking an array | internal | FluentQL `orderBy(_:)`; DynamicQL `QueryBuilder.build()` | The public initializer is variadic and cannot be forwarded an array. |
| S-08 | `OnConflict.init(targets:resolution:)` | internal | FluentQL `onConflict(_:doUpdate:)`, `onConflictDoNothing(_:)` | The public factories are variadic. |
| S-09 | `XLInsertReturningStatement`, `XLUpdateReturningStatement`, `XLDeleteReturningStatement` memberwise initializers | internal | FluentQL `returning(_:)` | |
| S-10 | `Insert.init(table:target:)` | `package` | FluentQL `insert(_:or:)`, `replace`; the SQLite `Replace` clause | |
| S-11 | `XLNamespace.makeAlias(alias:)`, `XLNamespace.makeNestedNamespace()`, and `XLSchema`'s `tableNamespace`, `commonTableNamespace`, `parameterNamespace` | `package`, internal, internal | FluentQL free `subquery` and `nullableSubquery` (A-19, A-20) | They open an independent scope: a fresh namespace, then an alias from it. Reimplementing through `XLSchema().subquery` would number the body's aliases from `t1` instead of `t0`, changing rendered SQL. |
| S-12 | `XLQueryStatementComponents.commonTables`, `.components` | internal | DynamicQL `QueryBuilder.build()` | It assigns `commonTables` and appends in bulk. `append(_:)` is public, so only the assignment needs a seam. |
| S-13 | `XLInsertStatementComponents.components` | internal | DynamicQL `InsertBuilder.build()` | It appends the values clause. |
| S-14 | `Limit.init(_dialectSurface:)`, `Offset.init(_dialectSurface:)` untyped `any XLExpression` | `@_spi` | FluentQL and DynamicQL | Reachable through the SPI. Listed because the SPI's stability is itself the #319 question; see [Limit and Offset](#limit-and-offset-type-erasure). |
| S-15 | `XLSubquery` and `XLDialectExpression.init(_:)` | `package` | none | Not a seam. The scalar-subquery members forward to the builder twin (B-18), so FluentQL does not need them. The note says "only SwiftQL creates" a dialect expression, and that restriction should survive. |

### Must not become a seam

- `XLDeleteStatementComponents` has public mutable stored properties
  (`commonTables`, `delete`, `components`). #319 says not to expose mutable state;
  its constructors are the part to keep and the stored properties are not.
- The `_dialectSurface*` methods on `QueryBuilder` (D-04) are an internal detail
  of the generated D-03 members. They move with the builder.
- `AbstractXLQueryStatement` and `AbstractXLInsertStatement` (D-06) are
  replaceable by the SPI-public statement structs.

### Generator and compile-fail gates

The extraction also moves `scripts/dialect-surface/Templates/QueryStatements.swift.template`,
`WriteStatements.swift.template`, and `QueryBuilder.swift.template` out of the
SwiftQL generator, plus the `InOperator.swift.template` overloads E-01, E-02, and
E-05.

`scripts/ci/check-query-clause-ordering-type-safety.sh` proves clause ordering
with fixtures that call chain methods on `XLQueryTableStatement`:
`HavingWithoutGroupBy.swift`, `OffsetWithoutLimit.swift`,
`WhereAfterOrderBy.swift`, and `WhereRequiresBoolean.swift` (negative), and
`QueryClauseOrderingValid.swift` (positive). No negative fixture in
`Tests/CompileFail` writes a clause out of order inside a `sql { }` body; the
builder tokens appear only in positive fixtures. The builder gets its ordering
from the `buildPartialBlock` overload sets. When the chain leaves, that
guarantee loses its only negative test unless #324 adds builder fixtures first.
Other fixtures also use the chain or `QueryBuilder`
(`DialectClauseJoinFunctionalForeignTable.swift`,
`DialectClauseUnionForeignBranch.swift`,
`DialectClauseQueryBuilderForeignTable.swift`,
`DialectClauseReturningForeignProjection.swift`), and are #324's to place.

## Method and verification

- Read the code at `origin/version/2.0` with `git show`, `git ls-tree`, and
  `git grep`. No build or test was run: the change is documentation only.
- Enumerated every extension on the statement types, not only the methods the
  issue names, by reading `Statements/`, `Generated/`, and the templates.
- Counted usage with `git grep -o -E`, for example
  `git grep -o -E 'sqlInsert[(][^b]' origin/version/2.0 -- README.md SKILL.md Sources/SwiftQL/SwiftQL.docc Documentation Examples Benchmarks IntegrationTests Tests Conformance | wc -l`.
  The counts are approximate: a pattern can match a comment or a doc example.
- Checked that every `Sources/`, `Tests/`, `scripts/`, `Documentation/`,
  `Examples/`, and `Research/` path in this note exists at the baseline, and
  that every named symbol appears in the tree.
- Dispositions counted from the tables A to F by script, not by hand.

Not covered, by design: expressions, operators, functions, codecs, and the
execution layer. They are not query-construction spellings. They appear here
only where a classified symbol depends on them.
