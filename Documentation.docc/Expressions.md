# Expressions

## Overview

SwiftQL allows complex expressions to be used wherever a column reference is
allowed. Complex expressions are commonly used when computing a result from 
column values, and in where expressions. 

## Boolean operators

Standard boolean operators to combine multiple expressions, such as for a 
boolean field or in a `Where` clause: 

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.id == "fred" || person.age > 65)
}
```

SwiftQL supports the following Swift boolean operators: `==`, `!=`, `!`, `<`, 
`>`, `>=`, `<=`, `&&`, `||`.

## Numeric operators

SwiftQL supports the following operators for performing numeric operations with 
`Int` and `Double` expressions: `+`, `-`, `/`, `*`.

The following operators are suppported on `Int` expressions: `%` (modulo), 
`~` (bitwise negate).

As an example, we can compute the years each person has to retirement:

```swift
@SQLResult PersonRetirement {
    var personId: String
    var yearsToRetirement: Int
}

let query = sql { schema in
    let person = schema.table(Person.self)
    let row = result {
        PersonRetirement(
            personId: person.id,
            yearsToRetirement: 65 - person.age
        )
    }
    Select(row)
    From(person)
    Where(row.yearsToRetirement > 0)
}
```

## Grouping expressions

Expressions in SwiftQL can be grouped using parenthesis like normal Swift, 
often used to explicitly define operator precedence, or to visually separate
sub-expressions for legibility:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where((person.occupationId == "eng") && (((65 - person.age) > 0) || (person.age < 21)))
}
```

When writing complex expressions, placing sub-expressions on separate lines with 
indentation can improve legibility. The above statement can also be written as:


```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(
        person.occupationId == "eng" 
        && 
        (
            (65 - person.age) > 0 
            || 
            person.age < 21
        )
    )
}
```

## Text operators

SwiftQL supports the following operators for text expressions:

### + operator

Concatenates two or more strings:

```swift

@SQLTable struct Contact {
    var id: String
    var firstName: String
    var lastName: String
}

@SQLResult struct ContactViewState {
    var name: String
}

let query = sql { schema in 
    let contact = schema.table(Contact.self)
    let row = result {
        ContactViewState.SQLReader(
            name: contact.firstName + " " + contact.lastName
        )
    }
    Select(row)
    From(contact)
}
```

> Note: SwiftQL does not support Swift string interpolation. Use the `+` 
concatenation operator to combine two or more strings in SwiftQL.

### like operator

Use the `like` operator is used for pattern matching within text values. It 
allows searching for strings that match a specified pattern using wildcard 
characters.

The `like` operator is typically used in the `Where` clause of a `Select` 
statement to filter results based on a pattern.

Find names starting with 'A':

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name.like("A%"))
}
```

Find names containing 'smith'.

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name.like("%smith%"))
}
```

Find names with 'a' as the second letter:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name.like("_a%"))
}
```

Find names exactly five characters long and ending with 'e':

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name.like("____e"))
}
```

> Note: SwiftQL does not currently support an `escape` clause for the `like` 
operator.

### glob operator

The `glob` operator is used for pattern matching in string values, similar to 
the `like` operator, but with a key difference in its wildcard syntax and 
case sensitivity.

Pattern Matching: It determines whether a given string value matches a 
specified pattern. If a match is found, it returns `true` otherwise, it returns 
`false`.

Case Sensitivity: Unlike `like`, `glob` is case-sensitive by default. This means 
`"A".glob("A")` would return `false`.

Wildcards: `glob` uses Unix file globbing syntax for its wildcards:

`*` (asterisk): Matches zero or more characters.

`?` (question mark): Matches exactly one character.

`[charset]` (character set): Matches any single character within the specified 
set. For example, `[abc]` matches `'a'`, `'b'`, or `'c'`.

`[^charset]` or `[!charset]`: Matches any single character not within the 
specified set.

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name.glob("J*n"))
}
```

This query would return names that start with 'J', end with 'n', and have any 
number of characters in between, such as 'John' or 'Jillian'.
Code

```swift
@SQLTable struct Document {
    var id: String
    var name: String
}

let query = sql { schema in
    let document = schema.table(Document.self)
    Select(document)
    From(document)
    Where(document.name.glob("report_??.pdf"))
}
```

This query would return filenames like 'report_01.pdf', 'report_AB.pdf', but not 
'report_1.pdf' or 'report_abc.pdf'.

Comparison with `like`:

While both `glob` and `like` are used for pattern matching, their primary 
distinctions are:

Wildcards: `like` uses `%` for zero or more characters and `_` for a single 
character, whereas `glob` uses `*` and `?` respectively.

Case Sensitivity: `glob` is case-sensitive by default, while `like` is typically 
case-insensitive.

### isNull and notNull

The operators `isNull` and `notNull` are used to determine whether an expression
evaluates to `ISNULL` or `NOTNULL` respectively. The SQL term `NULL` is used 
interchangeably with `nil`.

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.occupationId.notNull())
}
```

This query returns all of the `Person` records where the `occupationId` is not
`NULL`.

### Nil coalescing operators

SwiftQL provides the `coalesce` and `??` operators, which are used to provide a 
value when an expression otherwise evaluates to a `nil` value. They provide
identical functionality. `??` is preferred in adhering to Swift conventions, 
while `coalesce` is provided for situations where parity with SQL is preferred.

```swift
@SQLResult struct PersonViewState {
    var name: String
    var occupation: String
}

let query = sql { schema in
    let person = schema.table(Person.self)
    let occupation = schema.nullableTable(Occupation.self)
    Select(
        result {
            PersonViewState(
                name: person.name,
                occupation: occupation.name ?? "No occupation"
            )
        }
    )
    From(person)
    Join.Left(occupation, on: occupation.id == person.occupationId)
}
```

In this query the occupation name is coalesced to `No occupation` when no 
`Occupation` record is associated with the `Person`.

## In operator:

The `in` operator is a logical operator used in `Where` clauses to determine if 
a value matches any value within a specified list or a subquery. It provides a 
concise way to filter data based on multiple possible values for a single 
column, eliminating the need for multiple or conditions.

SwiftQL provides three variants of the `in` operator

expression: This can be any valid expression or a column from a table.

value_list: A comma-separated list of literal values (e.g., 'value1', 'value2', 10, 20).

subquery: A `Select` statement that returns a single column of values.

The `in` operator returns `true` if the expression matches any value present in 
the value_list or the result set of the subquery. If no match is found, it 
returns `false`. Prefixing the expression with the `!` (not) operator reverses 
this logic.

Using a value_list.

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.occupationId.in(["eng", "sci"]))
}
```

This query retrieves all employees whose department is either 'eng' or 'sci'. 

```swift
@SQLTable struct Customer {
    var id: String
    var name: String
}

@SQLTable struct Order {
    var id: String
    var customerId: String
    var date: String
}

let query = sql { schema in
    let customer = schema.table(Customer.self)
    Select(customer)
    From(customer)
    Where(
        customer.id.in { schema in
            let order = schema.table(Order.self)
            Select(order.customerId)
            From(order)
            Where(order.date > "2034-01-01")
        }
    )
}
```

This query retrieves the names of customers who placed an order after January 
1, 2024.
