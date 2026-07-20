# Select Queries

Use joins, aggregates, sorting, subqueries, and common table expressions.

## Overview

The <doc:GettingStarted> showed the fundamental principles behind SwiftQL. This 
guide covers:

- Joining tables
- Performing aggregate queries using group by and having clauses 
- Sorting using order by 
- Using limit and offset 
- Subqueries
- Common table expressions

## Where 

The <doc:GettingStarted> showed `Where` clauses being used in select statements.
This section covers the capabilities of `Where` clauses in more detail.

`Where` predicates use SQLite's three-valued logic and can evaluate to `true`,
`false`, or `NULL`. Only rows for which the predicate is `true` are included;
rows producing `false` or `NULL` are excluded.

We have already seen a simple `Where` expression where we check if a field is 
equal to a static value or a parameter:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == "fred")
}
```

A `Where` expression can include multiple terms. SwiftQL's builder does not add
its own complexity limit; the configured SQLite engine's limits still apply:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == "fred" || ((person.age > 21) && (person.age < 65)))
}
```

Refer to the <doc:Expressions> guide for more details about expressions.

## Join

The ability to join tables in a query is where relational databases really start 
to shine. SwiftQL supports cross join, inner join, and left (outer) join. 

> Note: SwiftQL does not currently support right joins or full outer joins.

First let's define an `Occupation` table that we can join to our `Person` table:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
import SwiftQL

@SQLTable struct Occupation {
    var id: String
    var name: String
}
```

Let's create the table and insert some entries:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
try database.makeRequest(with: sqlCreate(Occupation.self)).execute()

let engineer = Occupation(id: "eng", name: "Engineer")
try database.makeRequest(with: sqlInsert(engineer)).execute()

let scientist = Occupation(id: "sci", name: "Scientist")
try database.makeRequest(with: sqlInsert(scientist)).execute()
```

Let's also create some `Person` entries linked to these occupations:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let joeBloggs = Person(id: "joe-bloggs", occupationId: "eng", name: "Joe Bloggs", age: 25)
try database.makeRequest(with: sqlInsert(joeBloggs)).execute()

let janeDoe = Person(id: "jane-doe", occupationId: "sci", name: "Jane Doe", age: 45)
try database.makeRequest(with: sqlInsert(janeDoe)).execute()

let davidSmith = Person(id: "david-smith", occupationId: "sci", name: "David Smith", age: 33)
try database.makeRequest(with: sqlInsert(davidSmith)).execute()
```

When joining multiple tables the result is often, although not always, a
combination of columns from some or all of the tables. To define a result
with an arbitrary combination of columns we use a struct annotated with 
`@SQLResult`.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
import SwiftQL

@SQLResult struct PersonOccupation {
    let personId: String
    let personName: String
    let occupationId: String?
    let occupationName: String?
}
```

We can now write a query that selects all of the people in the database with 
their occupation. The `occupationId` on the `Person` table is optional so when
we join the `Occupation` table it is possible that the `Occupation` table will
be `NULL` for that person. To handle this we need to tell SwiftQL that we expect
a *nullable* table to be returned.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
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

We used the `PersonOccupation.columns` to instantiate a column set which 
uses fields from both the `Person` and `Occupation` tables. 

We can also reference the fields of the result column set in the query:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let row = PersonOccupation.columns(
        personId: person.id,
        personName: person.name,
        occupationId: occupation.id,
        occupationName: occupation.name
    )
    Select(row)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
    Where(row.personName != "Fred")
}
```

> Tip: SwiftQL's builder does not add its own limit on joined tables. The
> configured SQLite engine's limits still apply.

> Tip: Use `Join.Cross` or `Join.Inner` to perform a cross or inner 
join respectively.

## Group By

Use the group by clause to return aggregate results, or results where a single
row has a computation from multiple records, such as the total number of records
matching some criteria.

Let's define a `@SQLResult` to return the total number of people for each 
occupation:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
import SwiftQL

@SQLResult struct OccupationAggregate {
    var occupationId: String?
    var numberOfPeople: Int
}
```

We can write a query to select the person records grouped by their 
`occupationId`, and use the `count()` aggregate function to compute the number
of people for each occupation.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let row = OccupationAggregate.columns(
        occupationId: person.occupationId,
        numberOfPeople: person.id.count()
    )
    Select(row)
    From(person)
    GroupBy(person.occupationId)
}
```

SwiftQL currently supports the following aggregate functions:

API                               | Input             | Result    | Behavior
----------------------------------|-------------------|-----------|-------------------------------------------
`count()`                         | Any               | `Int`     | Number of non-NULL values; zero for empty input.
`count(all())`                    | All rows          | `Int`     | Number of input rows, rendered as `COUNT(*)`.
`minOrNull()`                     | Any comparable    | `T?`      | Minimum non-NULL value.
`maxOrNull()`                     | Any comparable    | `T?`      | Maximum non-NULL value.
`averageOrNull()`                 | `Double`          | `Double?` | Average (arithmetic mean) of non-NULL values.
`sumOrNull()`                     | `Int` or `Double` | `T?`      | Additive sum of non-NULL values.
`groupConcatOrNull()`             | `String`          | `String?` | Concatenation of all non-NULL values.
`groupConcatOrNull(separator:)`   | `String`          | `String?` | Concatenation using a custom separator.

Except for `count()`, these aggregates return `nil` when SQLite evaluates an
empty input or a group containing no non-NULL values. Model those results with
optional properties, or choose a nonoptional fallback explicitly:

Use `count(all())` when NULL values must still contribute to the row count.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
@SQLResult struct AgeAggregate {
    var minimumAge: Int?
    var maximumAge: Int?
    var totalAge: Int
}

let query = sql { schema in
    let person = schema.table(Person.self)
    Select(
        AgeAggregate.columns(
            minimumAge: person.age.minOrNull(),
            maximumAge: person.age.maxOrNull(),
            totalAge: person.age.sumOrNull().coalesce(0)
        )
    )
    From(person)
}
```

