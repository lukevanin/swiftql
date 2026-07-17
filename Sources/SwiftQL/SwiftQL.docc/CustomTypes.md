# Custom Types

Create custom scalar types for table columns.

## Overview

SwiftQL has the following built in data types: `Bool`, `Int`, `Double`, 
`String`, and `Data`.

It is sometimes necessary to use a more specific type to accurately represent 
data, or to simplify common query operations. SwiftQL allows you to create 
custom encoding for types that can be stored in the SQLite database.

Examples of where custom types might be used are for storing UUIDs, dates, or 
other structured content.

This guide shows how to define custom types and use them in tables and queries.
We cover two common use cases showing how to wrap Foundation `UUID` and `Date`
values in application-owned types.

To use a custom scalar value in SQL, its type must satisfy the `XLCustomType`
protocol composition (`XLExpression`, `XLBindable`, and `XLLiteral`). It can also
adopt these marker protocols to opt into operators:

- `XLEquatable`: Enables equality expressions such as `==` and `!=`.
- `XLComparable`: Refines `XLEquatable` and also enables `<`, `>`, `<=`, and `>=`.

Custom types are stored in the SQL database as one of the native
representations used by SQLite: `Int`, `Double`, `String`, or `Data`. Custom 
types need to implement support to convert to and from one of these native 
representations when being written to and read from the database. 

## UUID wrapper

Below is an example showing how to wrap a Foundation `UUID` and store it as a
string. Defining an application-owned type avoids a retroactive conformance on
Foundation's `UUID`, which can conflict with conformances added by another
module in the future.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
import Foundation
import SwiftQL

// 1. Define an application-owned wrapper type.
struct MyUUID: XLCustomType, XLComparable, Equatable {

    private enum ReadError: LocalizedError {
        case invalidUUID(String)

        var errorDescription: String? {
            switch self {
            case .invalidUUID(let rawValue):
                "Data does not represent a valid UUID: \(rawValue)"
            }
        }
    }

    // 2. Associated SQL value type.
    public typealias T = Self

    public let wrappedValue: UUID

    public init(_ wrappedValue: UUID) {
        self.wrappedValue = wrappedValue
    }

    // 3. Initialize the custom type from a database field.
    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = try reader.readText(at: index)
        guard let wrappedValue = UUID(uuidString: rawValue) else {
            throw ReadError.invalidUUID(rawValue)
        }
        self.wrappedValue = wrappedValue
    }

    // 4. Assign a value using our custom type in an SQL expression.
    public func bind(context: inout XLBindingContext) {
        context.bindText(value: wrappedValue.uuidString)
    }

    // 5. Encode our custom type into a database field.
    public func makeSQL(context: inout XLBuilder) {
        context.text(wrappedValue.uuidString)
    }

    // 6. Provide a default value.
    public static func sqlDefault() -> MyUUID {
        MyUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }
}
```

Let's go through this step by step:

1. We create a `MyUUID` structure which satisfies the `XLCustomType` protocol
composition and stores a Foundation `UUID`. We implement the required protocol
members in the following steps.

We also adopt `XLComparable`, which refines `XLEquatable`. These are marker
protocols with no additional method requirements; adopting them opts `MyUUID`
into SwiftQL's generic comparison operators.

2. Add `public typealias T = Self`. This tells the compiler that SQL expressions
using this type produce `MyUUID` values.

3. Implement the initializer. The initializer takes an `XLColumnReader` and an 
index. The `XLColumnReader` lets us read the native data from the database. The
`index` represents the column which we need to read.

Our UUID is encoded as a `String`, which translates to a SQLite `TEXT` value. We
read the text value, validate it as a Foundation `UUID`, then instantiate our
custom type.

4. Implement the `bind` method. This method encodes our custom value when it
is used as a variable in an expression. Again, since our data is represented by 
a `Text` value, we can bind the string representation.

5. Implement the `makeSQL` method. This method is used to encode our custom type
when it is used as a literal value in an expression. 

6. Implement `sqlDefault`. SwiftQL uses this placeholder while it determines a
result type's column expressions. The only requirement is to return a valid
instance of the custom type; the placeholder value is not read from or written
to the database.

This conformance allows `MyUUID` to be used in SQL expressions, such as a column
in a table or a condition in a `WHERE` clause:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
@SQLTable struct Employee {
    let id: MyUUID
    let name: String
}

let employeeID = MyUUID(UUID(uuidString: "536d0033-65a0-4142-8c21-99b6b891c4e8")!)
let query = sql { schema in
    let employee = schema.table(Employee.self)
    Select(employee)
    From(employee)
    Where(employee.id == employeeID)
}
```

