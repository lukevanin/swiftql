# SwiftQL

SwiftQL lets you you write SQL queries using familiar Swift type-safe syntax. Writing SQL using SwiftQL should feel 
familiar if you have used SQL. Currently SwiftQL supports SQLite's dialect of SQL.

## Getting started:

Assume we have a table defined in the database.

```
CREATE TABLE Person (
    id TEXT NOT NULL,
    occupationId TEXT NULL,
    name TEXT NOT NULL,
    age INT NOT NULL
);
```

We define the table using a struct annotated with `@SQLTable`.

```
import SwiftQL

@SQLTable struct Person {

    var id: String
    
    var occupationId: String?

    var name: String
    
    var age: Int
} 
```

SwiftQL supports `Bool`, `Int`, `Double`, `String`, and `Data` types as well as enums using these types. Support for 
other types can be added as needed. 

The name of the table can be explicitly defined in the SQLTable annotation. If a name is not provided then the name of 
the struct will be used.

```
@SQLTable(name: "People") struct Person {
    ...
}
```

This table can be used in a select query:

```
let schema = SQLSchema()
let person = schema.table(Person.self)
// SELECT person.* FROM Person AS person;
let statement = select(person).from(person) 
```

1. First we create a schema, which provides tables from the database.
2. Second we create a reference for the tables we want to use in the query. 
3. Finally we create the select statement. 

Tables can be given an explicit alias:

```
let schema = SQLSchema()
let people = schema.table(Person.self, as: "people")
// SELECT people.* FROM Person AS people
let statement = select(people).from(people) 
```

The alias is only used in the SQL that is generated and does not affect the Swift code. 

Note: SwiftQL does not perform any validation on aliases that are provided to it, it is the programmer's responsibility
to ensure that aliases do not conflict with other aliases. 

SwiftQL provides the `sqlQuery` convenience function which can be used to wrap SQL statements, helping to keep code
organized:

```
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    // SELECT person.* FROM Person AS person 
    return select(person).from(person)
}
``` 

SwiftQL also supports a result builder syntax that is similar to SwiftUI, which lets you to write SQL statements in a 
style that more closely resembles SQL text. To use the result builder syntax use the `sql` closure:

```
let statement = sql { schema in
    let person = schema.table(Person.self)
    // SELECT person.* FROM Person AS person 
    Select(person)
    From(person)
}
```

To execute the query we need to run it against a database instance. SwiftQL currently provides support for SQLite using
GRDB.

```
let database = GRDBDatabase(url: <url to SQLite database file>)
let request = database.makeRequest(with: statement)
let rows = request.fetchAll()
```

1. We need to instantiate the database.
2. Create a request for the query.
3. Execute the query to fetch the results. This example returns an array of `Person` objects, one for each entry in the
`Person` table in the database.  
 
Once the request is created it can be reused as many times as needed. The SQL statement is created only once and then 
cached by the database so that queries can reused without extra overhead.

## Variable parameters

1. Define a variable parameter using the schema `binding` function.
2. Use the parameter in a SQL expression.
3. Set the value for the parameter on the request.
4. Execute the request.

```
let schema = SQLSchema()

// 1. Define the nameParameter
let nameParameter = schema.binding(of: String.self)
let person = schema.table(Person.self)

// 2. Use nameParameter in an expression.
let statement = select(person).from(person).where(person.name == nameParameter)
let sql = encoder.makeSQL(statement)
var request = database.makeRequest(with: statement)

// 3. Set the value for the parameter on the request.
request.set(nameParameter, "John Doe")
let rows = try request.fetchAll()
```

Parameters can also be created by instantiating a `SQLNamedBindingReference<T>` directly. The code below is equivalent 
to the previous example:

*Functional syntax:*
```
// 1. Define the nameParameter
let nameParameter = SQLNamedBindingReference<String>(name: "name")
let statement = sqlQuery { schema in
    let person = schema.table(Person.self)
    // 2. Use nameParameter in an expression.
    return select(person).from(person).where(person.name == nameParameter)
}
let sql = encoder.makeSQL(statement)
var request = database.makeRequest(with: statement)
// 3. Set the value for the parameter on the request.
request.set(nameParameter, "John Doe")
let rows = try request.fetchAll()
```

*Result builder syntax:*
```
// 1. Define the nameParameter
let nameParameter = SQLNamedBindingReference<String>(name: "name")
let statement = sql { schema in
    let person = schema.table(Person.self)
    // 2. Use nameParameter in an expression.
    Select(person)
    From(person)
    Where(person.name == nameParameter)
}
let sql = encoder.makeSQL(statement)
var request = database.makeRequest(with: statement)
// 3. Set the value for the parameter on the request.
request.set(nameParameter, "John Doe")
let rows = try request.fetchAll()
```


## Simple queries

SwiftQL supports `where`, `order`, `group`, `limit`, and `offset` clauses. 

Here is an example of a where clause:

*SQL:*
```
SELECT person.* 
FROM Person AS person
WHERE person.name == 'John Doe';
```

*Functional syntax:* 
```
let _ = sqlQuery {
    let person = $0.table(Person.self)
    return select(person)
        .from(person)
        .where(person.name == "John Doe")
}
```