The legacy `min`, `max`, `average`, `sum`, and `groupConcat` aggregate spellings
remain available but deprecated throughout SwiftQL 1.x. Their canonical names
will return optional expressions in SwiftQL 2. Migrate to the `OrNull` APIs in
v1 so the result type accurately represents SQLite NULL.

The aggregate-function forms without a custom separator accept a `distinct`
boolean parameter. When set to `true`, duplicate values will be discarded and
only unique values will be included in the result set.

SQLite does not allow `DISTINCT` and a custom separator in the same
`GROUP_CONCAT` call. Use either `groupConcatOrNull(distinct: true)` or
`groupConcatOrNull(separator:)`.

Earlier SwiftQL releases incorrectly exposed the custom-separator overload on
numeric expressions. Convert a numeric expression with `toString()` before
calling `groupConcatOrNull(separator:)`.

SQLite permits a `GROUP BY` clause with or without aggregate result terms.
SwiftQL preserves the grouping expression but leaves SQLite to validate the
complete query.

## Having

The having clause is used in conjunction with the group by clause to filter 
groups. Think of like a where clause but operating on groups instead of 
individual rows. As an example we can filter our previous query to only include 
occupations where there are two or more people with that occupation:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
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

## Order By

Query results can be sorted using the order by clause. Use the `ascending` or
`descending` functions on the column or columns to sort by:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.name.ascending())
}
```

To sort by multiple columns, include the columns in the order by clause:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.name.ascending(), person.age.descending())
}
```

## Limit and offset

Use the limit clause to specify the maximum number of items to return from a 
query. We can write a query to return the five youngest people in the database:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.age.ascending())
    Limit(5)
}
```

The offset clause is used in conjunction with the limit clause. Offset skips a 
number of rows, and is often used to paginate results from a large result set:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
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

## Subqueries

Subqueries can be used anywhere that a column is used, such as in a result for
a `Select` query:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
@SQLResult struct OccupationCount {
    let occupation: String
    let numberOfPeople: Int?
}
```

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)
    Select(
        OccupationCount.columns(
            occupation: occupation.name,
            numberOfPeople: subqueryExpression { _ in
                Select(person.id.count())
                From(person)
                Where(person.occupationId == occupation.id)
            }
        )
    )
    From(occupation)
}
```

Subqueries can also be used in place of a table in a `From` or `Join` clause:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(
        subqueryExpression { _ in
            Select(person)
            From(person)
            Where(person.age > 18)
        }
    )
    Where(person.age < 65)
}
```

See the <doc:Expressions/In-operator> documentation for an example of using a
subquery with the `in` operator.

## Union, Union All, Except, Intersect

The result of two or more select statements can be combined into a compound query
using the union, union all, except, or intersect operators. 

Suppose we have a table representing a family tree, and we want to select the 
mother and father of each member in the tree.

We first define a table representing the family tree:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
@SQLTable struct Family {
    var name: String?
    var mom: String?
    var dad: String?
    // Fixed-width UTC ISO-8601 dates retain chronological order as text.
    var born: String?
    var died: String?
}
```

We also define a result set for the name of the family member and their parent:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
@SQLResult struct FamilyMemberParent {
    let name: String?
    let parent: String?
}
```