## Date wrapper
 
UUIDs were quite easy to support as there is a direct mapping between the
wrapped value (`UUID`) and the representation (`String`).

In this example we show how to support a more complex use case by defining an
`SQLDate` type that wraps a Foundation `Date`.

Storing a `Date` can introduce complications as there are many ways that dates
can be represented depending on implementation requirements. For our purposes
we will store the date using a standardized string representation. 

We will use SQLite's `julianday` function to convert our text representation
into a numeric value so that we can perform comparisons in a predictable way.

Ideally the `Date` would already be stored as a Unix timestamp; however, this
example illustrates a common real world scenario where data often needs to be 
converted when it is used.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
import Foundation
import GRDB
import SwiftQL

struct SQLDate: XLCustomType, XLComparable, Equatable {

    private enum ReadError: Error {
        case invalidJulianDay(Double)
    }

    public typealias T = Self

    public let wrappedValue: Date

    public init(_ wrappedValue: Date) {
        self.wrappedValue = wrappedValue
    }

    // 1. Define a stable formatter for the text stored in SQLite.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = .gmt
        return formatter
    }()

    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = try reader.readReal(at: index)
        guard let wrappedValue = Date(julianDay: rawValue) else {
            throw ReadError.invalidJulianDay(rawValue)
        }
        self.wrappedValue = wrappedValue
    }

    public func bind(context: inout XLBindingContext) {
        let rawValue = Self.dateFormatter.string(from: wrappedValue)
        context.bindText(value: rawValue)
    }

    // 2. Wrap Date values with the `julianday` function to convert them into a
    // number which can be used in computations and comparison operations.
    public static func wrapSQL(context: inout XLBuilder, builder: (inout XLBuilder) -> Void) {
        context.simpleFunction(name: "julianday") { context in
            context.listItem { context in
                builder(&context)
            }
        }
    }

    // 3. Convert numeric Date expressions back to the string representation
    // stored in the database when inserting or updating values.
    public static func unwrapSQL(context: inout XLBuilder, builder: MakeExpression) {
        context.simpleFunction(name: "strftime") { context in
            context.listItem { context in
                context.text("%Y-%m-%dT%H:%M:%f")
            }
            context.listItem { context in
                builder(&context)
            }
        }
    }

    // 4. Encode the Date when used in an SQL expression.
    public func makeSQL(context: inout XLBuilder) {
        Self.wrapSQL(context: &context) { context in
            context.text(Self.dateFormatter.string(from: wrappedValue))
        }
    }

    public static func sqlDefault() -> SQLDate {
        SQLDate(Date(timeIntervalSince1970: 0))
    }
}
```

The implementation of the `SQLDate` wrapper is similar to `MyUUID`, with some
additional details. We discuss some of the differences below.

1. Add a static `DateFormatter` used to encode the text stored in SQLite. Its
locale, calendar, and time zone are fixed so the persisted format does not vary
with the user's settings. Query results are decoded from the numeric Julian day
returned by `julianday`, not by this formatter. The exact stored format depends
on the application's requirements.

2. Implement `wrapSQL`. SwiftQL applies this method to date expressions. The
implementation injects a call to SQLite's `julianday` function so stored text,
bound parameters, and literal values can be compared as numbers. Query results
are therefore read as `Double` values and converted back into `Date` instances.

3. Implement `unwrapSQL`. SwiftQL applies this method when writing a date. The
implementation uses SQLite's `strftime` function to convert the numeric
expression back to the text representation stored in the database.

4. Implement `makeSQL`. This is similar to the `MyUUID` example, except the
encoded string is wrapped with `julianday` for use in an expression.

The example below shows how we might use `SQLDate` in a table and query:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
@SQLTable struct Invoice {
    let id: String
    let dueDate: SQLDate
}

let dateParameter = XLNamedBindingReference<SQLDate>(name: "date")

let query = sqlQuery { schema in
    let invoice = schema.table(Invoice.self)
    return select(invoice)
        .from(invoice)
        .where(invoice.dueDate > dateParameter)
}

var request = database.makeRequest(with: query)
request.set(dateParameter, SQLDate(Date(timeIntervalSince1970: 0)))
let invoices = try request.fetchAll()
```