*Result builder syntax:*
```
let _ = sql {
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "John Doe")
}
```

Here is a more complex boolean expression:

*SQL:*
```
SELECT person.* 
FROM Person AS person 
WHERE (person.name == 'John Doe') OR (person.age == 25);
```

*Functional syntax:* 
```
let _ = sqlQuery {
    let person = $0.table(Person.self)
    return select(person)
        .from(person)
        .where((person.name == "John Doe") || (person.age == 25))
}
```

*Result builder syntax:*
```
let _ = sqlQuery {
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    Where((person.name == "John Doe") || (person.age == 25))
}
```

*Note that the `||` is the boolean __or__ operator used by Swift, and is __not__ the string concatenation used by 
SQLite. SwiftQL prefers Swift syntax and conventions where possible.*

We can also specify the order of results. Call the `ascending` or `descending` function on the property to specify the 
order:

*SQL:*
```
SELECT person.* 
FROM Person AS person 
ORDER BY person.name ASC, person.age DESC
```

*Functional syntax:*
```
let _ = sqlQuery { 
    let person = $0.table(Person.self)
    let _ = select(person)
        .from(person)
        .orderBy(person.name.ascending(), person.age.descending())
}
``` 

*Result builder syntax:*
```
let _ = sqlQuery { 
    let person = $0.table(Person.self)
    Select(person)
    From(person)
    OrderBy(person.name.ascending(), person.age.descending())
```

The number of items can be constrained using limit, and limit with an offset:

```
let _ = sqlQuery { 
    let person = $0.table(Person.self)
    // SELECT person.* 
    // FROM Person AS person 
    // LIMIT 10
    let _ = select(person)
        .from(person)
        .limit(10) 
}

let _ = sqlQuery { 
    let person = $0.table(Person.self)
    // SELECT person.* 
    // FROM Person AS person 
    // LIMIT 10
    // OFFSET 30
    let _ = select(person)
        .from(person)
        .limit(10)
        .offset(30)
}
```

## Type conversion

SQL written in SwiftQL are strictly typed. It is not possible to use different types in an expression. The following 
code attempts to compare a string with an integer, which would result in a compile time error. 
  
```
let _ = sqlQuery { 
    let person = $0.table(Person.self)
    let _ = select(person).from(person).where((person.name == 12) // Error, string cannot be compared to an integer
}
```

[TODO: Specify type casting]

## Complex queries

Multiple tables can be joined in a single query. SwiftQL currently supports inner joins and left outer joins. Up until 
now we have seen how to fetch results from a single table. 

To join a table, use the `innerJoin` or `leftJoin` method on the query, passing a closure which specifies the 
constraints for the join. 

*SQL:*
```
SELECT person.* 
FROM Person AS person
INNER JOIN Occupation ON Occupation.id == Person.occupationId

```

*Functional syntax:*
```
let _ = sqlQuery { 
    let person = $0.table(Person.self)
    let occupation = $0.table(Occupation.self)
    return select(person)
        .from(person)
        .innerJoin(occupation, on: occupation.id == person.occupationId)
}
```

*Result builder syntax:*
```
let _ = sqlQuery { 
    let person = $0.table(Person.self)
    let occupation = $0.table(Occupation.self)
    Select(person)
    From(person)
    Join.Inner(occupation, on: occupation.id == person.occupationId)
}
```

Note: When using the result builder, the type of join is specified as using `Join.Inner`, `Join.Outer`, or `Join.Left`.

Right joins are not currently supported by SwiftQL.  

Often when tables are joined the results are a combination of multiple tables. We can indicate an object that used as a 
result of a select using the `@SQLResult` annotation instead of `@SQLTable`:

```
@SQLResult struct PersonOccupation {

    let person: String
    
    let occupation: String
}
```

We use the `columns` static method to define how the columns from multiple table are mapped to our `PersonOccupation`:

```
let _ = sql {
    let person = $0.table(Person.self)
    let occupation = $0.nullableTable(Occupation.self)
    let result = PersonOccupation.columns(
        person: person.name,
        occupation: occupation.name
    )
    // SELECT person.name AS _person, occupation.name AS _occupation 
    // FROM Person AS person
    // LEFT JOIN Occupation AS occupation ON Occupation.id == Person.occupationId
    Select(result)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

Here we are using a nullable table to indicate that the columns could be null in the result set, which can occur when
a table is joined using a left join.  

Results can be used in `where`, `order by`, `group by`, and `limit` clauses like any other table. 

```
let _ = sqlQuery {
    let person = $0.table(Person.self)
    let occupation = $0.nullableTable(Occupation.self)
    let result = PersonOccupation.columns(
        person: person.name,
        occupation: occupation.name
    )
    // SELECT person.name AS _person, occupation.name AS _occupation
    // FROM Person AS person 
    // LEFT JOIN Occupation As occupation ON occupation.id == person.occupationId
    // WHERE _occupation == 'Engineer'
    Select(result)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
    Where(result.occupation == "Engineer")
}
```

## Aggregate Queries (Group By)

SwiftQL currently supports the following aggregate functions:

- `count`
- `min`
- `max`
- `average`

```
@SQLResult struct OccupationCount {

