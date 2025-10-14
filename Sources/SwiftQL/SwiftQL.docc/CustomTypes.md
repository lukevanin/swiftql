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
We cover two common use cases showing how to support Foundation `UUID` and 
`Date` types.

To allow a custom type to be used in SQL it needs to conform for the 
`SQLCustomType` protocol, and optionally one or more of the following:
- `SQLEquatable`: Allow the type to be used in equality expressions (e.g. `==` and `!=`)
- `SQLComparable`: Allow the type to be used in comparison expressions (e.g. `>`, `<`, `>=`, `<=`)

Custom types are stored in the SQL database by as one of the native 
representations used by SQLite: `Int`, `Double`, `String`, or `Data`. Custom 
types need to implement support to convert to and from one of these native 
representations when being written to and read from the database. 

## UUID extension

Below is an example showing how we can add an extension to the Foundation `UUID` 
type to store the UUID as a string.

```swift
// 1. Define the extension
extension UUID: XLCustomType, XLEquatable, XLComparable {

    private enum InternalError: LocalizedError {
        case uuidInvalid(String)

        var errorDescription: String? {
            switch self {
            case uuidInvalid(let rawValue):
                "Data does not represent a valid UUID: \(rawValue)"
            }
        }
    }
    
    // 2. Protocol conformance
    public typealias T = Self
    
    // 3. Initialize the custom type from a database field.
    public init(reader: XLColumnReader, at index: Int) throws {
        let rawValue = reader.readText(at: index)
        guard let uuid =  UUID(uuidString: rawValue) else {
            throw InternalError.uuidInvalid(rawValue)
        }
        self = uuid
    }
    
    // 4. Assign a value using out custom type in an SQL expression.
    public func bind(context: inout XLBindingContext) {
        context.bindText(value: uuidString)
    }
    
    // 5. Encode our custom type into a database field.
    public func makeSQL(context: inout XLBuilder) {
        context.text(self.uuidString)
    }
    
    // 6. Provide a default value.
    public static func sqlDefault() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
}
```

Let's go through this step by step:

1. We create an extension on `UUID` which conforms to the `XLCustomType` 
protocol. We will implement the protocol conformance in the following steps. 

We also add conformance for `XLEquatable` and `SQLComparable`. We do not need
to implement anything for these two protocols since SwiftQL will provide 
conformance automatically.

2. Add `public typealias T = Self`. This is necessary boilerplate to tell the
compiler that this extension implements the conformance for itself.

3. Implement the initializer. The initializer takes an `XLColumnReader` and an 
index. The `XLColumnReader` lets us read the native data from the database. The 
`index`represents the column which we need to read. 

Our `UUID` is encoded as a `String` which translates to an SQL `Text` value. We 
read the text value then instantiate our custom type. 

4. Implement the `bind` method. This method encodes our custom value when it
is used as a variable in an expression. Again, since our data is represented by 
a `Text` value, we can bind the string representation.

5. Implement the `makeSQL` method. This method is used to encode our custom type
when it is used as a literal value in an expression. 

6. Implement `sqlDefault`. This static method is used internally by SwiftQL when
preparing SQL queries. The only requirement is to provide a valid instance of
our custom type. The value itself does not matter.

This extension allows `UUID` type to be used in SQL expressions, such as a a 
column in a table, or a conditions in a where clause:

```swift
@SQLTable struct Employee {
    let id: UUID
    let name: String
}

let query = sql { schema in
    let employee = schema.table(Employee.self)
    Select(employee)
    From(employee)
    Where(employee.id == UUID(uuidString: "536d0033-65a0-4142-8c21-99b6b891c4e8"))
}
```

## Date extension
 
UUIDs were quite easy to support as there is a direct mapping between the type 
(`UUID`) and the representation (`String`). 

In this example we show how to support a more complex use case, by adding 
support for Fundation `Date` types.

Storing a `Date` can introduce complications as there are many ways that dates
can be represented depending on implementation requirements. For our purposes
we will store the date using a standardized string representation. 

We will use the `unixepoch` to convert our text representation into a unix 
timestamp so that we can perform comparisons in a predictable way. 