We can select the mother and father for each family member, then combine the 
results using a `union`.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let query = sql { schema in
    // Define the tables used in the two queries.
    let familyMom = schema.table(Family.self)
    let familyDad = schema.table(Family.self)

    // Define the result that reads the person's name and their mother's name.
    let momRow = FamilyMemberParent.columns(name: familyMom.name, parent: familyMom.mom)

    // Define the result that reads the person's name and their father's name.
    let dadRow = FamilyMemberParent.columns(name: familyDad.name, parent: familyDad.dad)

    // Fetch the name of the mother for each person.
    Select(momRow)
    From(familyMom)

    // Use union to combine the results of the second query.
    Union()

    // Fetch the name of the father for each person.
    Select(dadRow)
    From(familyDad)
}
```

`UnionAll` combines the rows from both queries and preserves duplicates. `Union`
is similar except duplicate rows are excluded. SQLite does not guarantee the
order of compound-query rows unless the compound statement has an `OrderBy`
clause.

The `Except` operator returns the results from the first query that are not also 
in the second query, which is to say that the row is omitted if it is returned 
by both queries.

The `Intersect` operator returns rows that are present in both queries.

> Tip: All of the select statements used in a compound query must return the
same data type.

## Common table expressions

Common table expressions are a powerful feature of SQLite which allow SQL to be 
queried in a procedural way. Using common table expressions, SQL statements can 
be encapsulated into separate expressions which can be used as tables in other
select statements within the same query.

To use a common table expression:
1. Call the `commonTableExpression` function to create the common table 
expression, passing a closure that returns a select query.
2. Call `schema.table` to identify the common table expression as a table.
3. Call `With` before `Select` to include the common table expression in
the query.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let _ = sql { schema in
    let personCommonTable = schema.commonTableExpression { schema in
        let person = schema.table(Person.self)
        Select(person)
        From(person)
        Where(person.occupationId.notNull())
    }
    let person = schema.table(personCommonTable)
    With(personCommonTable)
    Select(person)
    From(person)
}
```

This is equivalent to the following SQL:

```sql
WITH cte0 AS (
  SELECT
   t0.id AS id,
   t0.occupationId AS occupationId,
   t0.name AS name,
   t0.age AS age
  FROM
   Person AS t0
  WHERE
   (t0.occupationId NOTNULL)
)
SELECT
 t0.id AS id,
 t0.occupationId AS occupationId,
 t0.name AS name,
 t0.age AS age
FROM
 cte0 AS t0
```

> Note: A common table expression definition cannot be passed directly to
`Select`, `From`, or `Join`. For example, `Select(personCommonTable)` is invalid;
first obtain a table reference with `schema.table(personCommonTable)`.

### Recursive common table expressions

Recursive common table expressions are common table expressions where the query 
refers to itself. They are commonly used with hierarchical data sets. 

A recursive expression is written as the union of two or more queries, where the 
first query provides the base case, or starting condition, and the remaining 
queries produce subsequent results. 

Use `recursiveCommonTableExpression` to create a recursive common table
expression.

For our example, define a table that represents a company's hierarchical
organization chart:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
@SQLTable struct Org {
    var name: String?
    var boss: String?
}
```

We will also define an `@SQLResult` that we use to refer to the result of the 
recursive common table expression. This essentially defines a 'table' with a 
single column. 

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
@SQLResult struct ScalarString {
    var value: String?
}
```

We can now create an expression which returns all of the members of the 
organisation from a person named Alice, and everyone below her. 

We call `recursiveCommonTableExpression` passing the return type which is 
returned by the expression. In this case we use our `ScalarString` result which
we defined above.

The `recursiveCommonTableExpression` closure provides a schema which we have
seen before, as well as a second parameter which we can use to refer to the
common table expression recursively.

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
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
    
    // Select members from the org whose names are returned by the common table expression.
    let org = schema.table(Org.self)
    With(cte)
    Select(org.name)
    From(org)
    Where(org.name.in(cte))
}
```

### Combining recursive common tables with non-recursive common tables

SwiftQL emits common table expressions in the order passed to `With`. The
SQLite behavior exercised by SwiftQL's tests accepts the dependency-first order
shown below: the ordinary common table appears before the recursive common table
that references it. This example does not establish portable ordering
requirements for recursive common tables across every database backend.

We can now write a query to fetch all living ancestors of 'Alice', using the
family tree table from our earlier example:

<!-- test: XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs -->
```swift
let selectStatement = sql { schema in
    
    let parentOfCommonTable = schema.commonTableExpression { schema in
        let family = schema.table(Family.self)
        let momRow = FamilyMemberParent.columns(name: family.name, parent: family.mom)
        let dadRow = FamilyMemberParent.columns(name: family.name, parent: family.dad)
        Select(momRow)
        From(family)
        Union()
        Select(dadRow)
        From(family)
    }
    
    let ancestorOfAliceCommonTable = schema.recursiveCommonTableExpression(ScalarString.self) { schema, this in
        let parentOf = schema.table(parentOfCommonTable)
        Select(ScalarString.columns(value: parentOf.parent))
        From(parentOf)
        Where(parentOf.name == "Alice".toNullable())
        UnionAll()
        Select(ScalarString.columns(value: parentOf.parent))
        From(parentOf)
        Join.Inner(this, on: this.value == parentOf.name)
    }
    
    let ancestorOfAlice = schema.table(ancestorOfAliceCommonTable)
    let family = schema.table(Family.self)
    
    // parentOfCommonTable appears first because ancestorOfAliceCommonTable uses it.
    With(parentOfCommonTable, ancestorOfAliceCommonTable)
    Select(family.name)
    From(ancestorOfAlice)
    Join.Cross(family)
    Where((ancestorOfAlice.value == family.name) && family.died.isNull())
    OrderBy(family.born.ascending())
}
```

Observe the dependency order. We first define an ordinary common table that
selects the mother and father for each family member, and then reference it from
the recursive common table. The `With` clause uses the same order. SwiftQL
preserves this order but does not currently validate or reorder dependencies
between common table expressions.
