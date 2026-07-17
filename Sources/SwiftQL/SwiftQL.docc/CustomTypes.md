# Custom Types

Create custom scalar types for table columns.

## Overview

SwiftQL has built-in support for `Bool`, `Int`, `Double`, `String`, and `Data`.
Use a contextual value codec for a different application type or when one Swift
type has more than one valid database representation. A codec pairs throwing
encode and decode closures with stable type, dialect, storage, name, and version
metadata. It does not require a property wrapper or a retroactive conformance.

The older `XLCustomType` literal path remains source compatible. It is described
after the contextual API so existing applications can migrate deliberately
without silently changing persisted representations.

## Contextual value codecs

The following example gives Foundation `Date` two named SQLite representations.
Both codecs target the same Swift type without changing `Date` itself. The
decimal-seconds text codec is the database default; an integer-seconds codec can
be selected at an individual property, parameter, or result site.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
import Foundation
import SwiftQL

enum DateCodecError: Error {
    case invalidText(String)
    case unexpectedValue(XLSQLiteValue)
}

let dateType = XLValueTypeIdentifier(rawValue: "com.example.foundation-date")
let decimalDateCodecKey = XLValueCodecKey(
    id: "com.example.date.decimal-seconds",
    version: 1
)
let integerDateCodecKey = XLValueCodecKey(
    id: "com.example.date.integer-seconds",
    version: 1
)

let decimalDateCodec = XLValueCodec<Date, XLSQLiteDialect>(
    key: decimalDateCodecKey,
    valueTypeIdentifier: dateType,
    dialectIdentifier: XLSQLiteDialect.identity,
    storageIdentifier: XLValueStorageIdentifier(
        rawValue: XLSQLiteStorageClass.text.rawValue
    ),
    encode: { date, _, _ in
        .text(String(date.timeIntervalSince1970))
    },
    decode: { value, _, _ in
        guard case .text(let text) = value else {
            throw DateCodecError.unexpectedValue(value)
        }
        guard let seconds = Double(text) else {
            throw DateCodecError.invalidText(text)
        }
        return Date(timeIntervalSince1970: seconds)
    }
)

