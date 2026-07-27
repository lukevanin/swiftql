# Custom Types

Create custom scalar types for table columns.

## Overview

SwiftQL has built-in support for `Bool`, `Int`, `Double`, `String`, and `Data`.
Use the v1.2 contextual value-codec API for a different application type or
when one Swift type has more than one valid database representation. A codec
pairs throwing encode and decode closures with stable type, dialect, storage,
name, and version metadata. It does not require a property wrapper or a
retroactive conformance.

The older `XLCustomType` literal path remains source compatible. Existing types
can keep an explicit legacy introspection placeholder, while new types that use
generated static row layouts do not need to invent one. The compatibility path
is described after the contextual API so applications can migrate deliberately
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

### Contextual parameters and invocation packets

Create a contextual binding from the same database that will prepare the
request. `contextualBinding` resolves the codec once from that database's
immutable coding snapshot. Rendering then records the declaration in the
request's static `XLParameterLayout`; encoding a runtime value produces one
`XLInvocationBinding` for a per-call packet.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let codecDatabase = try GRDBDatabase(
    url: databaseURL,
    codingConfiguration: dateCoding,
    logger: nil
)
let cutoffDate = try codecDatabase.contextualBinding(
    Date.self,
    expressedAs: String.self,
    named: "cutoffDate"
)
let cutoffQuery = sql { _ in
    Select(cutoffDate)
}
let cutoffRequest = codecDatabase.makeRequest(with: cutoffQuery)
let cutoffBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: cutoffRequest.parameterLayout,
    bindings: [
        cutoffDate.encode(
            Date(timeIntervalSince1970: 86_400),
            in: cutoffRequest.parameterLayout
        )
    ]
).validatingComplete()
let storedCutoff = try cutoffRequest.fetchOne(bindings: cutoffBindings)
```

Here `Value` is `Date`, while the reference's `Literal` is `String` because the
selected codec stores SQLite `TEXT`. The `expressedAs` literal controls SQL
expression typing and any literal wrapping; it does not make `Date` conform to
`XLLiteral`, choose a different codec at execution time, or become part of the
runtime packet. SwiftQL rejects a known storage mismatch between the literal
and codec when the contextual reference is created.

Nullability is equally explicit. A nullable contextual reference must use an
optional literal expression type, and `encodeOptional(nil, in:)` produces a
present SQLite `.null` binding:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let optionalDate = try codecDatabase.contextualBinding(
    Date.self,
    expressedAs: Optional<String>.self,
    named: "optionalDate",
    nullability: .nullable
)
let nullQuery = sql { _ in Select(optionalDate.isNull()) }
let nullRequest = codecDatabase.makeRequest(with: nullQuery)
let nullBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: nullRequest.parameterLayout,
    bindings: [
        optionalDate.encodeOptional(nil, in: nullRequest.parameterLayout)
    ]
).validatingComplete()
let isNull = try nullRequest.fetchOne(bindings: nullBindings)
```

An empty packet for `nullRequest` is missing a binding and fails
`validatingComplete()`; it is not interpreted as SQL `NULL`. Encoding `nil` for
a required slot fails with parameter, codec, and coding-path context before the
driver binds anything.

Foundation `UUID` and application-owned values use the same API without
retroactive literal conformances. Suppose `applicationCodecDatabase` was opened
with registered defaults whose storage identifiers match `BLOB` and `INTEGER`,
respectively:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
struct InvoiceToken {
    let rawValue: Int64
}