    let occupation: String
    
    let numberOfPeople: Int
}

let _ = sqlQuery {
    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)

    let result = OccupationCount.columns(
        occupation: occupation.name,
        numberOfPeople: count(person.id)
    )

    return select(result)
        .from(person))
        .leftJoin(Occupation.self, on: person.occupationId == occupation.id }
        .groupBy(occupation.id)
}
```

Note: SwiftQL currently does not enforce any constraints on the correctness of group-by statements. It is the 
programmer's responsibility ensure that the columns and group by statement are correct.   

## Subqueries

Subqueries can be used anywhere that a column is used, as well as in the source in a from or join expression.

```
@SQLResult struct OccupationCount {

    let occupation: String
    
    let numberOfPeople: Int
}
```

*SQL:*
```
SELECT 
 occupation.name AS _occupation
 (
  SELECT 
   COUNT(person.id) 
  FROM 
   Person as person 
  WHERE 
   person.occupationId == occupation.id
 ) AS numberOfPeople
FROM 
 Occupation AS occupation
```

*Result builder syntax:*
```
let _ = sql { schema in

    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)

    let result = OccupationCount.columns(
        occupation: occupation.name,
        numberOfPeople: sqlSubquery { _ in
            Select(count(person.id))
            From(person)
            Where(person.occupationId == occupation.id)
        }
    )
    Select(result)
    From(occupation)
}
```

*Result builder syntax:*
```
let _ = sql { schema in

    let person = schema.table(Person.self)
    let occupation = schema.table(Occupation.self)

    let result = result {
        OccupationCount.SQLReader(
            occupation: occupation.name,
            numberOfPeople: sqlSubquery { _ in
                Select(count(person.id))
                From(person)
                Where(person.occupationId == occupation.id)
            }
        )
    }
    Select(result)
    From(occupation)
}
```

[TODO: Describe subqueries: column, FROM, and IN]

## Complex expressions

### `coalesce`

`coalesce` behaves similarly to the null coalescing operator '??' in Swift, and is used to provide a default value for 
an optional or nullable expression. 

```
let _ = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let result = PersonOccupation.columns(
        person: person.name,
        occupation: occupation.name.coalesce("No occupation") 
    )
    // SELECT 
    //  person.name AS _person, 
    //  COALESCE(occupation.name, 'No occupation') AS _occupation 
    // FROM 
    //  Person AS person 
    // LEFT JOIN 
    //  Occupation AS occupation
    // ON 
    //  occupation.id == person.occupationId
    Select(result)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

### `iif`

The `iif` function is used to implement a simple if-then-else:

```
let _ = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let result = PersonOccupation.columns(
        person: person.name,
        occupation: iif(
            occupation.name.isNull(), 
            then: "Unemployed", 
            else: "Employed"
        )
    )
    // SELECT 
    //  person.name AS _person, 
    //  IIF(occupation.name ISNULL, 'Unemployed', 'Employed') AS _occupation 
    // FROM 
    //  Person AS person 
    // LEFT JOIN 
    //  Occupation AS occupation
    // ON 
    //  occupation.id == person.occupationId
    Select(result)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

### `case-when-then`

The `onCase-when-then-else` can be used to create conditional expressions matching more than one condition. SwiftSQL 
provides two variants. 

The first variant uses a constant term to match and behaves similar to a `switch` statement in Swift, where multiple
patterns are compared against a single condition.

```
let statement = sql { schema in
    let occupation = schema.table(Occupation.self)
    let result = OccupationColor.columns(
        occupation: occupation.name,
        color: switchCase(occupation.name)
            .when("Engineer", then: "Red")
            .when("Scientist", then: "Blue")
    )
    // SELECT 
    //  occupation.name AS _occupation, 
    //  (
    //   CASE occupation.name 
    //    WHEN 'Engineer' THEN 'Red' 
    //    WHEN 'Scientist' THEN 'Blue' 
    //   END
    //  ) AS _color 
    // FROM 
    //  Occupation AS occupation
    Select(result)
    From(occupation)
}
let sql = encoder.makeSQL(statement)
let rows = try database.makeRequest(with: statement).fetchAll()
```

The second variant behaves like an `if` statement with multiple boolean conditions, and uses the result from the first 
true boolean condition.

```
let statement = sql { schema in
    let occupation = schema.table(Occupation.self)
    let result = OccupationColor.columns(
        occupation: occupation.name,
        color: when(occupation.name == "Artist", then: "Cyan")
    )
    // SELECT 
    //  occupation.name AS _occupation, 
    //  (
    //   CASE 
    //    WHEN (occupation.name == 'Artist') THEN 'Cyan' 
    //   END
    //  ) AS _color 
    // FROM 
    //  Occupation AS occupation
    Select(result)
    From(occupation)
}
```

Both variants produce an optional type by default, and return a nil result if none of the conditions match. We can
use an `else` to specify a default expression which is used instead, which also changes the result to a non-optional
type.

```
let statement = sql { schema in
    let occupation = schema.table(Occupation.self)
    let result = OccupationColor.columns(
        occupation: occupation.name,
        color: switchCase(occupation.name)
            .when("Engineer", then: "Red")
            .when("Scientist", then: "Blue")
            .else("Green")
    )
    // SELECT 
    //  occupation.name AS _occupation, 
    //  (
    //   CASE occupation.name 
    //    WHEN 'Engineer' THEN 'Red' 
    //    WHEN 'Scientist' THEN 'Blue' 
    //    ELSE 'Green' 
    //   END
    //  ) AS _color 
    // FROM 
    //  Occupation AS occupation
    Select(result)
    From(occupation)
}
let sql = encoder.makeSQL(statement)
let rows = try database.makeRequest(with: statement).fetchAll()
```

## Generic type parameters:

You can create tables and results which use generic type parameters. Generic parameters can use the intrinsic types 
including `Bool`, `Int`, `Double`, `String` and `Data`, as well any custom type defined as an `SQLCustomType`.

We define a table with a generic `Value` parameter:

```
@SQLTable(name: "Generic")
struct GenericTable<Value>: Identifiable where Value: SQLLiteral & SQLExpression {
    var id: String
    var value: Value
}
```

We can create, insert, and query our table using a `String` generic parameter...

```
let createStatement = sqlCreate(GenericTable<String>.self)
try database.makeRequest(with: createStatement).execute()