let integerDateCodec = XLValueCodec<Date, XLSQLiteDialect>(
    key: integerDateCodecKey,
    valueTypeIdentifier: dateType,
    dialectIdentifier: XLSQLiteDialect.identity,
    storageIdentifier: XLValueStorageIdentifier(
        rawValue: XLSQLiteStorageClass.integer.rawValue
    ),
    encode: { date, _, _ in
        .integer(Int64(date.timeIntervalSince1970))
    },
    decode: { value, _, _ in
        guard case .integer(let seconds) = value else {
            throw DateCodecError.unexpectedValue(value)
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
)

let dateRegistry = try XLValueCodecRegistry()
    .registering(decimalDateCodec)
    .registering(integerDateCodec)
let dateCoding = try XLValueCodingConfiguration(
    registry: dateRegistry,
    defaultCodecKeys: [decimalDateCodecKey]
)
```

Registration and configuration are immutable operations. `registering` returns
a new registry, and `XLValueCodingConfiguration` keeps that registry snapshot.
Passing the configuration to `GRDBDatabase` snapshots it for the database; carry
the same value into query construction, then call `resolvedCodec` once for each
static property, parameter, or result slot retained by a prepared handle. The
resulting `XLResolvedValueCodec` is immutable and reusable across invocations or
rows. There is no process-global registry or mutable capture to synchronize.

Registering a codec never changes an existing representation by itself. A codec
becomes a database default only when its key is listed in `defaultCodecKeys`.
Treat changes to a codec key or version, stable Swift type identifier, dialect,
or storage identifier as a schema/data migration. These values are also the
stable components available to schema and query fingerprinting; do not derive
durable identity from Swift runtime type names or hashes.

### Selection and errors

Codec selection uses one deterministic order:

1. An explicit property, parameter, or result codec key.
2. A query-level codec key.
3. The database default for the stable Swift type and dialect.
4. A selected v1 literal adapter.
5. A structured missing- or ambiguous-codec error.

The first populated tier is authoritative. An unknown or incompatible explicit
key throws at the explicit tier; SwiftQL does not silently fall through to a
query key, default, or legacy adapter. Duplicate keys and duplicate defaults are
also rejected deterministically.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let dialect = XLSQLiteDialect()
let dueDate = Date(timeIntervalSince1970: 86_400)
let parameterContext = XLValueCodingContext(
    site: .parameter,
    path: XLValueCodingPath("invoice.dueDate")
)

// The explicit integer codec wins over both the query codec and text default.
let resolvedDueDateCodec = try dateCoding.resolvedCodec(
    for: Date.self,
    using: dialect,
    context: parameterContext,
    selection: XLValueCodecSelection(
        explicitCodecKey: integerDateCodecKey,
        queryCodecKey: decimalDateCodecKey
    )
)
let storedValue = try resolvedDueDateCodec.encode(dueDate)
```

The context path is retained in structured registration, selection, storage,
encoding, and decoding errors. Use stable paths that identify the property,
parameter, or result field rather than transient array positions.

### SQL NULL and optional values

Optionality is outside a nonoptional codec. `encodeOptional` and
`decodeOptional` first resolve and validate the selected codec, then map Swift
`nil` directly to the dialect's SQL `NULL` or SQL `NULL` directly to Swift
`nil`. The codec closure never receives either optional state.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let nullValue = try dateCoding.encodeOptional(
    Optional<Date>.none,
    using: dialect,
    context: parameterContext
)

let resultContext = XLValueCodingContext(
    site: .result,
    path: XLValueCodingPath("invoice.dueDate")
)
let decodedDate: Date? = try dateCoding.decodeOptional(
    Date.self,
    from: .null,
    using: dialect,
    context: resultContext
)
```

## Legacy `XLCustomType` wrappers

For existing v1 code, a custom scalar value satisfies the `XLCustomType`
protocol composition (`XLExpression`, `XLBindable`, and `XLLiteral`). It can also
adopt these marker protocols to opt into operators:

- `XLEquatable`: Enables equality expressions such as `==` and `!=`.
- `XLComparable`: Refines `XLEquatable` and also enables `<`, `>`, `<=`, and `>=`.

Legacy custom types are stored in the SQL database as one of the native
representations used by SQLite: `Int`, `Double`, `String`, or `Data`. Custom 
types need to implement support to convert to and from one of these native 
representations when being written to and read from the database. 

### UUID wrapper

Below is an example showing how to wrap a Foundation `UUID` and store it as a
string. Defining an application-owned type avoids a retroactive conformance on
Foundation's `UUID`, which can conflict with conformances added by another
module in the future.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
import Foundation
import SwiftQL

// 1. Define an application-owned wrapper type.
struct MyUUID: XLCustomType, XLComparable, Equatable, Sendable {

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

### Date wrapper
 
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

## Migrating v1 literals

`XLV1LiteralCodec` exposes an existing `Sendable` `XLLiteral` implementation as
a named SQLite codec. Requiring `Sendable` keeps the immutable configuration
safe to share between tasks; the original v1 literal path remains unchanged for
older types. This is a compatibility bridge, not permission to change storage
implicitly: declare the actual v1 storage class, test existing rows, and retain
the old representation until a deliberate migration has completed.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let legacyKey = XLValueCodecKey(
    id: "com.example.my-uuid.v1-literal",
    version: 1
)
let legacyAdapter = XLV1LiteralCodec<MyUUID>(
    key: legacyKey,
    valueTypeIdentifier: XLValueTypeIdentifier(
        rawValue: "com.example.my-uuid"
    ),
    storageClass: .text
)
let legacyRegistry = try XLValueCodecRegistry()
    .registering(legacyAdapter.codec)
let legacyCoding = try XLValueCodingConfiguration(registry: legacyRegistry)

let encodedID = try legacyCoding.encode(
    employeeID,
    using: XLSQLiteDialect(),
    context: XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath("employee.id")
    ),
    selection: XLValueCodecSelection(legacyCodecKey: legacyKey)
)
```

The adapter is considered only when no explicit, query, or database-default key
was selected. Once callers have moved to a native contextual codec, remove the
legacy selector only after stored values and prepared-query fingerprints have
been migrated together.