let uuidParameter = try applicationCodecDatabase.contextualBinding(
    UUID.self,
    expressedAs: Data.self,
    named: "invoiceID"
)
let tokenParameter = try applicationCodecDatabase.contextualBinding(
    InvoiceToken.self,
    expressedAs: Int.self,
    named: "token"
)
```

Each reference retains its resolved codec identity and context. Call
`encode(_:in:)` with the prepared request's layout, collect the returned
bindings in one `XLInvocationBindings` value, validate completeness, and pass
that packet to the request. Only normalized `XLSQLiteValue` values enter the
packet; the original `Date`, `UUID`, or custom value is not retained.

### Property-level codec selection

The database default and any query-level key cover most properties, but two
properties of the *same* Swift type sometimes need two different storage
conventions on the same table -- one `Date` stored as decimal seconds, another
stored as an integer, without introducing a wrapper type for either one.
`@SQLCodec` declares that choice on the property itself. It is metadata only:
the attribute names a codec key, and the registry/configuration from the
sections above still perform the actual conversion.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
@SQLTable
struct InvoiceRecord: Equatable {
    let id: Int

    @SQLCodec(decimalDateCodecKey)
    let filedAt: Date

    @SQLCodec(integerDateCodecKey)
    let reviewedAt: Date
}
```

`@SQLCodec` does not change `filedAt`'s or `reviewedAt`'s Swift type,
`InvoiceRecord`'s memberwise initializer, or `Equatable`/`Codable`
behavior -- it never wraps the property. Applying it to a stored property is a schema/data migration for that
property alone, exactly like changing a codec's key or version: the property
keeps whichever storage convention its codec key names for as long as that key
is deployed, independent of every other property and of the database default.

The macro emits the key as stable metadata reachable two ways: a
`_swiftQLPropertyCodecKeys` dictionary on the generated type (keyed by column
name), and a generated `staticResultField(_:...)` convenience per annotated
property that already supplies `selection: .explicit(...)` -- so a caller never
repeats the key when building a `staticRowLayout(using:...)` argument for that
property:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let invoiceTable = XLSchema().table(InvoiceRecord.self, as: "invoice")
let invoiceLayout = try InvoiceRecord.staticRowLayout(
    using: XLSQLiteDialect.self,
    id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
        selecting: invoiceTable.id,
        identifiedBy: XLQuerySlotIdentity(path: ["invoice", "id"])
    ),
    filedAt: InvoiceRecord.staticResultField(
        filedAt: invoiceTable.filedAt,
        storedAs: String.self,
        identifiedBy: XLQuerySlotIdentity(path: ["invoice", "filed-at"]),
        using: codecDatabase.dialect,
        configuration: codingConfiguration
    ),
    reviewedAt: InvoiceRecord.staticResultField(
        reviewedAt: invoiceTable.reviewedAt,
        storedAs: Int.self,
        identifiedBy: XLQuerySlotIdentity(path: ["invoice", "reviewed-at"]),
        using: codecDatabase.dialect,
        configuration: codingConfiguration
    )
)
```

Both codecs must still be registered with the configuration passed to
`staticResultField`; `@SQLCodec` selects among registered codecs, it does not
register one. An unregistered key, a key registered for a different Swift
value type, or a key registered for a different dialect all fail exactly the
way an explicit `XLValueCodecSelection` fails elsewhere in this
document -- with the same `XLValueCodecError` cases, at the same "explicit"
precedence tier, before any row is touched.

## JSON `Codable` columns

SQLite has no native JSON column type. It stores JSON as `TEXT` or `BLOB`
bytes, and SwiftQL does not drive SQLite's `json1` functions, validate JSON,
or create generated/indexed columns on the caller's behalf: those remain the
application's or a future issue's responsibility. `XLJSONValueCodec` is a
factory, built on the same contextual codec API described above, that
converts an application `Codable` value to and from one of those two storage
representations. It stores no `JSONEncoder`/`JSONDecoder` instance globally
or between calls; `XLJSONCodecConfiguration` snapshots the relevant
`Sendable` strategies once, and every encode or decode builds a fresh encoder
or decoder from that snapshot.

The example below defines a nested `Codable` value with a struct, an array,
an optional, and an enum field, then registers two `XLJSONValueCodec`
codecs for it: one storing canonical, sorted-key `TEXT`, the other storing
the same JSON bytes as `BLOB`. `TEXT` and `BLOB` are different storage
classes with different stable identities; selecting the wrong one for a
stored column fails with `XLValueCodecError.storageMismatch` rather than
silently reinterpreting bytes.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
struct ContactAddress: Codable, Equatable {
    var street: String
    var city: String
}

enum ContactMethod: Codable, Equatable {
    case email(String)
    case phone(String)
}

struct CustomerProfile: Codable, Equatable {
    var name: String
    var tags: [String]
    var address: ContactAddress?
    var contact: ContactMethod
    var loyaltyPoints: Int

    enum CodingKeys: String, CodingKey {
        case name, tags, address, contact, loyaltyPoints
    }

    init(
        name: String,
        tags: [String],
        address: ContactAddress?,
        contact: ContactMethod,
        loyaltyPoints: Int = 0
    ) {
        self.name = name
        self.tags = tags
        self.address = address
        self.contact = contact
        self.loyaltyPoints = loyaltyPoints
    }

    // Schema evolution: `loyaltyPoints` was added after JSON rows already
    // existed. Older stored JSON that omits the key still decodes, using an
    // explicit application default instead of failing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        tags = try container.decode([String].self, forKey: .tags)
        address = try container.decodeIfPresent(ContactAddress.self, forKey: .address)
        contact = try container.decode(ContactMethod.self, forKey: .contact)
        loyaltyPoints = try container.decodeIfPresent(Int.self, forKey: .loyaltyPoints) ?? 0
    }
}

let profileType = XLValueTypeIdentifier(rawValue: "com.example.customer-profile")
let profileTextKey = XLValueCodecKey(id: "com.example.customer-profile.text", version: 1)
let profileBlobKey = XLValueCodecKey(id: "com.example.customer-profile.blob", version: 1)

let profileTextCodec = XLJSONValueCodec.text(
    key: profileTextKey,
    valueTypeIdentifier: profileType
) as XLValueCodec<CustomerProfile, XLSQLiteDialect>
let profileBlobCodec = XLJSONValueCodec.blob(
    key: profileBlobKey,
    valueTypeIdentifier: profileType
) as XLValueCodec<CustomerProfile, XLSQLiteDialect>

let profileRegistry = try XLValueCodecRegistry()
    .registering(profileTextCodec)
    .registering(profileBlobCodec)
let profileCoding = try XLValueCodingConfiguration(
    registry: profileRegistry,
    defaultCodecKeys: [profileTextKey]
)
```

