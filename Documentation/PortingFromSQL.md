# Porting SQL to SwiftQL

A guide for moving existing SQLite queries into SwiftQL, and for reading
SwiftQL if you already know SQL.

SwiftQL is designed so that this is a mechanical exercise. Every clause appears
once, under its SQL name, in SQL's grammatical order. Porting a query means
rewriting it clause by clause, top to bottom, without first redesigning it to
fit a builder's vocabulary. The same property works in reverse: a SwiftQL query
can be read out as SQL by anyone who knows SQL and has never seen this library.

If you find a query that does not port this way, that is a defect worth
reporting, not a limitation you should work around.

## The shape of a port

Start with a query you already have:

```sql
SELECT * FROM Person WHERE name = 'Fred'
```

The port keeps the clauses, in order, and replaces the table and column names
with typed references:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

Three lines of SQL, three statements of Swift, same order. The only additions
are the `sql { schema in ... }` entry point and the `let person =` binding that
gives you a typed handle to the table.

That handle is the one genuine difference from SQL, and it is what buys the type
checking: `person.name` is a typed column reference, so a typo does not compile
and a rename leads the compiler to every query affected.

## Clause mapping

| SQL | SwiftQL |
| --- | --- |
| `SELECT *` | `Select(person)` |
| `SELECT a, b` | `Select(#row(person.name, occupation.name))` or a `@SQLResult` projection |
| `FROM t` | `From(person)` |
| `INNER JOIN t ON x` | `Join.Inner(occupation, on: occupation.id == person.occupationId)` |
| `LEFT JOIN t ON x` | `Join.Left(occupation, on: ...)` with `schema.nullableTable(...)` |
| `CROSS JOIN t` | `Join.Cross(occupation)` |
| `WHERE x` | `Where(person.age > 21)` |
| `GROUP BY x` | `GroupBy(person.occupationId)` |
| `HAVING x` | `Having(row.numberOfPeople >= 2)` |
| `ORDER BY x ASC, y DESC` | `OrderBy(person.name.ascending(), person.age.descending())` |
| `LIMIT n` | `Limit(5)` |
| `OFFSET n` | `Offset(10)` |
| `UNION` | `Union()` |
| `UNION ALL` | `UnionAll()` |
| `WITH name AS (...)` | `schema.commonTableExpression { ... }` plus `With(cte)` |
| `WITH RECURSIVE name AS (...)` | `schema.recursiveCommonTableExpression(Row.self) { schema, this in ... }` plus `With(cte)` |
| `(SELECT ...)` as a value or source | `subqueryExpression { ... }` |
| `x IN (SELECT ...)` | `org.name.in(cte)` |
| `COUNT(x)` | `person.id.count()` |
| `MIN(x)` / `MAX(x)` / `SUM(x)` | `person.age.minOrNull()` / `.maxOrNull()` / `.sumOrNull()` |
| `COALESCE(x, 0)` | `person.age.sumOrNull().coalesce(0)` |
| `x IS NULL` / `x IS NOT NULL` | `family.died.isNull()` / `person.occupationId.notNull()` |
| `AND` / `OR` / `NOT` | `&&` / `\|\|` / `!` |
| `CREATE TABLE` | `sqlCreate(Person.self)` |
| `INSERT INTO t VALUES (...)` | `sqlInsert(person)` |
| `UPDATE t SET c = v` | `Update(person)` plus `Setting(person) { row in row.age = 42 }` |
| `DELETE FROM t` | `Delete(person)` |
| `:name` bind parameter | `XLNamedBindingReference<String>(name: "name")` |

Read statements take their table from `schema.table(_:)`. Write statements take
theirs from `schema.into(_:)`.

## Worked ports

### 1. Filter and order

```sql
SELECT * FROM Person
ORDER BY age ASC
LIMIT 5 OFFSET 10
```

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.age.ascending())
    Limit(5)
    Offset(10)
}
```

### 2. Left join with a projection

```sql
SELECT Person.id, Person.name, Occupation.id, Occupation.name
FROM Person
LEFT JOIN Occupation ON Occupation.id = Person.occupationId
```

A projection that is not a whole table needs a result type, so the decoded rows
have somewhere to land:

```swift
@SQLResult struct PersonOccupation {
    let personId: String
    let personName: String
    let occupationId: String?
    let occupationName: String?
}

let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    Select(
        PersonOccupation.columns(
            personId: person.id,
            personName: person.name,
            occupationId: occupation.id,
            occupationName: occupation.name
        )
    )
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

Note `schema.nullableTable` on the joined side. A left join can produce no
matching row, so its columns are optional, and SwiftQL makes you say so. The
result type's `occupationId` and `occupationName` are `String?` for the same
reason. In SQL this is a runtime surprise; here it is a compile-time fact.

For a quick two-column projection with no named type, `#row` avoids declaring
one:

```swift
Select(#row(person.name, occupation.name))
```

### 3. Group and aggregate

```sql
SELECT occupationId, COUNT(id) AS numberOfPeople
FROM Person
GROUP BY occupationId
HAVING numberOfPeople >= 2
```

```swift
@SQLResult struct OccupationAggregate {
    var occupationId: String?
    var numberOfPeople: Int
}

let query = sql { schema in
    let person = schema.table(Person.self)
    let row = OccupationAggregate.columns(
        occupationId: person.occupationId,
        numberOfPeople: person.id.count()
    )
    Select(row)
    From(person)
    GroupBy(person.occupationId)
    Having(row.numberOfPeople >= 2)
}
```

Binding the projection to `row` first lets `Having` refer to the aggregate by
name, the same way SQL refers to the alias.

### 4. Recursive common table expression

