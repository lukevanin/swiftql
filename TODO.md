# TODO

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

### Provide a `#table` macro to replace `schema.table(SomeTable.self)`

### Provide a `#row` macro to replace `result { SomeResult.SQLReader(...) }`

### Support ESCAPE clause in LIKE

### Support COLLATE NOCASE 

### Use `isNil` and `notNil` instead of `isNull` and `notNull`.

### Remove `coalesce` operator (keep only `??`).

### Create a helper macro to more easily define functions.

E.g. provide a helper method to define a function by making use of the common 
pattern of providing a function name and a set of parameters:

```
    // Define how the function is formatted into an SQL expression.
    public func makeSQL(context: inout SQLBuilder) {
        context.simpleFunction(name: Self.definition.name) { context in
            context.listItem(expression: fromLatitude.makeSQL)
            context.listItem(expression: fromLongitude.makeSQL)
            context.listItem(expression: toLatitude.makeSQL)
            context.listItem(expression: toLongitude.makeSQL)
        }
    }
```

### Provide a macro for creating static queries.

### Provide playgrounds showing example queries.

### Provide convenience functions for using SwiftQL expressions with SwitfUI
more easily.

### Support custom collations (eg for unicode).