Both codecs handle only the nonoptional `CustomerProfile`. Optionality is not
reinvented here: `encodeOptional`/`decodeOptional` on the resolved codec or
coding configuration compose with either storage exactly as they do for the
`Date` codecs above, mapping Swift `nil` directly to SQL `NULL` without
calling `JSONEncoder`.

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let profile = CustomerProfile(
    name: "Ada Lovelace",
    tags: ["engineer", "mathematician"],
    address: ContactAddress(street: "12 Analytical Ave", city: "London"),
    contact: .email("ada@example.com"),
    loyaltyPoints: 42
)
let profileParameterContext = XLValueCodingContext(
    site: .parameter,
    path: XLValueCodingPath("customer.profile")
)

let textValue = try profileCoding.encode(
    profile,
    using: dialect,
    context: profileParameterContext,
    selection: XLValueCodecSelection(explicitCodecKey: profileTextKey)
)
let blobValue = try profileCoding.encode(
    profile,
    using: dialect,
    context: profileParameterContext,
    selection: XLValueCodecSelection(explicitCodecKey: profileBlobKey)
)

let decodedFromText = try profileCoding.decode(
    CustomerProfile.self,
    from: textValue,
    using: dialect,
    context: resultContext,
    selection: XLValueCodecSelection(explicitCodecKey: profileTextKey)
)
let decodedFromBlob = try profileCoding.decode(
    CustomerProfile.self,
    from: blobValue,
    using: dialect,
    context: resultContext,
    selection: XLValueCodecSelection(explicitCodecKey: profileBlobKey)
)
```

Malformed or incompatible stored bytes fail with a structured, catchable
error instead of silently producing a default value. The underlying
`EncodingError`/`DecodingError` text is preserved inside the wrapped
`XLValueCodecError.decodingFailed`/`.encodingFailed` message, alongside the
codec key and coding context that produced it:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
do {
    _ = try profileCoding.decode(
        CustomerProfile.self,
        from: .text("{this is not valid json"),
        using: dialect,
        context: resultContext,
        selection: XLValueCodecSelection(explicitCodecKey: profileTextKey)
    )
    preconditionFailure("Expected a structured decoding failure.")
}
catch let XLValueCodecError.decodingFailed(codec, _, message) {
    precondition(codec == profileTextKey)
    precondition(message.contains("JSON decoding"))
}
```

