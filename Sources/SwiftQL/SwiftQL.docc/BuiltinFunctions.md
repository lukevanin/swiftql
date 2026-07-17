# Built-in Functions

Functions provided by SwiftQL. 

## Overview

In this guide we will see some of the functions provided by SwiftQL, including
functions provided natively by SQLite.

## Conditional functions

### iif()

The `iif` function in SwiftQL is a conditional function that evaluates one
boolean expression and returns one of two values. It is logically equivalent to
Swift's `if-then-else` expression.

The following SwiftQL code shows how to use the `iif` function:

<!-- test: XLDocumentationTests.testDocumentationConditionalAndScalarFunctions -->
```swift
@SQLResult struct EmploymentStatus {
    let person: String
    let occupation: String
}

let statement = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    let result = EmploymentStatus.columns(
        person: person.name,
        occupation: iif(
            occupation.name.isNull(), 
            then: "Unemployed", 
            else: "Employed"
        )
    )
    Select(result)
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

This statement returns the person's name in the `person` column, and the word
`Unemployed` in the `occupation` column if the person's occupation is `NULL`,
or `Employed` if the person's occupation is not `NULL`.

### switchCase(), when(), and else()

The `switchCase-when-then-else` APIs create conditional expressions matching
more than one condition. SwiftQL provides two variants.

*Condition matching:*

The first variant uses a constant term to match and behaves similar to a 
`switch` statement in Swift, where multiple patterns are compared against a 
single condition.

<!-- test: XLDocumentationTests.testDocumentationConditionalAndScalarFunctions -->
```swift
@SQLResult struct OccupationOptionalColor {
    let occupation: String
    let color: String?
}

let statement = sql { schema in
    let occupation = schema.table(Occupation.self)
    let result = OccupationOptionalColor.columns(
        occupation: occupation.name,
        color: switchCase(occupation.name)
            .when("Engineer", then: "Red")
            .when("Scientist", then: "Blue")
    )
    Select(result)
    From(occupation)
}
```

*Boolean matching:*

The second variant behaves like an `if` statement with multiple boolean 
conditions, and uses the result from the first boolean condition that evaluates 
to `true`.

<!-- test: XLDocumentationTests.testDocumentationConditionalAndScalarFunctions -->
```swift
@SQLResult struct OccupationColor {
    let occupation: String
    let color: String
}

let statement = sql { schema in
    let occupation = schema.table(Occupation.self)
    let result = OccupationOptionalColor.columns(
        occupation: occupation.name,
        color: when(occupation.name == "Artist", then: "Cyan")
    )
    Select(result)
    From(occupation)
}
```

*Else:*

Both variants produce an optional type by default, and return a `nil` result if 
none of the conditions match. We can use an `else` to specify a default 
expression which is used instead, which also changes the result to a 
non-optional type.

<!-- test: XLDocumentationTests.testDocumentationConditionalAndScalarFunctions -->
```swift
let statement = sql { schema in
    let occupation = schema.table(Occupation.self)
    let result = OccupationColor.columns(
        occupation: occupation.name,
        color: switchCase(occupation.name)
            .when("Engineer", then: "Red")
            .when("Scientist", then: "Blue")
            .else("Green")
    )
    Select(result)
    From(occupation)
}
let sql = encoder.makeSQL(statement).sql
let rows = try database.makeRequest(with: statement).fetchAll()
```

## Date functions

### toUnixTimestamp()

Converts a string representation of a date to an integer representing the number
of seconds since the unix epoch.

## Numeric functions

### abs()

Returns the absolute value of a numeric expression.

### rounded()

Returns a `Double` expression rounded to the nearest integral value.

### rounded(to:)

Returns a `Double` expression rounded to the provided number of decimal places.

### floor()

Returns a `Double` expression rounded to the largest integral value less than or
equal to it.

## String functions

### collate()

Specifies the collating sequence, or collation, for comparing `String` values.
Collations determine the order and equality of strings during operations such as 
`OrderBy`, `groupBy`, `Join`, and `Where` clauses.

SwiftQL provides three default collating sequences:
- `binary`: Compares string data using `memcmp()`, treating characters as raw 
byte sequences. This is the default collation.
- `nocase`: Similar to `binary`, but performs case-folding for ASCII characters 
(converting uppercase ASCII letters to their lowercase equivalents) before 
comparison. It does not handle full Unicode case-folding.
- `rtrim`: Similar to `binary`, but ignores trailing space characters during 
comparison.

Their names are closed grammar choices that render as `COLLATE BINARY`,
`COLLATE NOCASE`, and `COLLATE RTRIM`, rather than as SQL string literals or
arbitrary raw SQL fragments.

### printf()

Returns a formatted string. In SwiftQL `printf()` is similar to the same 
function provided by the standard C library. 

Refer to the [SQLite printf](https://sqlite.org/printf.html) documentation for
more information.

## Type conversion

SwiftQL adopts Swift's conventions and requires expressions of different types 
to be explicitly converted to a common type when used together in the 
same expression. 

Type conversion of custom types should be implemented as required.

### toInt()

Converts an expression of type `Bool`, `Double`, or `String` to an expression of
type `Int`.

### toDouble()

Converts an expression of type `Int` or `String` to an expression of 
type `Double`.

### toString()

Converts an expression of type `Int`, `Double`, or `Data` to an expression of
type `String`.

### toData()

Converts an expression of type `String` to an expression of type `Data`.
