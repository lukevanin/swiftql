# SwiftQL select queries
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

The result of a `Where` expression always resolves to a boolean value. Rows for
which the boolean value resolves to `true` are included in the result, and all
other rows are excluded.

We have already seen a simple `Where` expression where we check if a field is 
equal to a static value or a parameter:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == "fred")
}
```

A where expression can include multiple terms. SwiftQL does not impose any limit
on the complexity of the `Where` clause:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == "fred" || ((person.age > 21) && (person.age < 65))
}
```

Refer to the <doc:Expressions> guide for more details about expressions.

## Join

The ability to join tables in a query is where relational databases really start 
to shine. SwiftQL supports cross join, inner join, and outer join. 

> Note: SwiftQL does not currently support right joins.

First let's define an `Occupation` table that we can join to our `Person` table:

```swift
import SwiftQL

@SQLTable struct Occupation {
    var id: String
    var name: String
}
```

Let's create the table and insert some entries:

```swift
try database.makeRequest(with: sqlCreate(Occupation.self)).execute()

let engineer = Occupation(id: "eng", name: "Engineer")
try database.makeRequest(with: sqlInsert(engineer)).execute()

let scientist = Occupation(id: "sci", name: "Scientist")
try database.makeRequest(with: sqlInsert(scientist)).execute()
```

Let's also create some `Person` entries linked to these occupations:

```swift
let joeBloggs = Person(id: "joe-bloggs", occupationId: "eng", name: "Joe Bloggs", age: "25")
try database.makeRequest(with: sqlInsert(joeBloggs)).execute()

let janeDoe = Person(id: "jane-doe", occupationId: "sci", name: "Jane Doe", age: 45)
try database.makeRequest(with: sqlInsert(janeDoe)).execute()

let davidSmith = Person(id: "david-smith", occupationId: "sci", name: "David Smith", age: 33)
try database.makeRequest(with: sqlInsert(davidSmith)).execute()
```

When joining multiple tables the result is often, although not always, a 
combination of columns from some or or all of the tables. To define an result
with an arbitrary combination of columns we use a struct annotated with 
`@SQLResult`.

```swift
import SwiftQL

@SQLResult PersonOccupation {
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

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    Select(
        result {
            PersonOccupation.SQLReader(
                personId: person.id,
                occupationId: occupation.id,
                personName: person.name,
                occupationName: occupation.name
            )
        }
    )
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

In the select statement we used the `result` function and 
`PersonOccupation.SQLReader` to instantiate a column set which includes fields 
from both the `Person` and `Occupation` tables. 

We can also reference the result in the query:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let row = result {
        PersonOccupation.SQLReader(
            personId: person.id,
            occupationId: occupation.id,
            personName: person.name,
            occupationName: occupation.name
        )
    }
    Select(row)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
    Where(row.personName != "Fred")
}
```

> Tip: SwiftQL does not impose a limit on the  number of tables that can be 
joined in a query.

> Tip: Use `Join.Cross` or `Join.Inner` to perform a cross or inner 
join respectively.

## Group By

Use the group by clause to return aggregate results, or results where a single
row has a computation from multiple records, such as the total number of records
matching some criteria.

Let's define a `@SQLResult` to return the total number of people for each 
occupation:

```swift
import SwiftQL

@SQLResult struct OccupationAggregate {
    var occupationId: String
    var numberOfPeople: Int
}
```

We can write a query to select the person records grouped by their 
`occupationId`, and use the `count()` aggregate function to compute the number
of people for each occupation.

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let row = result {
        OccupationAggregate(
            occupationId: person.occupationId,
            numberOfPeople: person.id.count()
        )
    }
    Select(row)
    From(person)
    GroupBy(person.occupationId)
}
```

SwiftQL currently supports the following aggregate functions:

Function           | Column type    | Usage
-------------------|----------------|-------------------------------------------
`count()`          | Any            | Number of items in the result set.
`min()`            | Any comparable | Minimum value in the result set.
`max()`            | Any comparable | Maximum value in the result set.
`average()`        | Double         | Average (arithmetic mean) of values in the result set.
`sum()`            | Int or Double  | Additive sum of values in the result set.
`groupConcat()`    | String         | Concatenation of all values in the result set.

All of the aggregate functions accept a `distinct` boolean parameter. When set 
to `true`, duplicate values will be discarded and only unique values will be
included in the result set.

> Important: A group by clause must include at least one aggregate term. SwiftQL
currently does not enforce correctness of a query containing a group by clause.

## Having

The having clause is used in conjunction with the group by clause to filter 
groups. Think of like a where clause but operating on groups instead of 
individual rows. As an example we can filter our previous query to only include 
occupations where there are two or more people with that occupation:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    let row = result {
        OccupationAggregate(
            occupationId: person.occupationId,
            numberOfPeople: person.id.count()
        )
    }
    Select(row)
    From(person)
    GroupBy(person.occupationId)
    Having(row.numberOfPeople >= 2)
}
```

## Order By

Query results can be sorted using the order by clause. Use the `ascending` or
`descending` functions on the column or columns to sort by:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.name.ascending())
}
```

To sort by multiple columns, include the columns in the order by clause:

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

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.age.ascending())
    Limit(5)
```

The offset clause is used in conjunction with the limit clause. Offset skips a 
number of rows, and is often used to paginate results from a large result set:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.age.ascending())
    Limit(5)
    Offset(10)
```

## Subqueries

[TODO]

## Union, Union All, Except, Intersect

The result of two or more select statements can be combined into a compund query 
using the union, union all, except, or intersect operators. 

Suppose we have a table representing a family tree, and we want to select the 
mother and father of each member in the tree.

We first define a table representing the family tree:

```swift
@SQLTable struct Family {
    var name: String?
    var mom: String?
    var dad: String?
    var born: Date?
    var died: Date?
}
```

We also define a result set for the name of the family member and their parent:

```swift
@SQLResult struct FamilyMemberParent {
    let name: String?
    let parent: String?
}
```

We can select the mother and father for each family member, then combine the 
results using a `union`.

```swift
let query = sql { schema in
    // Define the tables used in the two queries.
    let familyMom = schema.table(Family.self)
    let familyDad = schema.table(Family.self)

    // Define the result that reads the person's name and their mother's name.
    let momRow = result {
        FamilyMemberParent.SQLReader(name: familyMom.name, parent: familyMom.mom)
    }

    // Define the result that reads the person's name and their fathers's name.
    let dadRow = result {
        FamilyMemberParent.SQLReader(name: familyDad.name, parent: familyDad.dad)
    }

    // Fetch the name of the mother for each person.
    Select(momRow)
    From(familyMom)

    // Use union to append the results of the second query.
    Union()

    // Fetch the name of the father for each person.
    Select(dadRow)
    From(familyDad)
}
```

Using a `UnionAll`, the final result contains the combined results of the first 
query followed by the results of the second query. A `Union` is similar except 
duplicate rows are excluded.

The `Except` operator returns the results from the first query that are not also 
in the second query, which is to say that the row is omitted if it is returned 
by both queries.

The `Intersect` operator returns rows that are present in both queries.

> Tip: All of the select statements used in an compound query must return the 
same data type.

## Common table expressions

Common table expressions are a powerful feature of SQLite which allow SQL to be 
queried in a procedural way. Using common table expressions, SQL statements can 
be encapsulated into separate expressions which can be used as tables in other
select statements within the same query.

To use a common table expression:
1. Call the `commonTableExpression` function to create the common table 
expression, passing a closure that returns a select query.
2. Call the `table` function to identify the common table expression as a table.
3. Call `with` before `select`, to include the common table expression in 
the query.

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
    From(person))
```

This is equivalent to the following SQL:

```sql
WITH 
 personCommonTable AS (
  SELECT
   person.*
  FROM
   Person AS person
  WHERE
   person.occupationId NOTNULL
)
SELECT
 person.*
FROM
 personCommonTable AS person
```

> Note: A common table expression cannot be used direcly in a select, from, or join:

```
let _ = select(personCommonTable) // Error, cannot select from common table expression 
```

### Recursive common table expressions

Recursive common table expressions are common table expressions where the query 
refers to itself. They are commonly used with hierarchical data sets. 

A recursive expression is written as the union of two or more queries, where the 
first query provides the base case, or starting condition, and the remaining 
queries produce subsequent results. 

To create a recursive common table expression use 
`recursiveCommonTableExpression` to create.

For our example let's define a table to represent a hierarchical orag chart for 
a company: 

```swift
@SQLTable struct Org {
    var name: String?
    var boss: String?
}
```

We will also define an `@SQLResult` that we use to refer to the result of the 
recursive common table expression. This essentially defines a 'table' with a 
single column. 

```swift
@SQLResult struct ScalarString {
    var value: String
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

```swift
let query = sql { schema in

    let cte = schema.recursiveCommonTableExpression(ScalarString.self) { schema, cte in
        let org = schema.table(Org.self)
        // Define the initial value for the starting condition.
        let initialResult = result {
            ScalarString.SQLReader(value: "Alice".toNullable())
        }
        Select(initialResult)
        // Union the initial value with successive values.
        Union()
        // Select members from the org whose boss matches the current member
        Select(result { ScalarString.SQLReader(value: org.name) })
        From(org)
        Join.Cross(cte)
        Where(org.boss == cte.scalarValue)
    }
    
    // Select members from the org whose names are returned by the common table expression.
    let org = schema.table(Org.self)
    With(cte)
    Select(org.name)
    From(org)
    Where(org.name.in(cte))
}
```

### Combining recusive common tables with non-recursive common tables

When recursive common tables are used with other non-recursive common 
tables, the recursive common table must appear after the other common tables in 
the `With` statement.

We can now write a query to fetch all living ancestors of 'Alice', using the
family tree table from our earlier example:

```swift
let selectStatement = sql { schema in
    
    let parentOfCommonTable = schema.commonTableExpression { schema in
        let family = schema.table(Family.self)
        let momRow = result {
            FamilyMemberParent.SQLReader(name: family.name, parent: family.mom)
        }
        let dadRow = result {
            FamilyMemberParent.SQLReader(name: family.name, parent: family.dad)
        }
        Select(momRow)
        From(family)
        Union()
        Select(dadRow)
        From(family)
    }
    
    let ancestorOfAliceCommonTable = schema.recursiveCommonTableExpression(ScalarString.self) { schema, this in
        let parentOf = schema.table(parentOfCommonTable)
        Select(result { ScalarString.SQLReader(value: parentOf.parent) })
        From(parentOf)
        Where(parentOf.name == "Alice".toNullable())
        UnionAll()
        Select(result { ScalarString.SQLReader(value: parentOf.parent) })
        From(parentOf)
        Join.Inner(this, on: this.value == parentOf.name)
    }
    
    let ancestorOfAlice = schema.table(ancestorOfAliceCommonTable)
    let family = schema.table(Family.self)
    
    // Note the order of the common tables. The recursive common table must appear after other common tables.
    With(parentOfCommonTable, ancestorOfAliceCommonTable)
    Select(family.name)
    From(ancestorOfAlice)
    Join.Cross(family)
    Where((ancestorOfAlice.value == family.name) && family.died.isNull())
    OrderBy(family.born.ascending())
}
```

Observe the order of definitions. We define an ordinary common table which 
selects the mother and  father for each family member. We then use this common 
table in the recursive common table expression. In the with clause the the 
recursive common table expression is placed last.

> Warning: SwiftQL does not currently enforce the order of common table 
expressions in the with clause. It is the programmer's responsibility to ensure
that the recursive common table expression is always placed last in the with 
clause.