let insertStatement = sqlInsert(GenericTable(id: "foo", value: "Foo"))
try database.makeRequest(with: insertStatement).execute()

let selectStatement = sqlQuery { schema in
    let table = schema.table(GenericTable<String>.self)
    return select(table).from(table)
}
try database.makeRequest(with: selectStatement).fetchAll()
```

... or an `Int`:

```
let createStatement = sqlCreate(GenericTable<Int>.self)
try database.makeRequest(with: createStatement).execute()

let insertStatement = sqlInsert(GenericTable(id: "foo", value: 42))
try database.makeRequest(with: insertStatement).execute()

let selectStatement = sqlQuery { schema in
    let table = schema.table(GenericTable<Int>.self)
    return select(table).from(table)
}
try database.makeRequest(with: selectStatement).fetchAll()
```

We can also define a custom type. In the example below we define a custom `Wrapper` type which wraps a `UUID`:  

```
struct Wrapper: SQLCustomType, Equatable {
    
    public typealias T = Self
    
    var wrappedValue: UUID
    
    public init(_ wrappedValue: UUID) {
        self.wrappedValue = wrappedValue
    }
    
    public init(reader: SQLColumnReader, at index: Int) {
        wrappedValue = UUID(uuidString: reader.readText(at: index))!
    }
    
    public func bind(context: inout SQLBindingContext) {
        context.bindText(value: wrappedValue.uuidString)
    }
    
    public func makeSQL(context: inout SQLBuilder) {
        context.text(wrappedValue.uuidString)
    }
    
    public static func wrapSQL(context: inout SQLBuilder, builder: (inout SQLBuilder) -> Void) {
        builder(&context)
    }
    
