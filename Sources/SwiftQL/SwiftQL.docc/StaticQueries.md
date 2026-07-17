# Static queries

Define immutable, database-independent SQL contracts with durable identities,
typed parameter metadata, flat result layouts, and explicit row cardinality.

## Overview

An `XLStaticQueryDescriptor` is the complete static contract for one rendered
statement. It retains SQL, dialect requirements, referenced entities, parameter
slots, result slots, and cardinality. It does not retain a database, connection,
physical statement, codec registry, or invocation value. You can therefore
construct and register descriptors before opening a database, then prepare the
same descriptor against a compatible database when it is needed.

Static descriptors complement ordinary SwiftQL requests. Use a request when
you want the existing typed row-reader facade. Use a descriptor when you need a
durable query identity, an immutable cross-task prepared handle, an explicit
result contract, or a registry of query definitions.

## Construct a descriptor

First render a statement and convert its validated encoding into an
`XLStaticStatementDefinition`. The following example uses the `Date` codec from
<doc:CustomTypes>. It resolves the contextual codec without a database, records
one parameter, and declares the selected output as one result slot.

<!-- test: XLDocumentationTests.testDocumentationStaticQueries -->
```swift
let staticQueryDialect = XLSQLiteDialect()
let staticDateCoding = try XLValueCodingConfiguration(
    registry: try XLValueCodecRegistry().registering(decimalDateCodec),
    defaultCodecKeys: [decimalDateCodecKey]
)
let cutoffContext = XLValueCodingContext(
    site: .parameter,
    path: XLValueCodingPath("invoice.cutoffDate")
)
let cutoffCodec = try staticDateCoding.resolvedCodec(
    for: Date.self,
    using: staticQueryDialect,
    context: cutoffContext
)
let cutoffParameter = XLContextualBindingReference<
    Date,
    String,
    XLSQLiteDialect
>(
    key: .named("cutoffDate"),
    codec: cutoffCodec
)

let cutoffEncoding = try XLiteEncoder(dialect: staticQueryDialect)
    .makeValidatedSQL(sql { _ in Select(cutoffParameter) })
let cutoffStatement = try XLStaticStatementDefinition(
    validating: cutoffEncoding
)
let cutoffParameterIdentity = try XLQuerySlotIdentity(
    path: ["invoice", "parameter", "cutoffDate"]
)
let selectedDateIdentity = try XLQuerySlotIdentity(
    path: ["invoice", "result", "cutoffDate"]
)
let cutoffMetadata = try cutoffParameter.staticQueryParameter(
    identity: cutoffParameterIdentity,
    in: cutoffStatement.parameterLayout
)
let selectedDate = XLStaticQueryResultSlot(
    index: XLLogicalResultIndex(0),
    identity: selectedDateIdentity,
    valueTypeIdentifier: cutoffCodec.identity.valueTypeIdentifier,
    valueTypeName: String(reflecting: Date.self),
    nullability: .required,
    codecIdentity: cutoffCodec.identity,
    storageIdentifier: cutoffCodec.identity.storageIdentifier,
    codingContext: XLValueCodingContext(
        site: .result,
        path: XLValueCodingPath("invoice.cutoffDate")
    )
)
let cutoffDescriptor = try XLStaticQueryDescriptor(
    definitionIdentity: XLQueryDefinitionIdentity(
        path: ["invoice", "selected-after-cutoff"],
        version: 1
    ),
    statement: cutoffStatement,
    parameters: [cutoffMetadata],
    results: try XLStaticQueryResultMetadata(slots: [selectedDate]),
    cardinality: .exactlyOne
)
```

The renderer owns placeholder discovery and logical parameter order. Parameter
metadata must match the resulting `XLParameterLayout` exactly. Result indices
are also zero-based, contiguous, and in SQL output-column order.

Each selected property or direct output column is one flat `XLStaticQueryResultSlot`.
A selection with three columns therefore declares
three slots, even when a typed request would decode those columns into one
Swift value. Automatic synthesis of aggregate or nested property/result graphs
is owned by issue #40; static descriptors currently describe the flat values
that cross the driver boundary.

## Stable identity

`XLQueryIdentity.canonicalBytes` is the durable identity; `canonicalHex` is its
diagnostic and persistence-friendly spelling. Never persist Swift's randomized
`hashValue`.

Identity format v1 includes:

- The identity format version and definition path/version.
- Exact rendered SQL bytes.
- Dialect identity, minimum version, and required capabilities.
- Each parameter's stable slot identity, logical index, binding key, stable
  value-type identifier, nullability, and dialect storage identifier.
- Cardinality and each result's stable identity, index, stable value-type
  identifier, nullability, and dialect storage identifier.
