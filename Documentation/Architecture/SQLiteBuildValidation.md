# Build-Time SQLite Query Preparation and Schema Validation

## 1. Executive decision and v1.3 boundary

Issue [#132](https://github.com/lukevanin/swiftql/issues/132) is a research-only
v1.3 deliverable. The v1.3 release boundary is existing public SQLite syntax
proven against real SQLite; it does not ship a public validator, build plugin,
query macro, schema system, or new query-declaration API.

The selected validation contract is an explicit, checked-in SQLite database
snapshot plus a deterministic sidecar plan for static query descriptors. A
standalone validator owns a read-only SQLite connection, prepares each query
with `sqlite3_prepare_v3`, compares the resulting C metadata with the declared
plan, and emits a deterministic report. Only `passed` is success. `failed` and
`unsupported` both fail the validation gate.

The prepared statement exists only while one query is inspected. It is always
finalized and is never persisted, serialized, returned, or reused by runtime
execution. Runtime code still prepares or obtains a cached statement on each
physical connection.

## 2. Inputs audited

This decision builds on existing ownership rather than defining a parallel
model:

- [#128](https://github.com/lukevanin/swiftql/issues/128) separates query
  construction, uncached preparation, cache lookup, binding, execution, and
  decoding. Build validation does not remove the first physical prepare on a
  runtime connection.
- [#129](https://github.com/lukevanin/swiftql/issues/129) provides
  `XLStaticQueryDescriptor`: stable definition and query identities, exact SQL,
  dialect requirements, entity hints, canonical parameter and result layouts,
  cardinality, and codec/storage metadata. It owns no connection or statement.
- [#190](https://github.com/lukevanin/swiftql/issues/190) owns the canonical
  SQLite inventory and stable feature IDs in
  [`SQLiteConformanceInventory.json`](../../Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json).
- [#191](https://github.com/lukevanin/swiftql/issues/191) owns the bounded
  combinatorial manifest and its original 141 stable cases. [#286](https://github.com/lukevanin/swiftql/issues/286)
  adds 27 finite typed function-overload cases, [#288](https://github.com/lukevanin/swiftql/issues/288)
  adds 5 finite typed query-backed IN cases, and [#287](https://github.com/lukevanin/swiftql/issues/287)
  adds 10 packed operator-family cases, producing the current
  `c191-v2` manifest with 183 cases and runtime provenance in
  [`COMBINATORIAL_CASES.json`](../../Conformance/SQLite/COMBINATORIAL_CASES.json).
  Its runtime collector already records SQLite version/source ID, compile
  options, functions, collations, module names, caller-supplied extension names,
  and exact `sqlite_schema` evidence.
- [#254](https://github.com/lukevanin/swiftql/issues/254) owns the immutable
  Northwind database and its validation/access policy in
  [`NorthwindFixture.swift`](../../Tests/SwiftQLNorthwindFixtures/NorthwindFixture.swift).

The current static descriptor validates its own logical layout and codec/storage
coherence. It does not contain a schema fingerprint or all engine capability
requirements, and it is intentionally not made `Codable` by this research.

## 3. Validation question and non-goals

The question is narrow: given static SQL, declared parameter/result metadata,
explicit capabilities, and a reproducible SQLite schema, what can the same
SQLite parser reject before application runtime?

The prototype may establish syntax resolution, statement shape, C-level bind
and result metadata, schema identity, and engine capability evidence. It is not:

- a semantic query oracle or application-query execution system;
- a migration runner, typed DDL implementation, or schema-diff generator;
- a replacement for catalog/table-reference validation;
- a proof of SQLite dynamic value storage, result nullability, or codec closure
  behavior;
- a statement cache, bytecode format, or zero-runtime-parse design; or
- a new owner for the #190 inventory, #191 harness, or #254 fixture.

## 4. Schema-source comparison and selected contract

| Candidate | Reproducibility | Current ownership | Decision for #132 |
| --- | --- | --- | --- |
| Checked-in SQLite snapshot | Exact bytes and native SQLite parser semantics can be pinned and reviewed. | #254 already supplies an immutable real database. | **Selected.** |
| Ordered migrations | Reproducible only after migration ordering, engine setup, and failure policy are standardized. | Migration research and implementation are separate work. | May produce a snapshot later; not implemented here. |
| Typed DDL | Could provide a semantic catalog and generate a snapshot, but the surface does not exist yet. | [#139](https://github.com/lukevanin/swiftql/issues/139). | Future producer only; not implemented here. |

The selected snapshot is the checked-in Northwind database at upstream commit
`865de0872e61692a49cd6069cd2df8f9ac04541e`:

| Property | Pinned value |
| --- | --- |
| SHA-256 | `cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8` |
| Byte count | `602112` |
| Application tables / views | `13` / `17` |
| `sqlite_schema` rows | `37` |
| Existing #191 schema FNV-1a 64 | `e2c8fadbd38c2313` |

The FNV value uses #191's ordered fields `type`, `name`, `tbl_name`, `rootpage`,
and `COALESCE(sql, '')`. It is exact runtime provenance, not a semantic catalog
or migration identity: root pages and raw schema SQL are deliberately included.

A snapshot update is explicit: replace the artifact, update its upstream and
license provenance, SHA, byte count, object/row sentinels, schema row count and
FNV evidence, then review the deterministic validation-report diff. Future DDL
or migration tooling may materialize this input, but the validator boundary
remains a snapshot URL plus pinned identity.

## 5. Prototype architecture and data flow

```text
XLStaticQueryDescriptor + deterministic sidecar plan
                         + checked-in SQLite snapshot
                         + explicit codec/capability availability
                                      |
                                      v
                         standalone validation engine
                         - verify snapshot identity
                         - open one owned read-only connection
                         - capture runtime provenance
                         - prepare and inspect each query
                         - finalize every statement
                                      |
                                      v
                         canonical validation report
```

The validator owns its `sqlite3 *` for the full run. It does not borrow an
application connection or GRDB pool, and no statement or connection escapes.
Functions, collations, modules, or extensions are valid evidence only when
registered on that exact connection. The canonical snapshot remains read-only;
validation prepares but does not step application statements.

The engine is the single source of validation behavior. A prototype CLI may
drive it, but neither is a public v1.3 SwiftQL product or API.

## 6. Static validation-plan artifact

The sidecar plan fills the reproducible-build fields that do not belong in the
frozen `XLQueryIdentity` v1 representation. Each entry records:

- plan schema version, descriptor definition identity, and canonical query
  identity;
- exact UTF-8 SQL and dialect/version requirement;
- logical parameter indexes, physical placeholder spellings, nullability,
  storage identifiers, and selected codec identities;
- result indexes, declared stable aliases where available, cardinality,
  nullability, storage identifiers, and selected codec identities;
- expected snapshot SHA, byte count, schema row count, and exact provenance
  fingerprint;
- required SQLite version, compile options, functions, collations, virtual-table
  modules, and explicit extension identities; and
- existing #190 feature IDs, #191 case IDs, and Northwind anchor IDs used as
  evidence.

The plan is a sidecar, not a second structural query model. Descriptor fields
remain authoritative where they overlap. The prototype uses only existing
canonical references in its representative positive cases; #132-specific
negative fixtures use local query IDs rather than pretending to be conformance
cases. Strict registry resolution for arbitrary sidecar input belongs to the
versioned manifest contract in
[#292](https://github.com/lukevanin/swiftql/issues/292). #132 does not mint
another syntax family. Canonical JSON sorts entries and set-like fields and
excludes timestamps, hostnames, process IDs, absolute paths, and elapsed times.

## 7. `sqlite3_prepare_v3` probe lifecycle

The probe follows SQLite's documented
[`sqlite3_prepare_v3`](https://www.sqlite.org/c3ref/prepare.html) ownership rules:

1. Verify the snapshot bytes, then open a dedicated connection with
   `SQLITE_OPEN_READONLY`.
2. Reject embedded NUL, keep the SQL UTF-8 buffer alive, and pass its exact byte
   length to `sqlite3_prepare_v3` with flags `0`. `SQLITE_PREPARE_PERSISTENT` is
   only an allocation hint and is inappropriate for this one-shot inspection.
3. Require a non-null statement. Empty, whitespace-only, or comment-only SQL
   produces no statement and is rejected.
4. Follow `pzTail`. Re-prepare remaining text so whitespace/comments may be
   exhausted; any second non-null statement is rejected as multiple SQL.
5. Inspect bind, result, and readonly metadata only after successful prepare.
6. Call `sqlite3_finalize` for every non-null statement on every path, then
   close the validator-owned connection after the run.

A prepared statement is tied to the connection that created it. Stock SQLite
does not expose statement serialization; database
[`sqlite3_serialize`](https://www.sqlite.org/c3ref/serialize.html) serializes a
database image, not `sqlite3_stmt`. The prototype therefore makes no persisted
statement, bytecode portability, or zero-runtime-parser claim.

## 8. What can be proven

On the selected connection and snapshot, the validator can prove:

- the SQL is one non-empty statement accepted by the real SQLite parser;
- referenced tables, columns, functions, and collations needed during prepare
  resolve in that environment;
- the C parameter index/name layout agrees with the declared layout;
- the result-column count agrees with the descriptor and explicitly declared
  result aliases agree where stable aliases exist;
- explicitly declared engine capabilities are present in captured evidence;
- the snapshot and SQLite build match recorded provenance; and
- `sqlite3_stmt_readonly` classifies the directly prepared statement as
  read-only or potentially writing.

`sqlite3_stmt_readonly` is an engine-level direct-statement classification. It
does not replace semantic DML-role analysis and does not prove that functions or
virtual tables have no external side effects.

### Binding introspection

[`sqlite3_bind_parameter_count`](https://www.sqlite.org/c3ref/bind_parameter_count.html)
returns the largest parameter index, not necessarily the number of distinct
logical values; `?NNN` may create gaps. The validator must compare the complete
physical index map rather than equating this value with `parameters.count`.

[`sqlite3_bind_parameter_name`](https://www.sqlite.org/c3ref/bind_parameter_name.html)
is one-based, includes the `:`, `@`, `$`, or `?NNN` prefix, and returns null for
anonymous `?`. Repeated named placeholders share a physical index. Preparation
can check this layout, but a null name cannot distinguish an anonymous `?` from
an unused index gap introduced by `?NNN`. It also cannot prove Swift argument
values or runtime storage without binding and stepping.

### Result, codec, and capability checks

`sqlite3_column_count` is authoritative for prepared result width. Column names
are compared only when the plan declares stable `AS` aliases; SQLite does not
promise stable names for unaliased expressions. `sqlite3_column_decltype` may be
null for expressions and reports declared origin type rather than a runtime
storage class.

Descriptor construction already checks codec/value/storage coherence. The
validator can additionally compare declared codec identities with an explicit
available-codec manifest. It cannot execute or inspect codec closures.

Capabilities are checked against `sqlite_version()`/`sqlite_source_id()`,
`PRAGMA compile_options`, `function_list`, `collation_list`, and `module_list`.
SQLite has no portable registry of arbitrary loaded-extension library names, so
the connection owner must supply those identities explicitly. An absent or
otherwise unavailable required capability is `unsupported`. Neither a failed
declaration check nor an unsupported capability passes.

## 9. What cannot be proven

Successful preparation does not prove:

- persisted or reusable statement bytecode;
- the first runtime prepare has been eliminated;
- result values, row counts, cardinality, ordering semantics, or application
  behavior without execution and an independent oracle;
- SQLite runtime storage classes for dynamically typed expressions;
- general result nullability, especially through expressions, joins, CTEs, and
  subqueries;
- codec encode/decode behavior or compatibility inferred from declared SQLite
  types;
- table identity, catalog membership, alias/reference binding, correlated
  scopes, or semantic DML roles; or
- custom functions, collations, modules, or extensions that are registered only
  on a different future runtime connection.

Optional SQLite column-origin metadata also depends on
`SQLITE_ENABLE_COLUMN_METADATA`; its absence must not be treated as successful
structural validation.

## 10. Diagnostic taxonomy and verdict rules

Query diagnostics include the definition/query identity, applicable #190
feature IDs, #191 case IDs and Northwind anchor IDs, plus a stable code and
deterministic message. Snapshot/runtime diagnostics are report-scoped. Expected
and observed values currently live in the message rather than separate
structured fields. SQLite primary/extended result codes and copied
`sqlite3_errmsg` text are present only for engine preparation failures; that raw
wording is supporting evidence, not a stable diagnostic identity.

| Area | Stable diagnostic codes |
| --- | --- |
| Snapshot | `schema.snapshot-sha`, `schema.byte-count`, `schema.row-count`, `schema.fingerprint` |
| Runtime | `runtime.capture` |
| Statement | `statement.empty`, `statement.embedded-nul`, `statement.multiple`, `sqlite.prepare.failed` |
| Parameters | `parameter.count`, `parameter.key`, `parameter.metadata`, `parameter.syntax` |
| Results | `result.count`, `result.name` |
| Codecs | `codec.missing`, `codec.value-type`, `codec.dialect`, `codec.storage` |
| Capabilities | `capability.dialect`, `capability.dialect-flags`, `capability.sqlite-version`, `capability.sqlite-json-functions`, `capability.compile-option`, `capability.function`, `capability.collation`, `capability.module`, `capability.extension`, `capability.missing` |

SQLite commonly reports both syntax and schema-name resolution failures as
`SQLITE_ERROR`. The validator does not parse error-message prose to manufacture
a stable subtype. Labeled negative fixtures prove that both classes are
rejected, while the primary/extended code and copied message preserve the exact
engine evidence.

Verdicts are deliberately fail-closed:

- `passed`: all required evidence was captured and every check agreed.
- `failed`: SQLite or a deterministic comparison disproved the declaration.
- `unsupported`: a required capability or evidence source was unavailable, so
  the validator could not prove the declaration.

Only `passed` permits a successful CLI exit. A run containing `failed` or
`unsupported` entries exits nonzero. Diagnostics are sorted by query identity,
then stable code, with result codes and message as deterministic tie breakers.
Raw SQLite wording remains evidence and never becomes a diagnostic code.

## 11. Runtime provenance and determinism

Each report records the exact SQLite version and source ID, normalized compile
options, functions with arity/flags, collations, module names, caller-supplied
extension names, the snapshot identity table from section 4, and normalized
explicit codec, extension, and opaque capability identifiers in
`environment_evidence`. That last field makes caller-supplied reasons for a pass
auditable. This reuses the #191 provenance vocabulary instead of inventing a
second runtime record.

Two runs with the same plan, snapshot, SQLite build, and capability
registration must produce byte-identical canonical JSON. A different SQLite
source or capability set should produce an explicit report difference, not be
silently normalized away. Time, duration, host, PID, and local paths belong in
optional run logs, never the canonical validation artifact.

The Northwind SHA is the authoritative byte identity. The schema FNV is useful
exact-environment evidence but includes root pages and raw SQL, so it must not
be used as the future semantic DDL or migration fingerprint.

## 12. Standalone, plugin, and macro lifecycles

| Surface | Responsibility | Decision |
| --- | --- | --- |
| Standalone validator | Own all schema verification, connection setup, preparation, comparison, diagnostics, and report generation. | Authoritative engine and first v1.5 implementation. |
| SwiftPM build-tool plugin | Declare snapshot/manifest inputs and report output, then invoke the standalone tool as a build command. | Thin future wrapper; no duplicated validator logic or schema inference. |
| `@SQLQuery` macro | Lower a declaration to the existing static descriptor model and emit/collect manifest material with declaration-site source context. | Owned by #26; must not open SQLite, load a schema, or implement semantic validation. |

The standalone form is reproducible outside a compiler or IDE. The plugin may
provide build integration after the manifest and validator are stable. A build
command is preferable when inputs and outputs are known so SwiftPM can perform
incremental invalidation. The macro remains constrained by the v1.x Swift 5.9
floor and delegates database work to the external validator lifecycle.

## 13. Benchmark implications

The #128 benchmark contract keeps construction/rendering, uncached preparation,
cached lookup, binding, execution, and decoding separate. Build validation may
move query-construction mistakes earlier and a future declaration flow may
avoid repeated SwiftQL construction, but it does not install a statement into a
runtime connection.

Each physical runtime connection still performs its first supported SQLite
prepare and may then use its own cache. #132 records no latency, throughput,
memory, startup, or zero-parse performance claim.

## 14. Compatibility and package impact

The research preserves the package's Swift 5.9 tools floor and current public
SwiftQL/SwiftQLCore APIs. It does not change `XLQueryIdentity` v1, make
`XLStaticQueryDescriptor` wholesale `Codable`, expose GRDB or CSQLite types in a
public contract, or add a public product.

Any research targets remain internal and use the package's existing SQLite
dependency. A v1.5 implementation must validate a clean downstream Swift 5.9
consumer and must not require a Swift 6-only macro or plugin feature merely to
use the existing v1 library.

## 15. Validation evidence matrix

The bounded prototype reuses representative stable cases; it does not rerun or
take ownership of all 141 #191 cases.

| Evidence | Existing IDs reused | Expected validation |
| --- | --- | --- |
| Named binding, join, and schema resolution | `c191.v1.select.j-inner.w-named-binding`; #190 `binding.named`, `syntax.expression.current-operators`, `syntax.join.current-inner-left-cross`, `syntax.select.core`; Northwind `northwind.join.customer-order-employee-product` | One `:minimum_order_id` physical binding, one result, successful Northwind prepare. |
| CTE and explicit two-column aliases | `c191.v1.northwind.cte-order-subtotals`; #190 `syntax.cte.recursive`, `syntax.expression.aggregate-functions`, `syntax.select.core`; Northwind `northwind.cte.order-subtotals` | Zero bindings, `orderID`/`subtotal` result layout, successful Northwind prepare. |
| Required function capability | `c191.v1.expression.numeric-floor`; #190 `syntax.expression.numeric-comparable-functions`; requirement `function:FLOOR` | Pass when `FLOOR` is captured; non-pass when required evidence is missing. |
| Deliberate invalid fixtures | Local test query IDs, not conformance IDs | Reject syntax, missing table/column, bind count/name, result count/alias, missing codec/capability evidence, and snapshot SHA/byte/FNV disagreement; the raw probe also rejects empty and multiple statements. |
| Lifecycle and determinism | Existing #191 runtime-evidence conventions | Exercise every probe outcome through exactly-once finalization, reject active SQLite sidecars (including through a snapshot symlink), preserve read-only snapshot access, and produce byte-identical reports on repeated equal runs. Runner-level tests execute plan decoding, real snapshot validation, report writes, byte-identical repeated output, and the `0`/`1` verdict exit contract; the executable maps argument/usage errors to `2`. |

Prototype tests verify that the representative #190/#191/Northwind IDs exist in
their canonical sources. Exhaustive reference resolution for arbitrary
manifests is an acceptance criterion of #292. #132-specific negative fixtures
remain validator tests rather than new conformance inventory entries.

## 16. Recommended v1.5 implementation sequence

1. Freeze the sidecar manifest schema and deterministic serialization without
   database I/O.
2. Ship the standalone validator and prove its diagnostics against the pinned
   Northwind snapshot and a clean downstream consumer.
3. Add a thin SwiftPM build-tool plugin after the standalone input/output
   contract is stable.
4. Let #26 consume the manifest seam when query declarations are available;
   keep macro diagnostics about Swift declarations separate from SQLite
   validation diagnostics.

Catalog semantics and future schema producers can enrich the same manifest
later without changing the validator's snapshot boundary.

## 17. Existing ownership and atomic follow-ups

Existing issues retain their scope:

- [#26](https://github.com/lukevanin/swiftql/issues/26) owns the `@SQLQuery`
  declaration macro, lowering, generated handles, and declaration-site
  diagnostics. #132 does not implement or redesign it.
- [#139](https://github.com/lukevanin/swiftql/issues/139) owns typed,
  dialect-aware DDL and future semantic schema metadata. #132 does not create a
  competing DDL or fingerprint model.
- [#214](https://github.com/lukevanin/swiftql/issues/214) owns catalog
  membership, table/reference bindings, aliases, nullability propagation, DML
  roles, and nested/correlated scope semantics. Preparation cannot substitute
  for those checks.
- #190/#191 continue to own inventory and harness identities; #254 continues to
  own Northwind; #129 continues to own the static descriptor.

Three atomic v1.5 follow-ups are recommended:

1. [**#292: Define a deterministic SQLite build-validation manifest for static
   query descriptors.**](https://github.com/lukevanin/swiftql/issues/292)
   Specify versioned canonical JSON, query/descriptor identity,
   parameter/result/codec layout, schema identity, capabilities, and #190/#191
   references. No database I/O, macro implementation, or query-identity change.
2. [**#293: Ship a standalone SQLite static-query build
   validator.**](https://github.com/lukevanin/swiftql/issues/293) Consume the
   manifest and snapshot, own a read-only connection, call
   `sqlite3_prepare_v3`, produce stable fail-closed diagnostics, and validate a
   real downstream fixture. No plugin, macro, DDL, migrations, or statement
   persistence.
3. [**#294: Add a SwiftPM build-tool plugin wrapper for SQLite query
   validation.**](https://github.com/lukevanin/swiftql/issues/294) Use declared
   inputs/outputs and invoke the standalone tool. No validation logic, schema
   inference, or second report format in the plugin.

A separate macro-integration follow-up would duplicate #26 and is not proposed.

## 18. Remaining risks and limitations

- A byte-exact snapshot can drift from an application's migration-produced
  schema unless the application makes snapshot updates part of its release
  process.
- SQLite functions, collations, virtual-table modules, and extensions are
  connection-local; validation is authoritative only for the recorded setup.
- Different SQLite builds may accept different syntax or expose different
  capabilities. Source ID and compile options therefore remain part of the
  verdict evidence.
- SQLite dynamic typing and optional column-origin metadata leave result
  storage, nullability, and codec behavior for runtime/conformance tests and
  #214's structural model.
- Build-tool sandboxing and incremental input discovery remain v1.5 integration
  questions; hiding inputs in a prebuild command would weaken reproducibility.
- Snapshot FNV evidence is intentionally physical and is unsuitable as a
  semantic migration/catalog fingerprint.
- The research does not establish a portable prepared-statement format or
  remove runtime per-connection preparation.