    public static func sqlDefault() -> Wrapper {
        Wrapper(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }
}
```

The `Wrapper` can now be used as a generic parameter:

```
let createStatement = sqlCreate(GenericTable<Wrapper>.self)
try database.makeRequest(with: createStatement).execute()

let insertStatement = sqlInsert(GenericTable(id: "foo", value: Wrapper(testValue)))
try database.makeRequest(with: insertStatement).execute()

let selectStatement = sqlQuery { schema in
    let table = schema.table(GenericTable<Wrapper>.self)
    return select(table).from(table)
}
try database.makeRequest(with: selectStatement).fetchAll()
```

## Union, Union All, Except, Intersect

The result of two or more select statements can be combined into a compund query using the union, union all, except, 
or intersect operators. 

```
// Define the table.
@SQLTable struct Family {
    var name: String?
    var mom: String?
    var dad: String?
    var born: Date?
    var died: Date?
}

let selectExpression = sql { schema in
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

Using a UnionAll, the final result contains the combined results of the first query followed by the results of the 
second query. A Union is similar except duplicate rows are excluded.

The Except operator returns the results from the first query that are not also in the second query, which is to say that 
the row is omitted if it is returned by both queries.

The Intersect operator returns rows that are present in both queries.

Tip: All of the select statements used in an compound query must return the same data type.

## Common Table Expressions

To use a common table expression:
1. Call the `commonTable` function to create the common table expression, passing a closure that returns a select query.
2. Call the `table` function to identify the common table expression as a table.
3. Call `with` before `select`, to include the common table expression in the query.

*SQL:*
```
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

*Functional syntax:*
```
let _ = sqlQuery { schema in
    let personCommonTable = schema.commonTable { schema in
        let person = schema.table(Person.self)
        return select(person)
            .from(person)
            .where(person.occupationId.notNull())
    }
    let person = schema.table(personCommonTable)
    let _ = with(personCommonTable)
        .select(person)
        .from(person))
```

*Result builder syntax:*
```
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

Note: A common table expression cannot be used direcly in a select, from, or join:

```
let _ = select(personCommonTable) // Error, cannot select from common table expression 
```

## Recursive common table expressions

Recursive common table expressions are common table expressions where the query refers to itself. They are commonly used 
with hierarchical data sets. 

A recursive expression is written as the union of two or more queries, where the first query provides the base case, or 
starting condition, and the remaining queries produce subsequent results. 

Refer to the SQLite manual for futher details.  

To create a recursive common table expression use `recursiveCommonTable` or `recursiveCommonTableExpression` to create 
a query using the functional or result builder syntax respectively.

```
@SQLTable struct Org {
    var name: String?
    var boss: String?
}

// Define an SQLResult that we use to refer to the result of the recursive common table expression. 
@SQLResult struct SQLScalarResult<T> where T: SQLLiteral {
    var scalarValue: T
}

typealias ScalarString = SQLScalarResult<String?>

// Create an expression which returns all of the members of the organisation from Alice and everyone below her.
let expression = sql { schema in
    // Note 1: We need to pass in the return type when creating the expression.
    // Note 2: The closure provides a second parameter which we can use to refer to the expression recursively. 
    let cte = schema.recursiveCommonTableExpression(ScalarString.self) { schema, cte in
        let org = schema.table(Org.self)
        // Define the initial value for the starting condition.
        let initialResult = result {
            Scalar.SQLReader(scalarValue: "Alice".toNullable())
        }
        Select(initialResult)
        // Union the initial value with successive values.
        Union()
        // Select members from the org whose boss matches the current member
        Select(result { Scalar.SQLReader(scalarValue: org.name) })
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

When recursive common tables are used with other non-recursive common tables, the recursive common table must 
appear after the other common tables in the `With` statement:

```
// Fetch all living ancestors of Alice.
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
    
    let ancestorOfAliceCommonTable = schema.recursiveCommonTableExpression(Scalar.self) { schema, this in
        let parentOf = schema.table(parentOfCommonTable)
        Select(result { Scalar.SQLReader(scalarValue: parentOf.parent) })
        From(parentOf)
        Where(parentOf.name == "Alice".toNullable())
        UnionAll()
        Select(result { Scalar.SQLReader(scalarValue: parentOf.parent) })
        From(parentOf)
        Join.Inner(this, on: this.scalarValue == parentOf.name)
    }
    
    let ancestorOfAlice = schema.table(ancestorOfAliceCommonTable)
    let family = schema.table(Family.self)
    
    // Note the order of the common tables. The recursive common table must appear after other common tables.
    With(parentOfCommonTable, ancestorOfAliceCommonTable)
    Select(family.name)
    From(ancestorOfAlice)
    Join.Cross(family)
    Where((ancestorOfAlice.scalarValue == family.name) && family.died.isNull())
    OrderBy(family.born.ascending())
}
```


## Insert 

To insert a row into a table, create an insert statement using the `sqlInsert` function, then execute the statement
on the database:

*SQL:*
```
INSERT INTO Test 
 (id,value) 
VALUES 
  ('foo',42)
```

*Functional syntax:*
```
let test = TestTable(id: "foo", value: 42)
let insertStatement = sqlInsert(test)
try database.makeRequest(with: insertStatement).execute()
```

*Result builder syntax:*
```
let instance = TestTable(id: "foo", value: 42)
let expression = sql { schema in
    let t = schema.into(TestTable.self)
    Insert(t)
    Values(instance)
}
try database.makeRequest(with: insertStatement).execute()
```

Insert statements can also be parameterized using the variant of `sqlInsert` that accepts a builder closure:

```
struct InsertTest {
    
    private static let idParameter = SQLNamedBindingReference<String>(name: "id")

    private static let valueParameter = SQLNamedBindingReference<Int>(name: "value")

    private static let statement: any SQLInsertStatement<TestTable> = sqlInsert {
        let table = $0.into(TestTable.self)
        return insert(table).values(
            TestTable.MetaInsert(
                id: idParameter,
                value: valueParameter
            )
        )
    }
    
    private let request: SQLWriteRequest
    
    init(database: SQLDatabase) {
        request = database.makeRequest(with: Self.statement)
    }
    
    func execute(_ entity: TestTable) throws {
        var request = request
        request.set(Self.idParameter, entity.id)
        request.set(Self.valueParameter, entity.value)
        try request.execute()
    }
}

let insertTest = InsertTest(database: database)
try insertTest.execute(TestTable(id: "foo", value: 42))
```

Note: SwiftQL does not currently support subqueries on insert statements.

## Update

To update a row in a table, create an update statement using the `sqlUpdate` function, then execute the statement:

```
struct UpdateTest {
    
    private static let idParameter = SQLNamedBindingReference<String>(name: "id")

    private static let valueParameter = SQLNamedBindingReference<Int>(name: "value")

    private static let statement: any SQLUpdateStatement<TestTable> = sqlUpdate {
        let table = $0.into(TestTable.self)
        return update(table, set: TestTable.MetaUpdate(
            value: valueParameter
        ))
        .where(table.id == idParameter)
    }
    
    private let request: SQLWriteRequest
    
