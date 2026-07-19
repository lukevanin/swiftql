# Static queries

Define immutable, database-independent SQL contracts with durable identities,
typed parameter metadata, flat result layouts, and explicit row cardinality.

## Overview

Introduced in v1.2, an `XLStaticQueryDescriptor` is the complete static contract
for one rendered statement. It retains SQL, dialect requirements, referenced
entities, parameter slots, result slots, and cardinality. It does not retain a
database, connection,
physical statement, codec registry, or invocation value. You can therefore
construct and register descriptors before opening a database, then prepare the
same descriptor against a compatible database when it is needed.

Static descriptors complement ordinary SwiftQL requests. Existing v1 requests
remain source compatible. Use a generated static row layout when a model has
contextual-codec properties that do not conform to `XLLiteral`, or whenever
query construction must not execute a model initializer, `SQLReader`, or
`sqlDefault()`. Pair that layout with a descriptor when you also need a durable
query identity, an explicit result contract, typed fetch operations, or a
registry of query definitions. The raw `GRDBPreparedStaticQuery` handle is
`Sendable`; the closure-backed typed row layout and its prepared wrapper are
currently task-local.

### Build-validation research boundary

A static descriptor contains the stable SQL and parameter/result metadata that
future build validation can consume, but it does not validate a schema by
itself. The v1.3 research for issue
[#132](https://github.com/lukevanin/swiftql/issues/132) pairs descriptors with
an explicit sidecar plan and a pinned SQLite snapshot, then uses a private
prototype to prepare and inspect each statement on a validator-owned read-only
connection. The prototype is conformance evidence, not a public SwiftQL
product or API.

Successful prototype validation applies only to the recorded snapshot, SQLite
build, and registered capabilities. It does not prove result values,
cardinality, dynamic storage classes, codec behavior, or application semantics.
The inspected statement is finalized immediately; runtime execution still
prepares or retrieves a cached physical statement on its own connection. A
standalone validator and SwiftPM plugin remain separate v1.5 follow-up work.

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
let cutoffParameterIdentity = try XLQuerySlotIdentity(
    path: ["invoice", "parameter", "cutoffDate"]
)
let cutoffParameter = try staticDateCoding.queryCapture(
    Date.self,
    expressedAs: String.self,
    identifiedBy: cutoffParameterIdentity,
    using: staticQueryDialect,
    context: cutoffContext
)

let cutoffEncoding = try XLiteEncoder(dialect: staticQueryDialect)
    .makeValidatedSQL(sql { _ in Select(cutoffParameter) })
let cutoffStatement = try XLStaticStatementDefinition(
    validating: cutoffEncoding
)
let selectedDateIdentity = try XLQuerySlotIdentity(
    path: ["invoice", "result", "cutoffDate"]
)
let cutoffMetadata = try cutoffParameter.staticQueryParameter(
    in: cutoffEncoding
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

### Capture Swift invocation values

Use `XLQueryCapture` when a static query gets an immutable value from its Swift
caller. A capture is a value-free declaration token: it stores a durable slot
identity, expression nullability, dialect storage, and selected codec metadata,
but never the caller's value or a database. Referencing the same capture more
than once emits the same named placeholder and creates one logical binding in
first-traversal order.

The runtime DSL cannot distinguish a bare Swift variable from an inline SQL
literal, so capture inference is explicit at this bridge today: put the
`XLQueryCapture` in the expression and supply its value only when building the
invocation packet. The syntax-aware query macro planned by issue #26 can
generate these same stable tokens and packets for bare captured variables; it
does not require a second runtime binding model.

Intrinsic `Bool`, `Int`, finite `Double`, `String`, and `Data` inputs use
`intrinsic(identifiedBy:)`. Contextual inputs use an immutable coding
configuration or database factory. Contextual inference filters codecs by the
SQL literal's storage first. A matching configuration default wins; otherwise
exactly one matching codec is required. Use `.explicit(codecKey)` or
`.query(codecKey)` when more than one codec represents the same Swift type in
that storage class. This query-specific path never consults a legacy or
process-global fallback.

When a typed column or other `XLExpression` is available, use
`queryCapture(_:matching:identifiedBy:)`. Its associated literal type supplies
the SQL nullability and storage contract, so a `Date` matched to an expression
of `String` selects only `TEXT` codecs. Keep the `expressedAs:` factory as the
explicit fallback when declaration-time expression metadata is unavailable.
Generated domain-property metadata beyond an expression's literal type belongs
to the typed row-layout layer.

`staticQueryParameter(in:)` validates the rendered dialect as well as the
capture's complete parameter declaration. This is important for codec-free
intrinsic captures, whose metadata otherwise has no codec dialect to verify.
The token's stable binding name uses NFC-normalized, length-prefixed identity
components; it does not use `hashValue` or a slash-joined path.

After the descriptor is prepared, build a fresh packet from immutable per-call
arguments such as `cutoffCapture.argument(cutoffDate)`, or use the builder
closure for dynamic assembly. Arguments are intended for immediate packet
construction. Applying one copies only its encoded dialect value into the
packet; the reusable prepared handle stores neither arguments nor completed
packets. Contextual conversion is resolved from the prepared handle's
snapshotted configuration, not from whichever configuration happens to be
current when the call runs.

The nonoptional `argument` and `bind` overloads accept required or nullable
captures. Passing `nil` is available only for a capture whose SQL expression
type is optional, such as
`XLQueryCapture<String, String?, XLSQLiteDialect>`; `nil` becomes a present SQL
`NULL`, never an omitted binding. The completed packet rejects missing,
duplicate, foreign, or metadata-conflicting captures. Codec-selection failures
retain the capture identity, expected dialect and storage, selection tier,
ordered candidates, coding context, and the underlying deterministic detail.

Collections do not expand into a runtime-dependent number of placeholders.
Represent a collection as one dialect scalar through a contextual codec, such
as a JSON `TEXT` value consumed by SQLite's `json_each(?)`, or declare a fixed
number of element captures in the query structure. Runtime identifiers are not
bindable values: table, column, and ordering choices must remain in the static
SwiftQL expression graph.

Each selected property or direct output column is one flat `XLStaticQueryResultSlot`.
A selection with three columns therefore declares
three slots, even when those columns decode into one Swift row. Generated
`staticRowLayout(using:...)` factories position those slots in declaration
order and retain the corresponding typed encode/decode behavior.

## Generate a typed row layout

`@SQLTable` and `@SQLResult` generate a nominal
`staticRowLayout(using:...)` factory alongside the existing `columns(...)`
factory. Supply one `XLStaticSelectField` for each property. Intrinsic v1
literals can use `XLStaticSelectField.intrinsic`; contextual values use
`XLValueCodingConfiguration.staticResultField`, with an explicit intrinsic
storage carrier such as `String.self` and a codec selection when needed.

The public field type is
`XLStaticSelectField<Value, Storage, Dialect>`. It retains a storage-typed
`expression`, `storageIdentifier`, `codecSelection`, and the resolved
`selectedCodecIdentity`. This makes the result-to-parameter handoff explicit:
pass `field.expression` to `queryCapture(_:matching:identifiedBy:)` and reuse
`field.codecSelection`. The resulting capture must have the same storage and
selected codec identity as the field. Generated layout factories accept each
concrete field through a primary-associated-type protocol, so every property
keeps its independently inferred `Storage` without synthesized generic names
that can shadow model generics.

The factory assigns declaration indices and SQL aliases, validates them through
`XLStaticRowMetadata`, and returns `XLStaticRowLayout`. Constructing that layout
or `Select(layout)` only inspects immutable metadata and expressions. The
generated model initializer and codec decode closures run only when a row is
actually decoded. Empty rows follow the same rule: `Self()` appears inside the
decode closure, not in layout construction.

Optionality belongs to the generated field, not to its codec. A `Date?`
property therefore uses the same selected `Date` codec as a required `Date`,
while the layout maps SQL `NULL` to and from `nil`. Two properties of the same
Swift type can select different codec keys; their projection metadata,
layout-based encoding, and decoding remain distinct.

`XLTypedStaticQueryDescriptor` pairs the operational layout with an existing
structural descriptor and requires exact equality between
`descriptor.results` and `layout.metadata.results`. The type contains no GRDB
API. Preparing it through `GRDBDatabase` returns a
`GRDBPreparedTypedStaticQuery`, whose typed fetch operations decode raw SQLite
rows through the retained layout.

The existing `XLResult`, `SQLReader`, `columns(...)`, table, union, and common
table APIs remain the v1 compatibility path. Their `XLLiteral` behavior,
including `wrapSQL`, is unchanged. Contextual-only properties compile in
generated metadata, but must use a static layout for value encoding and row
decoding instead of the v1 `MetaInsert`/`MetaUpdate` and introspection path.

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
returns a `Sendable` `GRDBPreparedStaticQuery`. Preparing a matching typed
descriptor instead returns `GRDBPreparedTypedStaticQuery`. Preparation validates
dialect requirements and every contextual codec against the database's immutable
coding configuration. The handle retains that exact configuration snapshot; it
never consults process-global mutable state and does not own a connection-bound
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
let cutoffBindings = try preparedCutoff.makeInvocationBindings(
    cutoffParameter.argument(Date(timeIntervalSince1970: 86_400))
)
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
codec identity. Prefer an `XLQueryCapture` and `makeInvocationBindings` for new
static queries. The explicit packet API remains available and source-compatible:
you can still build bindings directly from `.integer`, `.real`, `.text`, or
`.blob` `XLSQLiteValue` values and consume result values in the same raw form.
The prepared handle enforces declared storage and nullability either way.
`NULL` must be a present `.null` binding for a nullable slot; omitting a binding
is an incomplete packet.

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