- The referenced entity set in canonical order.

It deliberately excludes invocation values, database and driver identity,
connection state, physical statements, codec registries, diagnostic Swift type
names, coding-context paths, and codec keys or versions when the stable storage
contract is unchanged. Those excluded codec and diagnostic fields remain in
the descriptor so preparation and decoding can still validate the exact
metadata selected by the query.

Metadata strings that participate in identity use Unicode NFC normalization,
so canonically equivalent definition paths, slot paths, binding names, stable
identifiers, and entity names produce the same identity material.
Rendered SQL is different: it remains exact UTF-8 and is never
Unicode-normalized. Canonically equivalent SQL spellings are still distinct
SQL contracts.

### Definition versions and registries

`XLQueryDefinitionIdentity` is human assigned. Keep its path stable and
increment `version` whenever that definition intentionally adopts a different
canonical contract. If two descriptors reuse the same path and version with
different canonical material, call
`validateDefinitionCompatibility(with:)` while registering them; it fails with
`XLStaticQueryError.definitionIdentityCollision`. A version increment creates a
new logical definition and does not collide.

An application-owned descriptor registry can be a value-semantic collection
created before any database exists. Registration should validate definition
compatibility and retain the descriptor, not just its identity, because codec
selection and diagnostic metadata are intentionally richer than the stable
identity projection. This registry is independent of
`XLValueCodecRegistry`, which supplies value codecs when a descriptor is
prepared.

## Prepare and invoke

Preparing binds the database-independent descriptor to one `GRDBDatabase` and
returns a `Sendable` `GRDBPreparedStaticQuery`. Preparation validates dialect
requirements and every contextual codec against the database's immutable coding
configuration. The handle retains that exact configuration snapshot; it never
consults process-global mutable state and does not own a connection-bound
SQLite statement.

Create a fresh `XLInvocationBindings` packet for every call. The packet owns
only normalized dialect values and is validated against the descriptor's
immutable layout. Neither packet construction nor execution mutates the
descriptor or prepared handle.

<!-- test: XLDocumentationTests.testDocumentationStaticQueries -->
```swift
let staticDatabase = try GRDBDatabase(
    url: databaseURL,
    codingConfiguration: staticDateCoding,
    logger: nil
)
let preparedCutoff = try staticDatabase.prepareInvocation(
    with: cutoffDescriptor
)
let preparedCutoffParameter = try preparedCutoff.preparedParameter(
    Date.self,
    identifiedBy: cutoffParameterIdentity
)
let cutoffBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: preparedCutoff.parameterLayout,
    bindings: [
        try preparedCutoffParameter.encode(
            Date(timeIntervalSince1970: 86_400)
        )
    ]
).validatingComplete()
let cutoffRow = try preparedCutoff.fetchExactlyOneValues(
    bindings: cutoffBindings
)
let cutoffResultCodec = try preparedCutoff.resultCodec(
    Date.self,
    identifiedBy: selectedDateIdentity
)
let decodedCutoff = try cutoffResultCodec.decode(cutoffRow[0])
```

The prepared parameter and result codec verify the descriptor's complete codec
identity against the retained database snapshot. Rebuilding a database with a
different default does not alter an existing handle.

### Intrinsic and contextual slots

Contextual parameters and results retain an `XLValueCodecIdentity`. Use
`preparedParameter(_:identifiedBy:)` to encode an application value and
`resultCodec(_:identifiedBy:)` to decode the returned dialect value. Both
operations fail if the exact selected codec is absent or incompatible in the
prepared snapshot.

Intrinsic `Bool`, `Int`, `Double`, `String`, and `Data` slots have no contextual
codec identity. Build their packet bindings directly from `.integer`, `.real`,
`.text`, or `.blob` `XLSQLiteValue` values and consume their result values in
the same raw form. The prepared handle still enforces declared storage and
nullability. `NULL` must be a present `.null` binding for a nullable slot;
omitting a binding is an incomplete packet.

### Cardinality

Cardinality is part of stable query identity and selects the only valid
execution operation:

| Cardinality | Prepared operation | Contract |
| --- | --- | --- |
| `.command` | `execute(bindings:)` | Returns no result slots. |
| `.exactlyOne` | `fetchExactlyOneValues(bindings:)` | Requires exactly one row. |
| `.zeroOrOne` | `fetchZeroOrOneValues(bindings:)` | Accepts zero or one row and rejects more. |
| `.many` | `fetchAllValues(bindings:)` | Accepts any number of rows. |

Descriptor construction rejects result slots on a command and rejects an empty
result layout for every row-returning cardinality. Prepared execution also
rejects calling an operation that does not match the descriptor cardinality,
then validates every returned row's column count, storage, and nullability.