Two configurations of the same `Codable` type coexist without a wrapper
struct: register a second codec with a different key and JSON key strategy,
then select each explicitly. Here `JSONMetric` has no explicit `CodingKeys`,
so `.convertToSnakeCase` changes the persisted field names without changing
the Swift type:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
struct JSONMetric: Codable, Equatable {
    let sampleCount: Int
    let averageValue: Double
}

let metricType = XLValueTypeIdentifier(rawValue: "com.example.json-metric")
let metricDefaultKeysKey = XLValueCodecKey(id: "com.example.json-metric.default-keys", version: 1)
let metricSnakeCaseKey = XLValueCodecKey(id: "com.example.json-metric.snake-case", version: 1)

let metricDefaultKeysCodec = XLJSONValueCodec.text(
    key: metricDefaultKeysKey,
    valueTypeIdentifier: metricType
) as XLValueCodec<JSONMetric, XLSQLiteDialect>
let metricSnakeCaseCodec = XLJSONValueCodec.text(
    key: metricSnakeCaseKey,
    valueTypeIdentifier: metricType,
    configuration: XLJSONCodecConfiguration(
        keyEncodingStrategy: .convertToSnakeCase,
        keyDecodingStrategy: .convertFromSnakeCase
    )
) as XLValueCodec<JSONMetric, XLSQLiteDialect>

let metricRegistry = try XLValueCodecRegistry()
    .registering(metricDefaultKeysCodec)
    .registering(metricSnakeCaseCodec)