The showpiece, because this is where most typed query builders stop. Walking an
org chart upward from a starting employee:

```sql
WITH RECURSIVE cte(value) AS (
    SELECT 'Alice'
    UNION
    SELECT Org.name FROM Org CROSS JOIN cte WHERE Org.boss = cte.value
)
SELECT Org.name FROM Org WHERE Org.name IN cte
```

```swift
@SQLResult struct ScalarString {
    var value: String?
}

let query = sql { schema in

    let cte = schema.recursiveCommonTableExpression(ScalarString.self) { schema, cte in
        let org = schema.table(Org.self)
        // Define the initial value for the starting condition.
        let initialResult = ScalarString.columns(value: "Alice".toNullable())
        Select(initialResult)
        // Union the initial value with successive values.
        Union()
        // Select members from the org whose boss matches the current member
        Select(ScalarString.columns(value: org.name))
        From(org)
        Join.Cross(cte)
        Where(org.boss == cte.value)
    }

    let org = schema.table(Org.self)
    With(cte)
    Select(org.name)
    From(org)
    Where(org.name.in(cte))
}
```

The recursive self-reference is the `cte` parameter of the closure. It is a
typed table reference like any other, so `cte.value` is checked the same way
`org.name` is.

Multiple CTEs are listed in one `With`, in dependency order, exactly as SQL
requires:

```swift
With(parentOfCommonTable, ancestorOfAliceCommonTable)
```

## Values, parameters, and types

Literal values are ordinary Swift values. Columns are ordinary Swift types:
`Int`, `Double`, `String`, `Data`, and their optionals. There is no parallel
`SQL.Integer` type system to learn, and no affinity rules to remember.

Bind parameters become named references, declared once and reused:

```swift
let personIDParameter = XLNamedBindingReference<String>(name: "id")
let ageParameter = XLNamedBindingReference<Int>(name: "age")

let updateAgeStatement = sql { schema in
    let person = schema.into(Person.self)
    Update(person)
    Setting(person) { row in
        row.age = ageParameter
    }
    Where(person.id == personIDParameter)
}
```

The statement is built once and prepared once. Values arrive separately at
invocation time through `XLInvocationBindings`, which is what keeps the prepared
statement cacheable. If you are porting code that concatenates values into a SQL
string, this is the change that matters most: the values stop being part of the
statement.

Types without a native SQLite representation, notably `Date` and `UUID`, are
handled by codecs rather than by conversion at every call site. SwiftQL ships
presets for the common encodings (`Date` as text or as a numeric value, `UUID`
as text or as a blob) and `@SQLCodec` selects one per property. See
[CustomTypes](../Sources/SwiftQL/SwiftQL.docc/CustomTypes.md) and
[NumericDateCodecs](../Sources/SwiftQL/SwiftQL.docc/NumericDateCodecs.md).

## Where the correspondence is not exact

Four differences are structural, and they are the price of compile-time
checking:

1. **Tables must be declared as Swift types.** `@SQLTable` on a struct is how
   the compiler learns your schema. Porting starts by writing those structs to
   match your existing tables.
2. **Table references are values.** `let person = schema.table(Person.self)`
   has no SQL counterpart. It is what makes `person.name` typed.
3. **Projections need a result type.** Selecting a whole table decodes into that
   table's struct. Anything else needs `@SQLResult` or `#row`, because the
   decoded row has to have a Swift type.
4. **Outer-joined tables are declared nullable at the source**, via
   `schema.nullableTable`, rather than only being nullable in the result.

Beyond those, the current gaps are recorded rather than hidden. As of the v1.3
conformance inventory, of 111 tracked features, 104 are supported with evidence
from a real SQLite engine, and the exceptions are:

- `NATURAL` and `USING` join forms are not implemented. Use an explicit `ON`
  condition.
- CTE materialization hints (`MATERIALIZED`, `NOT MATERIALIZED`) are not
  implemented.
- A typed DDL model is not implemented. `sqlCreate` creates a basic table and
  **does not migrate an existing schema**. Use GRDB's `DatabaseMigrator`
  alongside SwiftQL for migrations.
- One compound-query direct-scalar form is not implemented.
- Nested transactions and single-connection visibility are capability-gated,
  meaning they depend on the driver in use.

The inventory is the source of truth and is versioned with the library. See the
[conformance report](../Conformance/SQLite/REPORT.md) and
[COMPATIBILITY.md](../COMPATIBILITY.md#sqlite-conformance-inventory).

## Coming from raw SQLite or string-built SQL

If your current code calls `sqlite3_prepare_v2` directly, or builds strings for
GRDB or another driver, the port has three parts:

1. **Schema.** Write an `@SQLTable` struct per table. Column names and types
   must match what is already in the database; SwiftQL does not create or
   migrate it for you.
2. **Statements.** Port each query clause by clause using the table above.
   Statements are values, so they can be built once and stored.
3. **Values.** Replace interpolated values with named binding references, and
   pass them at invocation. Anything you were escaping by hand stops needing to
   be escaped, because it is no longer text.

Execution, pooling, transactions, and observation stay with GRDB underneath, so
an existing GRDB setup keeps working. SwiftQL replaces the part where queries
became strings, not the part that runs them.

## Checklist

- [ ] An `@SQLTable` struct for each table, matching the live schema
- [ ] `@SQLResult` types for projections that are not whole tables
- [ ] Outer-joined tables declared with `schema.nullableTable`
- [ ] Interpolated values replaced with `XLNamedBindingReference`
- [ ] `Date` and `UUID` columns given an explicit codec
- [ ] Migrations left with GRDB's `DatabaseMigrator`
- [ ] Queries that would not port cleanly reported as issues