Ideally the `Date` would already be stored in a unix timestamp, however this 
example illustrates a common real world scenario where data often needs to be 
converted when it is used.

```swift
extension Date: SQLCustomType, SQLEquatable, SQLComparable {

    private enum InternalError: LocalizedError {
        case dataInvalid(String)

        var errorDescription: String? {
            switch self {
            case dataInvalid(let rawValue):
                "Data does not represent a valid Date: \(rawValue)"
            }
        }
    }
    
    // 1. Define a formatter to use to encode and decode the date.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timezone = TimeZone.utc
        formatter.locale = .posix
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter
    }()
    
    public typealias T = Self
    
    public init(reader: XLColumnReader, at index: Int) {
        let rawValue = reader.readText(at: index)
        guard let date = self.dateFormatter.date(from: rawValue) else {
            throw InternalError.dateInvalid(rawValue)
        }
        self = date
    }
    
    public func bind(context: inout XLBindingContext) {
        let rawValue = Self.dateFormatter.string(from: self)
        context.bindText(value: rawValue)
    }

    // 2. Wrap Date values with the `unixepoch` function to convert it into a
    // number which can be used in computations and comparison operations.
    public static func wrapSQL(context: inout XLBuilder, builder: (inout XLBuilder) -> Void) {
        context.simpleFunction(name: "unixepoch") { context in
            context.listItem { context in
                builder(&context)
            }
        }
    }

    // 3. Encode the Date when used in an SQL expression.
    public func makeSQL(context: inout XLBuilder) {
        Self.wrapSQL(context: &context) { context in
            context.text(Self.dateFormatter.string(from: self))
        }
    }
    
    public static func sqlDefault() -> Date {
        Date(timeIntervalSince1970: 0)
    }
}
```

The implementation of the `Date` extension is similar to the `UUID` with some
additional details. We discuss some of the differences below.

1. Add a static variable with a `DateFormatter`. This date formatter is used to
encode and decode the `Date` to and from its string representation. The exact 
format would depend on the application requirements.  

2. Implement `wrapSQL`. This method is used by SwiftQL to all values read from 
the database. We override the `wrapSQL` method to inject a call to SQLite's 
`unixepoch` function to transform our date from a string into a numerical 
timestamp in order to perform computations, such as adding and subtracting 
dates, and perform comparisons.   

3. Implement `makeSQL`: This is similar to the `UUID` example, except we need
to call `wrapSQL` after converting our date.

The example below shows how we might use our `Date` in a table and query: 

```swift
@SQLTable struct Invoice {
    let id: Int
    let dueDate: Date
}

let dateParameter = SQLNamedBindingReference<Date>(name: "date")

let query = sq; { schema in
    let invoice = schema.table(Invoice.self)
    Select(invoice)
    From(invoice)
    Where(invoice.dueDate < dateParameter)
}
```

## Custom UUID

So far we have added SQL support to extisting types using extension. Custom 
types can also be defined as standalone objects. This example show how we can 
define a custom `MyUUID` standalone type which wraps a `UUID`:

> Tip: Use value types (`struct`) for custom types.

```swift
struct MyUUID: SQLCustomType, Equatable {
    
    public typealias T = Self
    
    var wrappedValue: UUID
    
    public init(_ wrappedValue: UUID) {
        self.wrappedValue = wrappedValue
    }
    
    public init(reader: XLColumnReader, at index: Int) {
        wrappedValue = UUID(uuidString: reader.readText(at: index))!
    }
    
    public func bind(context: inout XLBindingContext) {
        context.bindText(value: wrappedValue.uuidString)
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.text(wrappedValue.uuidString)
    }
    
    public static func wrapSQL(context: inout XLBuilder, builder: (inout XLBuilder) -> Void) {
        builder(&context)
    }
    
    public static func sqlDefault() -> Wrapper {
        MyUUID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }
}
```

The implementation for our custom UUID type is similar to the extension examples 
for `UUID` and `Date` shown previously. The main difference is that we store a 
`UUID` instance in an instance variable.