    init(database: SQLDatabase) {
        request = database.makeRequest(with: Self.statement)
    }
    
    func execute(id: String, value: Int) throws {
        var request = request
        request.set(Self.idParameter, id)
        request.set(Self.valueParameter, value)
        try request.execute()
    }
}

let updateTest = UpdateTest(database: database)
try updateTest.execute(id: "foo", value: 69)
```

The update statement can also be written using the result builder syntax:

```
private static let statement = sql {
    let table = $0.into(TestTable.self)
    Update(table)
    Setting<TestTable> { row in
        row.value = valueParameter
    }
    Where(table.id == idParameter)
}
``` 

When using the result builder the `Setter` clause requires a type parameter that must match the return type of the 
SQL expression. The closure passed to the setter has a single `row` parameter which is used to assign the values to 
update. Any values that are assigned to the row will be included in the update statement. Values that are not assigned
will be omitted from the update and will not be changed. 

Tip: The row parameters are "write only", which means they cannot be used on the right-hand side of the `=` assignment 
operator. If you would like to use the field in the expression, say to increment an existing value, use the field from 
the table:

```
private static let statement = sql {
    let table = $0.into(TestTable.self)
    Update(table)
    Setting<TestTable> { row in
        // Incorrect ❌:
        // row.value = row.value + 1
        
        // Correct ✔️:
        row.value = table.value + 1
    }
    Where(table.id == idParameter)
``` 

## Create

To create a table, use the `sqlCreate` function to create a statement, then execute the statement on the database:

```
// CREATE TABLE IF NOT EXISTS Test (
//  id NOT NULL,
//  value NOT NULL
// )
let createStatement = sqlCreate(Test.self)
try database.makeRequest(with: createStatement).execute()
```

You can also create a table using a select statement. Use the `as` method, passing a closure that returns a 
select statement:

*Functional syntax:*
```
let createStatement = sqlCreate { schema in
    let t = schema.create(Temp.self)
    return create(t).as { schema in
        let employee = schema.table(EmployeeTable.self)
        let row = result {
            Temp.SQLReader(
                id: employee.id,
                value: employee.name
            )
        }
        return select(row).from(employee)
    }
}
try database.makeRequest(with: createStatement).execute()
```

*Result builder syntax:*
```
let expression = sql { schema in
    let t = schema.create(Temp.self)
    Create(t)
    As { schema in
        let employee = schema.table(EmployeeTable.self)
        let row = result {
            Temp.SQLReader(
                id: employee.id,
                value: employee.name
            )
        }
        Select(row)
        From(employee)
    }
}
```

## Custom types

SwiftQL allows the following Swift types to be used as SQL columns and in SQL expressions: `Bool`, `Int`, `Double`, 
`String`, `Data`. Support can be added for other types can be added as needed, including Foundation types, or your own 
custom types. 

To allow a custom type to be used in SQL it needs to conform for the `SQLCustomType` protocol, and optionally one or 
more of the following:
- `SQLEquatable`: Allow the type to be used in equality expressions (e.g. `==` and `!=`)
- `SQLComparable`: Allow the type to be used in comparison expressions (e.g. `>`, `<`, `>=`, `<=`)

Custom types are stored in the SQL database by as one of the native representations used by SQLite: `Int`, `Double`, 
`String`, or `Data`. Custom types need to convert to and from one of these types when being written to and read from 
the database.

Below is an example of how the Foundation `UUID` type might be stored in the database as a string:  

```
extension UUID: SQLCustomType, SQLEquatable, SQLComparable {
    
    public typealias T = Self
    
    // Defines how the type is deserialized from a SQL query result. We instantiate a UUID from the string 
    // representation stored in the database.
    public init(reader: SQLColumnReader, at index: Int) {
        let rawValue = reader.readText(at: index)
        self = UUID(uuidString: rawValue)!
    }
    
    // Defines how the value is as a parameter. We use the string representation of the UUID.  
    public func bind(context: inout SQLBindingContext) {
        context.bindText(value: uuidString)
    }
    
    // Defines how the type is serialized in an SQL expression. Again we use the literal string representation.
    public func makeSQL(context: inout SQLBuilder) {
        context.text(self.uuidString)
    }
    
    // Defines a default or placeholder value to use when the value is available. We return a constant default value.
    public static func sqlDefault() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
}
```

This extension allows `UUID` type to be used in SQL expressions, such as a where clause:

```
@SQLTable struct Employee {
    let id: UUID
    let name: String
}

let _ = sqlQuery { schema in
    let employee = schema.table(Employee.self)
    // SELECT
    //  employee.*
    // FROM
    //  Employee AS employee
    // WHERE
    //  employee.id == '536d0033-65a0-4142-8c21-99b6b891c4e8'
    return select(employee)
        .from(employee)
        .where(employee.id == UUID(uuidString: "536d0033-65a0-4142-8c21-99b6b891c4e8"))
}
```
 
UUIDs were quite easy to support as there is a direct mapping between the type (`UUID`) and the representation 
(`String`). Below is another example which shows support for `Date` which stores the date as a string. The `unixepoch` 
function is used to convert the text representation to a unix timestamp.       

```
extension Date: SQLCustomType, SQLEquatable, SQLComparable {
    
    // Define a formatter to use to encode and decode the date.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter
    }()
    
    public typealias T = Self
    
    // Decode the date from an SQL result.
    public init(reader: SQLColumnReader, at index: Int) {
        let rawValue = reader.readText(at: index)
        self = Self.dateFormatter.date(from: rawValue)!
    }
    
    // Bind the date to an SQL expression.
    public func bind(context: inout SQLBindingContext) {
        let rawValue = Self.dateFormatter.string(from: self)
        context.bindText(value: rawValue)
    }
    
    // Encode the date expression to an SQL string.
    public func makeSQL(context: inout SQLBuilder) {
        Self.wrapSQL(context: &context) { context in
            context.text(Self.dateFormatter.string(from: self))
        }
    }
    
    // The wrap function applies a constant expression to every Date value. Here it is used to convert the date to a 
    // unix timestamp to be used in comparisons and calculations.
    public static func wrapSQL(context: inout SQLBuilder, builder: (inout SQLBuilder) -> Void) {
        context.simpleFunction(name: "unixepoch") { context in
            context.listItem { context in
                builder(&context)
            }
        }
    }
    
    // Return a constant date by default.
    public static func sqlDefault() -> Date {
        Date(timeIntervalSince1970: 0)
    }
}
```

The wrap function is applied to every occurance of the custom type. The default behaviour is to return the original 
expression. For our custom date type, we wrap dates with  a call to SQLite's built in `unixepoch` function to convert 
the date to a unix timestamp for comparison:  


```
@SQLTable struct Invoice {
    let id: Int
    let dueDate: Date
}

let dateParameter = SQLNamedBindingReference<Date>(name: "date")

let _ = sqlQuery { schema in
    let invoice = schema.table(Invoice.self)
    // SELECT
    //  invoice.*
    // FROM
    //  Invoice AS invoice
    // WHERE
    //  unixepoch(invoice.dueDate) <= unixepoch(:date) 
    return select(invoice)
        .from(invoice)
        .where(invoice.dueDate < dateParameter)
}
```

## Custom functions

SwiftQL allows custom functions to be installed on the database and called from SQL expressions at runtime in a type 
safe manner.

To define a custom function, create a class or struct that conforms to the `SQLCustomFunction` function protocol, and
implement the ` definition`, `makeSQL` and `execute` methods. The constructor accepts parameters which are passed to the 
function at runtime.

```
public struct HaversineDistance: SQLCustomFunction {
    