let metricCoding = try XLValueCodingConfiguration(registry: metricRegistry)
```

Storing both representations through a real database uses the same
`contextualBinding` API shown for `Date` above. `expressedAs: String.self`
requires `TEXT` storage; `expressedAs: Data.self` requires `BLOB` storage.
SwiftQL rejects a mismatch between the chosen literal and the resolved
codec's storage when the contextual reference is created, before any SQL
runs:

<!-- test: XLDocumentationTests.testDocumentationCustomTypeRoundTrips -->
```swift
let jsonCodecDatabase = try GRDBDatabase(
    url: databaseURL,
    codingConfiguration: profileCoding,
    logger: nil
)
let profileTextParameter = try jsonCodecDatabase.contextualBinding(
    CustomerProfile.self,
    expressedAs: String.self,
    named: "profileText",
    selection: XLValueCodecSelection(explicitCodecKey: profileTextKey)
)
let profileTextQuery = sql { _ in
    Select(profileTextParameter)
}
let profileTextRequest = jsonCodecDatabase.makeRequest(with: profileTextQuery)
let profileTextBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: profileTextRequest.parameterLayout,
    bindings: [
        try profileTextParameter.encode(profile, in: profileTextRequest.parameterLayout)
    ]
).validatingComplete()
let storedProfileJSON = try profileTextRequest.fetchOne(bindings: profileTextBindings)
```

Treat a change to a JSON codec's `key.id`, `key.version`, `valueTypeIdentifier`,
or chosen storage (`.text` vs `.blob`) as a data migration in the same way as
any other codec: they are the stable components schema and query
fingerprints use, and `TEXT` versus `BLOB` bytes for the same `Codable` type
are not interchangeable at rest. Because `XLJSONValueCodec`'s `Codable`-to-
`Data` transcoding is isolated from `XLSQLiteValue`/`XLSQLiteStorageClass`, a
future PostgreSQL dialect (`JSONB`, tracked separately as issue #137) can
reuse the same transcoding behind a dialect-native lowering without changing
this SQLite mapping. SwiftQL does not claim that mapping exists yet, and does
not offer a cross-database JSON abstraction today.

## Legacy `XLCustomType` wrappers

For existing v1 code, a custom scalar value satisfies the `XLCustomType`
protocol composition (`XLExpression`, `XLBindable`, and `XLLiteral`). It can also
adopt these marker protocols to opt into operators:

- `XLEquatable`: Enables equality expressions such as `==` and `!=`.
- `XLComparable`: Refines `XLEquatable` and also enables `<`, `>`, `<=`, and `>=`.

`XLLiteral` retains the `sqlDefault()` requirement so existing implementations
remain protocol witnesses. Its default implementation stops with a migration
diagnostic if legacy `SQLReader` introspection reaches a type that did not
provide a placeholder. Override it only while the type still uses that legacy
result path. A generated static row layout decodes from raw dialect values and
never calls `sqlDefault()`.

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
    public init(reader: XLFieldReader) throws {
        let rawValue = try reader.readText()
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

    // 6. Opt into legacy SQLReader result introspection.
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

3. Implement the initializer. The initializer takes an `XLFieldReader`, which
is already bound to the result field owned by this literal. It lets us read the
native data without accepting or forwarding a separate column index.

Existing v1 literal types that implement
`init(reader: XLColumnReader, at: Int)` remain source compatible. A bridge wraps
that column reader and index in an `XLFieldReader` when SwiftQL decodes a row.
New literal types should implement the field-reader initializer shown above;
the reverse bridge also keeps the older call shape working. Every literal type
must implement at least one of those initializers.

Our UUID is encoded as a `String`, which translates to a SQLite `TEXT` value. We
read the text value, validate it as a Foundation `UUID`, then instantiate our
custom type.

4. Implement the `bind` method. This method encodes our custom value when it
is used as a variable in an expression. Again, since our data is represented by 
a `Text` value, we can bind the string representation.

5. Implement the `makeSQL` method. This method is used to encode our custom type
when it is used as a literal value in an expression. 

6. This example continues to use the legacy query/result APIs, so it overrides
`sqlDefault`. SwiftQL uses the placeholder while it determines that result
type's column expressions. The placeholder is not read from or written to the
database. A type used only through a generated static row layout omits this
override instead of inventing a semantically fake value.

Steps 2 through 5 define the literal behavior; step 6 opts into legacy result
introspection. New domain values can instead remain plain Swift structs, enums,
`Date`, or `UUID` values, or retain `XLCustomType` expression behavior without a
placeholder: register an `XLValueCodec`, create each projected field with
`staticResultField`, and pass those fields to the macro-generated
`staticRowLayout(using:...)` factory. That path constructs result metadata and
renders projections without calling a model initializer, `SQLReader`, or
`sqlDefault()`.

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
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public init(reader: XLFieldReader) throws {
        let rawValue = try reader.readReal()
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

This last example deliberately shows the v1 `set` migration shim. It converts
the `SQLDate` literal immediately into a compatibility invocation packet on the
request copy. It cannot select or bypass a contextual codec. New code that has
a registered `Date` codec should use `contextualBinding`, encode a fresh packet,
and keep the prepared request immutable as shown above.

## Migrating v1 literals

`XLV1LiteralCodec` exposes an existing `Sendable` `XLLiteral` implementation as
a named SQLite codec. Requiring `Sendable` keeps the immutable configuration
safe to share between tasks; the original v1 literal path remains unchanged for
older types. This is a compatibility bridge, not permission to change storage
implicitly: declare the actual v1 storage class, test existing rows, and retain
the old representation until a deliberate migration has completed.

The adapter calls the literal's existing `bind(context:)` and
`init(reader:)` implementations; it does not call `sqlDefault()`. A new
`XLCustomType` can therefore omit an explicit placeholder when all of its result
decoding uses generated static layouts. Keep an explicit placeholder on older
types for as long as legacy result introspection remains in use.

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