    public typealias T = Double
    
    // Define the function signature. SQLite uses the name and number of parameters to differentiate functions.
    public static let definition = SQLCustomFunctionDefinition(
        name: "haversineDistance",
        numberOfArguments: 4
    )
    
    // Define parameters which are passed to the function at runtime.
    private let fromLatitude: any SQLExpression
    private let fromLongitude: any SQLExpression
    private let toLatitude: any SQLExpression
    private let toLongitude: any SQLExpression
    
    init(
        fromLatitude: any SQLExpression<Double>,
        fromLongitude: any SQLExpression<Double>,
        toLatitude: any SQLExpression<Double>,
        toLongitude: any SQLExpression<Double>
    ) {
        self.fromLatitude = fromLatitude
        self.fromLongitude = fromLongitude
        self.toLatitude = toLatitude
        self.toLongitude = toLongitude
    }
    
    // Define how the function is formatted into an SQL expression.
    public func makeSQL(context: inout SQLBuilder) {
        context.simpleFunction(name: Self.definition.name) { context in
            context.listItem(expression: fromLatitude.makeSQL)
            context.listItem(expression: fromLongitude.makeSQL)
            context.listItem(expression: toLatitude.makeSQL)
            context.listItem(expression: toLongitude.makeSQL)
        }
    }
    
    // Define the implementation details for how the function works. This is called at runtime from SQL, and the results
    // are returned to SQL.
    public static func execute(reader: SQLColumnReader) throws -> Double {
        let latA = radians(degrees: reader.readReal(at: 0))
        let lonA = radians(degrees: reader.readReal(at: 1))
        let latB = radians(degrees: reader.readReal(at: 2))
        let lonB = radians(degrees: reader.readReal(at: 3))
        return acos(sin(latA) * sin(latB) + cos(latA) * cos(latB) * cos(lonB - lonA)) * 6371
    }
    
    private static func radians(degrees: Double) -> Double {
        (degrees / 180) * .pi
    }
}
```

Once the function is defined it needs to be installed on the database. For GRDB this can be done by adding the function
in the configuration, or by using the `GRDBDatabaseBuilder` provided by SwiftQL:

```
// Create the builder.
var config = Configuration()
var builder = try GRDBDatabaseBuilder(url: url, configuration: config)

// Add the custom function defined above.
builder.addFunction(HaversineDistance.self)

// Instantiate the database.
let database = try builder.build()
``` 

The function can be used in any expression of the same type:

```
@SQLTable struct Restaurant {
    let name: String
    let latitude: Double
    let longitude: Double
}

@SQLResult struct NearbyRestaurant {
    let name: String
    let distance: Double
}

let myLatitude = SQLNamedBindingReference<Double>(name: "myLatitude")
let myLongitude = SQLNamedBindingReference<Double>(name: "myLongitude")
let statement = sql { schema in
    let restaurant = schema.table(Restaurant.self)
    let result = NearbyRestaurant.column(
        name: restaurant.name,
        distance: HaversineDistance(
            fromLatitude: myLatitude,
            fromLongitude: myLongitude,
            toLatitude: restaurant.latitude,
            toLongitude: restaurant.longitude
        ).round(to: 2)
    )
    // SELECT
    //  restaurant.name AS _name,
    //  ROUND(haversineDistance(:myLatitude, :myLongitude, restaurant.latitude, restaurant.longitude), 2) AS _ distance
    // FROM
    //  Restaurant AS restaurant
    // ORDER BY
    //  _distance ASC
    Select(result)
    From(restaurant)
    OrderBy(result.distance.ascending())
}
var request = database.makeRequest(with: statement)
request.set(myLatitude, -33.877873677687894)
request.set(myLongitude, 18.488075015723)
let _ = try request.fetchAll()
``` 


## TODO

Below are some remaining tasks and outstanding features:

### Column aliases
Only use explicit column aliases when the column is an expression.

### Function style
Currently some functions are defined as global functions (e.g. `max(someColumn)`), while others are
defined on expressions (e.g. `somecolumn.max()`). One style should be used for all expressions. Global function syntax 
has the benefit of being more readable (e.g. `max(age)` reads intuitively as "the maximum age"), whereas `age.max()` is
more cubersome as "the age, oh which by the way is the maximum one"). Global functions are harder to discover (e.g. how
would the programmer know that the `soundex` function can be used for SQL string expressions without resorting to 
looking at documentation). Discoverability can be improved by installing functions on global enum or struct which acts 
as a namespace, (e.g. `SQL.soundex(...)`), although this adds boilerplate and noise.   

### Type casting
Allow expressions to be cast to different types. e.g. `12.cast(to: String.self)` should cast the 
Real number `12` to the string `'12'`.

### Implement all SQLite built-in functions and operators
Currently a limited number of functions and operators have been 
implemented. These can be added simply by defining relevant marshalling functions in Swift.

### Select composite objects
Allow whole result/tables to be selected in expressions, e.g.

```
@SQLTable struct Company {

}

@SQLTable struct Employee {

}

@SQLResult struct EmployeeCompany {
    let employee: Employee
    let company: Company
}

let employee = schema.table(Employee.self)
let company = schema.table(Company.self)
let result = result {
    EmployeeCompany(
        employee: employee,
        company: company
    )
}
```

### Null coalescing operator `??`
Currently null coalescing is implemented using the `colesce` function. The `??` operator was implemented but resulted in
ambiguous Swift expressions in some places (e.g. passing parameters to GRDB). Further investigation is needed.

### INSERT...SELECT and UPDATE...SELECT
It would be useful to support SELECT clauses within INSERT and UPDATE statements. This should be relatively low effort 
as it requires adding support for existing SELECT  syntax in the relevant `SQL*Statement` classes. There may be some 
complications in using column references from the statements in the nested select statements.

### Upsert and Delete statements
SwiftQL should support UPSERT (UPDATE OR INSERT).

### Common tables
Support materialized and non-materialized tables. 

### Safer Group By
Make group by statements safer. Statements using a group by behave differently to other statements and imply constraints
on how columns can be used in the select clause: Columns need to be used in the group by clause, or use an aggregate 
function. Bare columns are allowed in SQLite in some cases (e.g. when using min or max aggregate functions), although
their behaviour is undefined in some cases. Currently it is the programmer's responsibility to ensure that these rules
are adhered to. It would be helpful to enforce or guide some of the constraints to reduce the chance of creating an 
illegal statement. 

A possible solution might be to generate a new meta type (MetaGroupResult) which is used in group by clauses. The meta 
type would define aggregate column types (SQLAggregateColumnReference) instead of the usual bare column references. A 
new group function wrapper (group { ... }) can be used to create statements that return a group result. Statements using
a group clause can only be used inside the function. 

### Implicit create
Create tables if they do not exist yet, when they are first used.

### Implicit migrations
It can be useful to automatically migrate data from existing tables when the table struct changes. Migration may 
involve:
- renaming, adding, and removing columns
- changing the the type of existing columns
- changing foreign and primary key constraints on columns

### Define primary and foreign keys on structs
- Used to generate table create statements.
- Enforce key relationships in joins. 

### Support native SQLite
Currently SwiftQL uses GRDB directly. It would be more efficient and portable to access SQLite directly. A longer term
goal of SwiftQL is to generate VDBE byte code directly and bypass SQL string parsing at runtime.

### Implicitly register functions
Currently functions need to be registered when the database is instantiated. It would be useful to register the function
automatically the first time it is called. 

### Implement `count(*)`
Add `all()` method which encodes to `*`. Used in `count` and other expressions, e.g. `count(all())`.

### Synthesize parameters on requests:

