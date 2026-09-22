# Changelog

## [2.0.0] - Unreleased

### Migration

- **Swift 6.1 is the minimum compiler** (issue #133). The package declares
  `swift-tools-version: 6.1` and builds in Swift 6 language mode. An older
  compiler cannot parse the manifest, so it cannot resolve SwiftQL 2.x at all.
  The floor is 6.1 rather than 6.0 because SwiftPM deprecated the `Path`
  plugin API at tools 6.0 and ships its replacement only from 6.1.
  **Stay on SwiftQL 1.x for an older toolchain.** The 1.x line keeps
  `swift-tools-version: 5.9`, Swift 5 language mode, and its Swift 5.9.2 Linux
  support point.
  - Your own code does **not** have to move to Swift 6 language mode. A client
    in Swift 5 mode compiles against the Swift 6 module, and
    `IntegrationTests/Swift5Client` proves it on every CI run.
  - Rows must now be `Sendable` (issue #685). A generic `@SQLTable` or
    `@SQLResult` model needs the conditional conformance stated by hand, such
    as `extension MyRow: Sendable where Value: Sendable {}`; the macro cannot
    write a `where` clause for a generic model.
  - CI drops its two Swift 5.9 Linux cells and its pinned Swift 6.0 support
    point. The floor is Swift 6.1 on macOS, and Linux is verified on Swift
    6.3.2, each in both resolution modes. See
    [COMPATIBILITY.md](COMPATIBILITY.md#pinned-compiler-support-points).
- **GRDB 7 is the only supported major** (issue #792). The manifest declares
  `from: "7.0.0"` (`7.0.0..<8.0.0`), and the committed resolution pins 7.11.1.
  One manifest cannot serve both majors, so an application still on GRDB 6
  must stay on SwiftQL 1.x. GRDB 7.0 needs Swift tools 6.0 and GRDB 7.10 needs
  6.1, which the Swift 6.1 floor above already supplies.
  - The `CSQLite` product is now `GRDBSQLite`, and `import GRDB` no longer
    re-exports the SQLite C module. A target that calls a `sqlite3_*` function
    declares the `GRDBSQLite` product and imports the module.
  - `XLLogger` now refines `Sendable`. SwiftQL logs from whichever thread runs
    a statement, so a logger must be safe for concurrent use. Protect any
    mutable state in your logger with a lock.
  - `GRDBDatabaseBuilder.addFunction(_:)` and `XLBuilder.customFunctionCall(_:parameters:)`
    now require the custom function's result type to be `Sendable`. GRDB 7
    registers a function through a `@Sendable` closure.
  - A `DatabasePool` observation performs one extra startup fetch on Linux.
    GRDB 7 disables its WAL-snapshot path there. See
    [COMPATIBILITY.md](COMPATIBILITY.md).

## [1.9.0] - 2026-09-16

### Migration

- **Declared queries generate new members** (issue #660). A member with the
  same name can stop compiling. Rename that member or specification.
  - `@SQLQueries` adds a `preparedQueries` property on the database type and a
    nested `Context.PreparedQueries` type. The macro reports these collisions
    at the declaration:
    - a query specification named `preparedQueries`, with or without
      parameters;
    - a property named `preparedQueries`, or a method `preparedQueries()` with
      no parameters, in the `@SQLQueries` extension itself.
  - The macro cannot see members outside its extension. A property named
    `preparedQueries`, or a method `preparedQueries()` with no parameters,
    declared in the type body or in another extension gives an
    "invalid redeclaration" error in generated code. A method named
    `preparedQueries` that has parameters does not collide.
  - `@SQLQuery` adds a peer `<name>PreparedQuery(...)` beside each executor,
    such as `personByNamePreparedQuery(name:)`. It has the parameters of the
    specification and returns `XLPreparedQuery<Row>`. A peer macro cannot see
    other members with swift-syntax 509, so the macro reports no collision.
    These declarations collide:
    - a property named `<name>PreparedQuery`, when the specification has no
      parameters: "invalid redeclaration";
    - a method `<name>PreparedQuery` with the same argument labels and
      parameter types that returns `XLPreparedQuery<Row>`: "invalid
      redeclaration";
    - the same method with a different return type: the declarations compile,
      but a call without a type annotation is ambiguous.

- **A `Data` value written into JSON fails before SQLite prepares the
  statement** (issue #671). This applies to a value passed to `jsonArray`,
  `jsonObject`, `jsonInserting`, `jsonReplacing`, `jsonSetting`,
  `jsonGroupArray`, `jsonGroupObject`, or one of their JSONB twins. The
  statement fails with the new case
  `XLSQLValueEncodingError.blobInJSONValue(valueType:function:)`. On 1.8.1,
  SQLite reported `JSON cannot hold BLOB values`, or it silently read the
  bytes as a document when they were valid JSONB. The result of a `jsonb`
  function is still accepted. To nest JSONB held in a `Data` column or
  parameter, pass it through `minifiedJSONB()` first. The check reads the
  static type, so a `Data?` value is rejected even when it is SQL `NULL`. For
  example, `jsonObject(("avatar", user.avatar))` with a nullable `Data` column
  wrote JSON `null` for a `NULL` row on 1.8.1, and now always throws
  `blobInJSONValue`. Pass the column through `minifiedJSONB()`, which keeps
  `NULL` as `NULL`, or leave it out of the document. This check runs when the
  statement renders, not at compile time. The JSON value parameters take
  `any XLExpression`, and a compile-time constraint would reject every opaque
  function result and every existential value that code passes today. A
  `switch` over `XLSQLValueEncodingError` with no `default` clause must handle
  the new case.
- **A JSON mutation on a non-optional document has a non-optional result**
  (issue #664). This applies to `jsonInserting`, `jsonReplacing`,
  `jsonSetting`, and `jsonRemoving` on a `String` document, and to their
  JSONB twins on a `Data` document. Where the call site gives no other type,
  Swift now infers `String` or `Data` instead of `String?` or `Data?`. Code
  that unwraps such a result twice, for example
  `if let row = try request.fetchOne(), let value = row`, must unwrap it
  once. The non-optional `jsonRemoving` and `jsonbRemoving` report the root
  path `$` with the new case
  `XLSQLValueEncodingError.jsonRootRemoval(function:)`, because SQLite
  returns `NULL` when it removes the root. On 1.8.1 that call returned SQL
  `NULL`. A `switch` over `XLSQLValueEncodingError` with no `default` clause
  must handle the new case. A call site that assigns the result to an
  optional column, or that passes it to `coalesce`, still compiles and
  renders the same SQL.

- **Build-validation manifest format version 2** (issue #658). New manifests
  are written as `format_version: 2`, and the reader accepts versions 1 and 2.
  A version 1 manifest decodes, validates, and encodes to the same bytes as on
  1.8.
  - `SQLiteBuildValidationManifest.conformanceInventoryVersion` and
    `combinatorialManifestVersion` are now `String?`, and so are the same
    properties on `SQLiteBuildValidationReport` and
    `SQLiteBuildValidationPlanReport`. Code that reads them must handle `nil`.
    A report omits the two keys when the manifest omits them.
  - `SQLiteBuildValidationParameterEntry.valueTypeName` and
    `SQLiteBuildValidationResultEntry.valueTypeName` are now `String?`.
  - `SQLiteBuildValidationManifestFormatVersion.current` is now `.v2`. To keep
    writing version 1, pass `formatVersion: .v1`.
  - `SQLiteBuildValidationManifestError` gains `unknownKey(path:)`, and
    `SQLiteBuildValidationPlanSuppressionError` gains `unknownKey(path:)`. A
    `switch` with no `default` clause must handle the new case.

- **Unknown keys fail closed** (issue #658). The manifest and the plan
  suppression file (`swiftql-plan-analysis.json`) reject a key their schema
  does not define, at every level, with `unknownKey(path:)`. A misspelled
  optional key no longer decodes as an absent field. A file that decoded on
  1.8 because it had an extra key now fails. Remove or correct the key.

- **Declared queries generate more members** (issue #659). `@SQLQueries`
  adds a `declaredQueries` property to the extended type and to its
  `Context`, and `@SQLQuery` adds a `<name>DeclaredQuery()` method beside each
  declaration. A type that already declares a member with one of these names
  gets a redeclaration error. Rename that member. Every generated member is
  an instance member that copies no specification body, so a declaration
  that compiled on 1.8 still compiles. The generated executors, their
  rendered SQL, and their runtime behaviour do not change.

### Added

- **Declared queries lower to a static descriptor** (issue #659). The macros
  emit what they know about each declaration: its name, cardinality,
  parameter names and types, row type, and value-free statement. The new
  `XLDeclaredQuery` type assembles that data into an `XLStaticQueryDescriptor`
  with `makeDescriptor()`. It renders the SQL with the encoder of the
  database the query was read from, takes the parameter layout from the
  rendered statement, and takes the result columns from a static row layout's
  metadata or from the row reader. The definition identity is the database
  type name, qualified by its enclosing types, and the specification name at
  version 1, so the descriptor identity does not change between builds of an
  unchanged declaration. No catalog is needed.

- **Declared-query discovery** (issue #659). The new
  `SwiftQLDeclaredQueryRegistryPlugin` build-tool plugin scans a target's
  sources with SwiftSyntax on every build and generates a
  `<Target>DeclaredQueries` registry into the target. Its `queries(for:)`
  method returns every `@SQLQueries` and `@SQLQuery` declaration of the
  database instances passed to it, and throws when a declaring type has no
  instance. A declaration the registry cannot reach is a build warning, and
  `// swiftql-registry: ignore` leaves one out without the warning. The scan
  reads every file of the target, and the registry keeps the source's `#if`
  conditions on imports, database types, and declarations. The plugin owns
  the name `<Target>DeclaredQueries` in the target. The
  `swiftql-declared-query-registry` executable is the tool the plugin runs.

- **A build-validation manifest from declarations** (issue #659). The new
  `SwiftQLSQLiteBuildValidationDeclaredQueries` library projects declared
  queries into a format version 2 manifest without fixture provenance.
  `SQLiteBuildValidationDeclaredQueryManifest.makeManifest(queries:snapshotIdentifier:snapshotURL:)`
  returns the manifest and the queries it had to skip, each with a reason.
  Generation does not validate: the validator and the build plugin stay the
  only validation step. The to-do demo now generates its manifest from its
  registry, and the hand-written list it used before is kept as a test
  fixture. `IntegrationTests/DeclaredQueryRegistryFixture` checks in CI that a
  query added to a target reaches the manifest and validates with no list or
  generator edited.

- **`@SQLBindings` generates a typed packet for the named bindings of a
  statement value** (issue #663). Attach the macro to a struct that has one
  stored property for each named binding. For each property, the macro
  generates a static `XLNamedBindingReference` with the name and type of the
  property. The statement uses these references. The macro also generates
  `bindings(in:)` and `bindings(for:)`, which encode the property values into
  an immutable `XLInvocationBindings` packet for a layout or a request. A
  misspelled binding name, a misspelled value label, or a missing value is now
  a compile error. Before, a caller found each slot with a string name, and a
  typo failed at runtime. The macro reports an error for a property with an
  initial value and for an initializer in the struct, because either one would
  let a call leave a value out. The packet still throws when the statement does
  not use a declared binding, or uses a binding that the struct does not
  declare, so declare one struct for each statement shape. Generated members
  are `public` or `package` only when the struct itself is written that way.
  `scripts/ci/check-named-binding-packet-type-safety.sh` proves the compile
  errors in CI. The to-do demo builds all of its packets with `@SQLBindings`
  and has no slot-lookup helper.

- **A declared query can be observed** (issue #660). The prepared form of a
  declared query returns an `XLPreparedQuery<Row>`: the request from the
  declaration's render-once cache and the binding packet for one set of
  arguments. Call `stream()`, `streamOne()`, `publish()`, or `publishOne()` on
  it, or pass it to `XLObservableQuery` or `XLObservableQueryRow`. For
  `@SQLQueries`, call `database.preparedQueries.personByName(name:)`. For `@SQLQuery`,
  call `database.personByNamePreparedQuery(name:)`. The prepared form and the
  executor use the same cache entry and the same binding code, so the
  statement renders at most once for each database. An observation does not
  enforce the exactly-one cardinality of a `Row` declaration: when the row goes
  away, `streamOne()` delivers `nil`. The to-do demo observes its declared
  reads directly, and `TodoLiveReads.swift` and `TodoFilteredRead.swift` are
  removed.
- **A declared query can be called inside `withTransaction`** (issue #662).
  An `@SQLQueries` database-level executor called on the scope that
  `withTransaction(_:)` gives its body now runs on that scope. It runs on the
  transaction's connection and sees the transaction's uncommitted writes.
  Before, it opened a transaction of its own and threw
  `nestedTransactionUnsupported`. On a database, the executor still opens a
  transaction as before. The executor uses the render-once cache entry of the
  database and the same binding packet, so a scope adds no cache entry and no
  render. The scope rules do not change: an ended scope throws `scopeEscaped`,
  the original database used inside a body and `execute(_:)` called on a scope
  throw `nestedTransactionUnsupported`, and a query prepared on a scope cannot
  be observed. The `@SQLQuery` peer executor already ran on a scope. The to-do
  demo's transactions now use its declared reads.

- The JSON mutation functions have overloads whose result follows the
  document's nullability (issue #664). A mutation on a `NOT NULL` column
  assigns back to that column without `coalesce`. A `String?` or `Data?`
  document keeps the optional result. `jsonPatched(with:)` and
  `jsonbPatched(with:)` stay optional, because a `NULL` patch also gives
  `NULL`. The to-do demo's checklist writes no longer end with `coalesce`.

- **`GRDBDatabase.insert(contentsOf:)` inserts many rows through one
  statement** (issue #668). A loop of
  `makeRequest(with: sqlInsert(row)).execute()` renders each row's values into
  the SQL as literals, so every row renders a new statement and SQLite prepares
  every distinct row again. `insert(contentsOf:)` renders the insert once, with
  a bound parameter in place of each literal, prepares it once for the call,
  and binds each row through an invocation packet. A 100-row batch inside one
  transaction renders once and prepares once, where the per-row loop renders
  and prepares 100 times.
  - On a `withTransaction(_:)` scope the rows run inside a savepoint in that
    transaction. When a row fails, every row of the call rolls back and the
    body's other writes stay. On any other database the call opens one write
    transaction, so either every row commits or none does.
  - The prepared statement is a local value of the call, on the connection that
    prepared it. It never outlives the call's connection access, so a pooled
    connection or an ended scope cannot keep it.
  - A row whose values cannot be bound -- a value that renders as SQL other
    than one literal, or a value that fails to render, such as a non-finite
    `Double` -- renders on its own as `sqlInsert(_:)` does, in the same
    transaction, and fails with the same error.
  - The SQL `sqlInsert(_:)` renders for one row does not change.
  - On the Issue259 `transactional_write` workload, SwiftQL's median for one
    100-row transaction fell from 993.42 us and 1.00 ms (per-row
    `sqlInsert(_:)`, process spreads 5.1% and 4.0%) to 363.98 us and
    358.17 us (`insert(contentsOf:)`, spreads 5.3% and 4.5%), in alternating
    runs on one shared host. See `Benchmarks/Comparison/Issue259/README.md`.

- **Build-time validation from an Xcode application target.**
  `SwiftQLSQLiteBuildValidationPlugin` now also conforms to
  `XcodeBuildToolPlugin`, so an Xcode project target, such as an app, can add
  it under "Run Build Tool Plug-ins" (issue #666). Before, only a SwiftPM
  target could adopt it. The target makes
  `swiftql-build-validation-manifest.json` and
  `swiftql-build-validation-snapshot.sqlite` member files, in one folder. It
  can add `swiftql-plan-analysis.json` beside them to turn on plan analysis.
  The plugin finds these files by name among the target's input files, and
  runs the same validator command as the SwiftPM path. An invalid manifest
  fails the app's build with the validator's diagnostic.
  `IntegrationTests/BuildValidationPluginFixture/verify-xcode.sh` now builds
  an application target and checks the correctness report, the plan sidecar,
  and the failure on an invalid manifest. SwiftPM targets see no change.
- `validJSONOrJSONBOrNull()` renders `json_valid(X, 9)` (issue #671). It
  checks text as RFC 8259 JSON, accepts a blob that is well-formed JSONB or
  that holds well-formed JSON text, and needs SQLite 3.45.0.
  `validJSONOrNull()` still renders `json_valid(X)`, which reports false for
  every JSONB blob.

- **Benchmark evidence checks and SwiftQL production phases** (issue #670).
  - The compile-time summarizer reads SwiftPM's
    `Build of product '...' complete! (N.NNs)` line from each raw log. It
    rejects a sample when the wall time is greater than 2 x that duration
    + 2 s. It lists each rejected sample and exits with status 1, unless
    `--allow-rejected-samples` is given. The 2026-08-02 report has three
    rejected samples, in the 10-table SwiftQL clean cell and the 10-query raw
    SQLite edit cell. The runner applies the same rule and builds a rejected
    sample again, up to two more times.
  - The compile-time runner gets `--matrix extended` (1, 10, 100, and 500
    tables; 1, 10, and 100 queries) and `--generate-only`. It splits tables
    and queries into files of at most 50 declarations. Every scale up to 50
    generates the same bytes as before. Timed builds run `swift build -v`, so
    the runner detects a recompilation under Swift Build, the default build
    system from Swift 6.4, as well as under the native build system. Each
    measurement records the build system that ran. Before it builds a point,
    the runner deletes generated files that the point does not produce, and it
    checks that the consumer holds exactly its template and generated files.
    Validation rejects a report whose generated files disagree with the
    declared scale.
  - The phase harness writes report format version 2. Each SQL case adds six
    phases on SwiftQL's own path: `swiftql_binding`, `swiftql_execution`,
    `swiftql_row_materialization`, `swiftql_row_decoding`,
    `swiftql_fetch_all`, and `swiftql_execute`. Each query also gets a
    plain-value variant that renders its values as inline SQL literals. The
    six version 1 phases keep their names and boundaries, and version 1
    reports still validate.
  - `Benchmarks/record-baselines.sh` records the phase, comparison, and
    compile-time baselines at one revision into new dated files.
    `BENCHMARKS.md` gets a current-baseline section.

### Changed

- **A `Bool` written into JSON is a JSON boolean** (issue #671). The same
  functions as above write a Swift `Bool` as `true` or `false`, not as `1` or
  `0`. A `Bool` literal renders as `json('true')` or `json('false')`. Any
  other `Bool` expression renders as
  `json(CASE X <> 0 WHEN 1 THEN 'true' WHEN 0 THEN 'false' END)`, so SQL
  `NULL` stays JSON `null`. A `Codable` reader of a `Bool` field now reads the
  stored document. Code that reads such a member as a number must change.
  The to-do demo no longer writes `json('true')` by hand.

- **Manifest format version 2** (issue #658) lets a generated manifest be
  valid without invented provenance. In version 2,
  `conformance_inventory_version` and `combinatorial_manifest_version` are
  optional, `queries` can be empty, and `value_type_name` is optional on each
  parameter and result. An absent provenance field means that the manifest was
  not authored against SwiftQL's test inventories. A present field must not be
  empty, and a `conformance_feature_ids` or `conformance_case_ids` reference
  requires its inventory version. `nullability` stays required, because
  validation checks it. Version 1 keeps every check it had. The to-do demo's
  manifest is now version 2 with no provenance.

- **Version-first decoding** (issue #658). The manifest and the plan
  suppression file decode `format_version` before anything else. A document
  in a version the reader does not know fails with `unsupportedFormatVersion`,
  not with a decoding error from its body. `SQLiteBuildValidationPlanSuppressions`
  gains `decode(_:)` for in-memory data.
- OpenCombine is a Linux-only dependency (issue #669). The `SwiftQL` target
  and the test targets that import OpenCombine now use
  `condition: .when(platforms: [.linux])` on the `OpenCombine`,
  `OpenCombineDispatch`, and `OpenCombineFoundation` products. An Apple-platform
  build uses Combine and compiles and links no OpenCombine module. SwiftPM can
  still fetch the package on Apple platforms, because the manifest declares it.
- The OpenCombine requirement changes from `exact: "0.14.0"` to
  `from: "0.14.0"`. A consumer graph that needs a later compatible OpenCombine
  release now resolves. `Package.resolved` keeps the tested 0.14.0 pin, and
  the committed-resolution CI cells still build against it.
- **CI: Linux on Swift 6, and a shorter main-branch run.** The compatibility
  matrix adds a Swift 6.3.2 Linux cell (issue #672). It installs its toolchain
  through the same signature-verified Swift.org archive path and pinned SQLite
  3.53.3 build as the Swift 5.9.2 cells, so the OpenCombine bridge and the
  Foundation-backed codecs now run under swift-foundation. Source coverage is
  no longer a separate macOS job that runs the suite twice: the Swift 6.0
  committed cell runs the suite once under coverage, and a verifier derives the
  expected source selection from `git ls-files` and the coverage config. The
  Getting Started playground check moves to the Swift 5.9 Linux committed cell,
  and complete strict concurrency runs once, on the Swift 6.0 clean cell.
  `COMPATIBILITY.md` records the account's macOS runner limit that these moves
  work around.
- **Release: version claims are a release gate, not test pins.** The release
  workflow runs `scripts/ci/check-release-version-claims.sh` on the exact tag
  commit and fails unless the six published-version claims name the tag's
  version. The Swift documentation tests compare those claims with the newest
  dated CHANGELOG heading instead of a literal, and no longer pin SKILL.md's
  release sentence verbatim, so a version bump touches no test file.
- **To-do demo: live-query tests await state.** The demo's test target gains
  an Observation-driven wait with a named 10-second backstop. The tests no
  longer poll with `Task.sleep`, and no shipping product imports XCTest.

- **A declared query accepts a parameter as a method or clause argument**
  (issue #661). `@SQLQuery` and `@SQLQueries` now rewrite a parameter passed
  to a DSL method or clause, such as `column.like(pattern)`,
  `column.regexp(pattern)`, or `Limit(count)`, into its named binding, so a
  declared query can match text and limit its rows with parameters. The
  frozen-literal guard no longer rejects a call argument, a local binding
  initialized from a parameter, or a parameter in a nested closure, because
  the rewrite replaces each of these references. It still rejects string
  interpolation and member access on a parameter. A parameter passed to a call
  whose parameter type is `Any` or generic, such as `String(describing:)`, is
  not a binding: the call renders the description of a binding reference as a
  constant literal, and the macro does not detect it. Pass parameters only to
  SwiftQL expression APIs. The to-do demo's filtered read is a declared query
  again.

- Recorded the v1.9.0 surface in the #190 canonical SQLite conformance
  inventory: the JSON value rules that write a Swift `Bool` as a JSON boolean
  and reject a blob (issue #671), the non-optional JSON and JSONB mutation
  results (issue #664), and the batch insert statement and its savepoint
  rollback (issue #668). The JSON path record states the new quoting rule, the
  JSON function record states the JSONB-aware validity check and what
  `jsonArrayLength` returns, and the nested-transaction record states that the
  driver has an internal savepoint hook. The inventory version is now 1.9.0.
  It records 120 public-surface feature records: 116
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  1 unimplemented. Of the 224 evidence records, 137 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.

- **CI: the declared-query discovery fixture survives a kill by the runner**
  (issue #772). The macOS cell killed
  `IntegrationTests/DeclaredQueryRegistryFixture/verify.sh` with SIGKILL five
  times, always after the build of `fixture-manifest` reported that it was
  complete. The script built and ran the generator with one `swift run`
  command, so it reported the kill as a failed validation.
  - The script now builds the generator and runs it as two steps. A build
    failure fails the fixture at once with its own message, and only the run
    gives a check its result.
  - The script limits SwiftPM to two compiler processes. Local measurements
    give the peak memory of a cold build as 3.42 GB at 14 processes, 1.78 GB
    at 3, and 1.38 GB at 2. No measurement of the runner itself exists, so
    this cap lowers the peak but does not prove that it stops the kill.
  - The build and the run each have a time limit, and the script retries a
    step after a SIGKILL only. A retry writes a `::warning::` annotation, so
    the flake stays visible. Every other failure fails the fixture at once.
  - The three checks the fixture makes do not change. Set
    `SWIFTQL_FIXTURE_JOBS`, `SWIFTQL_FIXTURE_BUILD_LIMIT`,
    `SWIFTQL_FIXTURE_RUN_LIMIT`, or `SWIFTQL_FIXTURE_SIGKILL_RETRIES` to
    change these values.

### Fixed

- **A prefix `-`, `+`, or `~` on a plain number keeps its type on Swift 6.3**
  (issue #771). `Int` and `Double` conform to `XLExpression`, so SwiftQL's
  generic prefix operators over `any XLExpression` also matched such an operand.
  Swift 6.3 preferred them. In a file that imports SwiftQL, ordinary code such
  as `let x = -someInt` then gave `x` an expression type, and every later use of
  `x` as an `Int` failed to compile. `+someInt`, `~someInt`, and `+someDouble`
  failed the same way. Swift 5.9 and Swift 6.4 always chose the standard library
  operator. SwiftQL now declares exact-match overloads: `-`, `+`, and `~` for
  `Int`, and `+` for `Double`. The result is an `Int` or a `Double` on every
  compiler. `Double` gets a `+` overload only, because Swift 6.3 already chose
  the standard library operator for `-someDouble`, and a `-` overload for
  `Double` makes `-someDouble` ambiguous. The operators for SwiftQL expressions,
  optional expressions included, keep their behaviour. The generic operators
  date from the first source commit, so the fault applies to user code on every
  1.x version under Swift 6.3, not only to 1.9.

- **A parameter named like a key-path component or a callee gets a
  diagnostic** (issue #661). A parameter named `name` in a body that also
  contains `\Person.name` made the rewrite produce invalid code. A parameter
  named `From` rewrote the `From(…)` clause. The rewrite now leaves key-path
  components and callees unchanged, and the macro reports the shared name at
  the declaration.

- **A `@SQLTable` or `@SQLResult` property default now applies** (issue #665,
  recorded on #469). The generated memberwise initializer gives a `var`
  property with an initial value a default for its parameter, so a call can
  leave that property out. Before this change, the initializer ignored the
  initial value and required the argument. The default refers to a generated
  `@usableFromInline` static accessor that returns the initial value. Thus a
  `public` model whose initial value refers to a `private` member still
  compiles. The change is source compatible: every existing call passes every
  argument and so still compiles. The value is a Swift default only and does
  not add a SQL `DEFAULT` clause. A `let` property with an initial value is
  still an error, because the initializer cannot assign it. The diagnostic
  now says that the value cannot be used as a default. The to-do demo gives
  `Todo.checklist` its default again.

- `XLJSONPath.key(_:)` quotes a key that begins with `"` or holds a control
  character (issue #671). SQLite rejected the unquoted form of a leading-quote
  key as a bad JSON path on every version. Such a key resolves on a SQLite
  that unescapes JSON labels, as the type documentation states.
- The documentation of `jsonArrayLength` states what SQLite returns: `0` for a
  value that is not an array, and `NULL` only for a path that selects nothing
  (issue #671).

### Documentation

- SwiftQL 1.x states that it supports GRDB 6 only (issue #667). The manifest
  range stays `from: "6.29.3"` (`6.29.3..<7.0.0`). `COMPATIBILITY.md` and the
  README Install section now say that an application on GRDB 7 cannot resolve
  SwiftQL 1.x. `Research/GRDB7Evaluation.md` records the build against GRDB
  7.11.1 and the break list: the `CSQLite` product rename, the SQLite C module
  that `import GRDB` no longer re-exports, and the `Sendable` closure and value
  requirements. The `Sendable` findings go to the v2.0 `Row` decision (issue
  #685).
- The blog post on build-time SQLite validation is back, rewritten for v1.9
  (issue #495). It sets up the validation plugin on a package that uses
  `@SQLQuery` and `@SQLQueries` declarations. The declared-query registry
  plugin finds the queries, and `makeManifest` generates the manifest from
  them. A hand-written manifest is now the fallback. The post states the
  current limits: the registry plugin runs only in a SwiftPM target (issue
  #766), and the validation plugin also runs in an Xcode app target (issue
  #666). `check-blog-output.sh` and the deployed-post check in
  `documentation.yml` list the post again.

## [1.8.1] - 2026-09-15

v1.8.1 is a correctness and safety patch for the 1.8 line. It removes process
traps, silently wrong results, and unbounded work, most often by replacing them
with a typed error. Some code that compiled and ran on 1.8.0 therefore needs a
change, and "Migration" lists every such case first.

### Migration

- **New cases on public error enums.** A `switch` over one of these enums with
  no `default` clause stops compiling until it handles the new cases or adds a
  `default` clause.
  - `XLSQLValueEncodingError` gains
    `contextualOnlyValueInLegacyWrite(valueType:)` (issue #651), and
    `nulCharacterInText(valueType:context:)` and
    `unsupportedCompoundBranchClause(compoundOperator:clause:)` (issue #657).
  - `SQLiteIndexAdvisorError` gains `forceRequiresApply`,
    `outputConflictsWithPlanReport`, and `outputNotGenerated(path:)`
    (issue #649).

- **Long `REGEXP` operands fail.** The bundled `regexp` function refuses a
  pattern string longer than 1,024 UTF-8 bytes, and a subject longer than
  16,384 UTF-8 bytes, with `XLRegexpLengthLimitError` (issue #645). It checks
  before it compiles or matches, and it never truncates either operand. The
  subject limit also applies to a pattern matched through `XLRegexPattern`. A
  statement that matched longer column text on 1.8.0 now throws when it reaches
  such a row. Search long text with full-text search, or match it in Swift.
  `XLRegexpLengthLimitError` is a new type, so no existing `switch` changes.

- **`QueryBuilder` folds `and` and `or` in call order** (issue #657). A query
  that mixes the two can render a different `WHERE` clause, and so match
  different rows. `and(a).or(b).and(c)` rendered `((a AND c) OR b)` and now
  renders `((a OR b) AND c)`. `or(a).and(b)` rendered `(b OR a)` and now renders
  `(a AND b)`, because the operator of the first term joins nothing and is not
  used. A query that uses only `and`, only `or`, or every `and` before every
  `or` renders as before. Check every mixed chain against the condition it is
  meant to express.

- **Some compound selects fail before SQLite prepares them** (issue #657). The
  right-hand branch of `union`, `unionAll`, `intersect`, or `except` must be a
  plain select. A branch with `WITH`, `ORDER BY`, `LIMIT`, or `OFFSET`, or a
  branch that is itself a compound, fails with
  `XLSQLValueEncodingError.unsupportedCompoundBranchClause` when the statement
  renders. On 1.8.0 SQLite applied the branch's `ORDER BY`, `LIMIT`, or
  `OFFSET` to the whole compound, a nested compound lost its grouping, and a
  `WITH` branch did not prepare, so a query that relied on the old placement
  ran and now throws. Move the clause after the last branch, and chain compound
  operators instead of nesting them. The common case is a recursive common
  table limited inside its closure: write
  `select(seed).unionAll { select(step).from(this) }.limit(10)`, not `limit(10)`
  inside the `unionAll` closure. Both spellings render the same SQL. The
  result-builder spelling, `Union()` followed by `Select`, is not affected.

- **Text that contains U+0000 is rejected** (issue #657). An inline text
  literal or a bound text value that contains U+0000 fails with
  `XLSQLValueEncodingError.nulCharacterInText`. On 1.8.0 SQLite read such a
  value only up to its first NUL, so a literal was cut short and a bound value
  was stored truncated. Store data that can contain U+0000 as a blob.

- **Automatic aliases and binding names in nested scopes change** (issue
  #644). A subquery or common table built from the enclosing schema no longer
  reuses an outer alias, common-table name, or automatic parameter name, so the
  SQL rendered for an unnamed nested source changes: an inner `WITH cte0` inside
  an outer `cte0` is now `cte1`, and the table in an
  `UPDATE ... FROM (SELECT ...)` body is now `t2` rather than `t0`. Explicitly
  named sources render as before. A test that pins the SQL of an unnamed nested
  source must move its pin.
  - An automatic binding in a body built from the enclosing schema
    (`commonTable`, `from`, `fromExpression`, and the scalar and recursive
    common tables) now gets its own name, for example `:p1`, where before it
    shared `:p0` with an outer binding. A caller that set only the outer
    reference must now set the inner reference too.
  - Two automatically named bindings from unrelated schemas that render the
    same placeholder fail with
    `XLInvocationBindingError.conflictingParameterKey`. On 1.8.0 they silently
    shared one value. This includes an outer automatic binding beside an inner
    one in a free `subquery { schema in ... }` or `in { schema in ... }`
    closure. Build such a subquery from the enclosing schema, with the new
    `XLSchema` subquery methods or `XLSchema(parent:)`.

- **Custom and bundled functions are installed once per connection** (issue
  #640).
  - Two `XLCustomFunction` types with the same name and argument count are one
    SQLite function. The first one installed on a connection serves every
    statement on that connection that calls either type. On 1.8.0 each
    execution installed the implementation its own statement referenced. Give
    functions that behave differently different names.
  - An application function still replaces a bundled function or a SQLite
    built-in with the same signature. If that replacement happens for the first
    time while a statement is active on the connection, for example inside an
    open `withResultSet(_:)` callback, the request now throws
    `XLDatabaseContractError.prepareFailure`. On 1.8.0 the process stopped.
  - SwiftQL records each install with a zero-argument marker function named
    `swiftql_installed_<kind>_<arity>_<hash>`, so these names appear in
    `PRAGMA function_list`.

- **Live-query streams deliver off the main queue** (issue #652). `stream()` and
  `streamOne()` on a GRDB-backed request deliver on a private serial queue, and
  their default retry backoff waits on the same queue. A refetch after a commit
  runs on a pool reader rather than inline on the writer, and GRDB coalesces a
  burst of commits. Code that treated stream values as if they arrived on the
  main thread must move to the main actor itself. Combine `publish()` and
  `publishOne()` still deliver on the main queue by default, and
  `XLQueryObserver` and `XLQueryRowObserver` still change their state on the
  main thread.

- **The build validator can fail a run that passed** (issue #647). A pinned
  snapshot that changes during index verification now fails the run with
  `snapshotChangedDuringVerification`, including a change while a candidate's
  verification throws and a change between two candidates. On 1.8.0 the run
  exited 0.

- **`swiftql-index-advisor --apply` refuses some writes** (issue #649). It
  refuses to replace an existing output file whose first line lacks the
  generated header, and it refuses an `--output` that is the same file as
  `--plan-report`. Pass `--force` once to replace a hand-written file, for
  example to adopt the advisor for an existing file. `swiftql-build-validate`
  also refuses an `--output` or `--plan-output` that is the same file as
  `--plan-suppressions`.

### Security

- The `REGEXP` length limits above (issue #645). A match runs inside a SQLite
  function callback, where SQLite does not check `sqlite3_interrupt`, so a
  statement cannot be cancelled during one match, and a pattern often comes
  from a search field. For a registered `XLRegexPattern`, one slow match also
  held the registration lock for every pooled connection. The limits bound the
  input size; they reduce catastrophic backtracking but do not remove it.

- `swiftql-index-advisor --apply` no longer destroys a file it did not generate
  (issue #649). Before, `--plan-report plans.json --apply --output plans.json`
  replaced the sidecar with SQL, and an `--output` that named a hand-maintained
  file replaced it with no warning. The alias check matches by path, by
  symbolic link (including a linked parent directory), and by hard link, and
  `--force` does not lift it.

### Fixed

- SwiftQL installs custom and bundled SQLite functions once per physical
  connection, not before every execution (issue #640). A `REGEXP` or
  custom-function request inside a `withResultSet` callback in a transaction no
  longer stops the process with SQLite error 5. Executions no longer expire the
  connection's prepared statements. The `regexp` pattern cache lasts for the
  life of the connection, so a statement compiles its pattern once rather than
  on every execution. Two `GRDBDatabase` values over one `DatabasePool` no
  longer fail with `no such function: regexp`.

- A request nested inside a `withResultSet` callback on a transaction scope,
  with the same SQL as the outer request, no longer resets the outer cursor
  (issue #641). The nested request prepares its own statement while the cached
  one is in use, so the outer result set returns its own rows in full.

- A declared query (`@SQLQuery` or `@SQLQueries`) called inside
  `withTransaction(_:)` no longer adds a permanent render-once cache entry for
  each transaction (issue #642). A transaction scope shares its database's
  entry, and the cached request is bound to the scope's connection when it is
  called.

- `fetchAtMost(_:bindings:)` on a `RETURNING` request runs in a transaction on
  the writer connection, as `fetchAll` and `fetchOne` do (issue #643). Before,
  it ran on a read-only pooled reader and failed, which broke the `.exactlyOne`
  fetch that `@SQLQuery` generates. SQLite applies every change of the
  statement during its first step, so reading fewer rows still applies the
  whole statement; the source comments that said otherwise are corrected.

- A subquery or common table built from the enclosing schema no longer shadows
  an outer alias or common-table name, or shares an automatic parameter with an
  outer binding (issue #644). See "Migration".

- A statement that matches an `XLRegexPattern` keeps the pattern registered for
  as long as the statement, or a request made from it, can execute (issue
  #646). Before, a pattern built as a local was released early, and execution
  failed with `unregisteredPattern`.

- A scratch copy that cannot be set up during index verification gives a
  readable, path-free unverified reason and a `plan.scratch-setup-failed`
  build warning (issue #647). Before, the reason named only the error type, and
  the build log showed nothing.

- Index verification registers the bundled SQLite functions, such as `regexp`,
  on its scratch connection (issue #648). A statement that uses `REGEXP` can now
  produce a verified index recommendation on a SQLite build without
  `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION`.

- A static row layout no longer stops the process at `select(_:)`,
  `with(...).select(_:)`, `insert(...).select(_:)`, `QueryBuilder(select:)`,
  `Returning(_:)`, or `returning(_:)` (issue #650). New overloads read the column
  aliases from the layout's metadata, and the dynamic `Select` and `Returning`
  initializers detect a layout at run time, so a generic caller that sees the
  layout only as `XLRowReadable` is covered too. `RETURNING` renders column
  aliases only, so each layout alias must name a column of the target table.

- A `@SQLTable` column whose type has no `XLLiteral` conformance, such as a
  `Date` read through a contextual codec, no longer stops the process when it
  is written through `Values(row)`, `sqlInsert(row)`, or
  `UpdateRequest.makeUpdate()` (issue #651). Preparation throws
  `XLSQLValueEncodingError.contextualOnlyValueInLegacyWrite(valueType:)`, and
  no row changes. Encode such a row through its static row layout.

- A live-query stream no longer refetches inline on the writer, and awaiting a
  stream or its default retry backoff no longer needs the main thread, so a
  thread that blocks while it waits, the main thread included, cannot deadlock
  (issue #652). `XLQueryObserver` and `XLQueryRowObserver` apply a value that
  arrives on the main thread at once, and keep the delivery order across
  threads.

- A compound select no longer applies a branch's `ORDER BY`, `LIMIT`, or
  `OFFSET` to the whole compound, and a text value with U+0000 is no longer
  truncated (issue #657). Both now fail with a typed error; see "Migration".

### Added

- `XLSchema(parent:)`, and `XLSchema` subquery methods that take their alias
  from the enclosing schema: `subquery(alias:_:)`, `nullableSubquery(alias:_:)`,
  the scalar `subquery(_:)` forms, `subqueryExpression(alias:statement:)`,
  `nullableSubqueryExpression(alias:statement:)`, and the scalar
  `subqueryExpression(statement:)` forms (issue #644).

- `XLStaticRowReadable` overloads of `select(_:)`,
  `XLWithStatement.select(_:)`, `XLInsertTableStatement.select(_:)`,
  `QueryBuilder.init(select:)`, `Returning.init(_:)`, and `returning(_:)` on
  insert, update, and delete statements (issue #650).

- `warnings` on `SQLiteBuildValidationRunResult` and
  `SQLiteBuildValidationValidatorCLIRunResult`,
  `SQLiteBuildValidationValidatorCLIRunResult.warningSummary(origin:)`, and a
  defaulted `reportScratchFailure` parameter on
  `SQLiteBuildValidationIndexCandidateVerifier.verify` (issue #647).
  `swiftql-build-validate` prints the warnings after its advisory summary; they
  never change the exit code.

- The `--force` option of `swiftql-index-advisor`, with
  `SQLiteIndexAdvisorOptions.forces` and a defaulted `forces:` initializer
  parameter (issue #649).

- "Query plan advice", a DocC article for plan analysis, suppressions, verified
  index recommendations, and `swiftql-index-advisor`, linked from the catalog
  landing page and the README (issue #654).

### Changed

- Corrected the documents that said SwiftQL does not support right joins, full
  outer joins, or SQLite's JSON functions (issue #653). `Queries.md` has a table
  of each join kind and its SQLite minimum, and `PortingFromSQL.md` maps
  `USING`, `NATURAL`, right, and full outer joins and the `sql { }` subquery
  form. The to-do demo check fails when the demo README's test count disagrees
  with the suite.

- The build validator has a negative control that fails if query validation
  prepares statements under `EXPLAIN` or `EXPLAIN QUERY PLAN`, where Apple's
  `SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION` would hide unknown-function errors
  (issue #656).

- CI runs the source-coverage target-membership check on pull requests, so a
  new target outside `scripts/ci/source-coverage-config.json` fails before the
  merge (issue #655).

- CI and `make-docs.sh` install the Hugo release pinned in
  `scripts/ci/hugo-version.sh`, checked by SHA-256, instead of the Homebrew
  formula, whose version drift broke every documentation build (issue #611).

- Recorded the v1.8.1 behavior in the #190 canonical SQLite conformance
  inventory: the `REGEXP` length limits, the compound-branch rule, the
  recursive `limit` placement, NUL rejection in text, nested-scope aliases and
  automatic bindings, static row layouts in `RETURNING`, and `fetchAtMost` on
  `RETURNING`. The inventory version is now 1.8.1. It records 117 public-surface feature records: 113
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  1 unimplemented. Of the 207 evidence records, 126 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.

### Correction to the 1.8.0 entry

- The 1.8.0 entry says that index verification fails closed when the pinned
  snapshot's byte count or SHA-256 changes. That was not true in 1.8.0 (issue
  #647). The verifier caught `snapshotChangedDuringVerification` for each
  candidate and recorded it as an unverified reason, so the run still exited 0.
  It is true from 1.8.1. A dated correction note now follows that statement in
  the 1.8.0 entry, whose text is otherwise unchanged.

### Known limitations

- A custom `XLRowReadable` projection that is not a static row layout, and
  whose own `readRow` throws against the definition reader, still stops the
  process in `Select.init(_:)` and `Returning.init(_:)`. Reporting it as a typed
  error needs those initializers to throw, which is a source-breaking change,
  so it is deferred to v2.0 as
  [#744](https://github.com/lukevanin/swiftql/issues/744). Every static row
  layout avoids the trap at every entry point (issue #650).
- The `REGEXP` length limits reduce catastrophic backtracking but do not remove
  it: an exponential pattern needs only a few dozen characters. Validate a
  pattern that comes from untrusted input.
- The free functions `subquery`, `nullableSubquery`, and `subqueryExpression`,
  and the schema that `in { schema in ... }` and `notIn { schema in ... }` pass
  to their closure, cannot see the enclosing schema and start an independent
  scope. Give a subquery there an explicit alias when it is joined to another
  source.
- `@SQLTable` does not diagnose a contextual-only column at its declaration,
  because a read-only table with such a column is valid. The write fails when
  it is prepared (issue #651).
- A request nested inside a `withResultSet` callback must use the transaction
  scope that opened the result set. A nested request on the root database
  can stop the process in GRDB (issue #641).

## [1.8.0] - 2026-09-08

### Added

- The standalone build validator can capture a normalised `EXPLAIN QUERY PLAN`
  record for every manifest entry (issue #394). A run opts in with
  `--plan-output <path>`; without it the validator captures nothing and does no
  extra work. Capture runs on the same read-only, query-only connection that
  produced the run's correctness evidence, after that evidence is complete, and
  writes a second canonical JSON file. Plans never enter the correctness
  report, whose schema, verdict semantics, and bytes are unchanged either way.

  Each `SQLiteBuildValidationPlanRecord` carries the entry's identity, the
  SQLite build that planned it — version, source ID, and the compile options
  that can change a plan — and exactly one of two outcomes: a normalised plan
  tree, or an explicit unsupported reason. There is no third state and no
  absent entry. The tree is built from each row's own `parent` id, and SQLite's
  `id` and `parent` numbers are then discarded, because the research measured
  them as the one field that differs between two SQLite builds planning the
  same statement. Every node keeps its raw detail text beside its
  classification, and text the classifier does not recognise stays
  `unclassified` rather than being coerced into a neighbouring shape.

  Statement parameters are left unbound. On a snapshot without `ANALYZE`
  statistics, which the pinned snapshot deliberately is, SQLite's plan choice
  never reads the bound value. The sidecar names that caveat, and the
  `ENABLE_STAT4` compile option, in every report.

- Advisory diagnostics for the plan shapes that indicate avoidable work (issue
  #395): a full table scan above a stated row threshold, a temporary B-tree for
  `ORDER BY`, a temporary B-tree for `GROUP BY`, and a correlated scalar
  subquery. Each finding names the query, its descriptor identity, the plan
  node that produced it, and — for the scan rule — the real table and its row
  count. A finding is keyed on the classified shape, never on raw
  `EXPLAIN QUERY PLAN` wording, and the diagnostic type refuses to be
  constructed with an unclassified shape.

  `SQLiteBuildValidationPlanDiagnosticSeverity.advisory` is its own type rather
  than a fourth `SQLiteBuildValidationVerdict` case. A verdict decides the exit
  status, and no arrangement of the advisory type can reach that decision.

  Suppression is a checked-in file, passed with `--plan-suppressions <path>`.
  Every rule names a diagnostic code and at least one of a query or a table,
  and must state a reason, so a rule that silences everything is not
  expressible and neither is a silent one. A silenced finding stays in the
  sidecar with that reason, and a rule that silenced nothing is reported, so a
  stale instruction to ignore a finding can be found and deleted.
  `--plan-scan-row-threshold <rows>` moves the scan rule's threshold, which
  defaults to 500.

- Deterministic index candidates derived from the statements behind remediable
  plan shapes (issue #396). Columns follow the rule the research settled with a
  real re-plan: equality-constrained columns lead, and a join key is an
  equality constraint too, so it shares that tier; then at most one range
  column, because SQLite stops narrowing at the first range term; then the
  `ORDER BY` terms, with their direction and collation.

  An `ORDER BY` term the extractor cannot read as a plain qualified column ends
  that tier rather than being skipped, because skipping it would claim an
  ordering the index does not provide. Candidates merge across statements, so a
  shared index is visibly shared, and a candidate whose columns are an exact
  prefix of a wider one on the same table folds into it with its attribution
  intact. Three stated bounds — six columns, four candidates per statement,
  four per table — are reported when hit rather than applied silently, and a
  remediable node the generator cannot read confidently is recorded as a
  decline with its reason.

- Verification of index candidates against a disposable copy of the snapshot
  (issue #397), opted into with `--verify-index-candidates`. Each candidate is
  created on its own scratch copy, the motivating statement is re-planned with
  the same classifier, and the recommendation carries the before-plan, the DDL,
  the after-plan, and a note of the write cost the index implies.

  The copy lives in the system temporary directory; a scratch parent beside the
  snapshot, or inside the working directory, is refused. It is removed on a
  normal return, on a thrown error, and on `SIGINT` or `SIGTERM` through a
  handler that unlinks a preallocated path table and then restores whichever
  disposition was in place before. The pinned snapshot's byte count and SHA-256
  must match what they were before the pass, or it fails closed.

  > **Correction (15 September 2026, v1.8.1, issue #647).** The last
  > sentence did not hold in 1.8.0. The verifier caught
  > `snapshotChangedDuringVerification` for each candidate and recorded it as
  > an unverified reason, so the run still exited 0. From 1.8.1 a snapshot
  > that changes during verification fails the run.

  The improvement rule is recorded by version. A candidate is kept only when
  the index SQLite names in the after-plan is that candidate's own, and either
  the alias's node moves from a full table scan or an automatic covering index
  to a narrowed index search, or a temporary B-tree the before-plan had is gone
  from the after-plan. A candidate the rule declined is reported with its
  reason, and one that could not be verified is reported unverified rather than
  recommended.

- The SwiftPM build-tool plugin can surface all of this as build warnings
  (issue #398). A target opts in by placing `swiftql-plan-analysis.json` in its
  own directory, beside the manifest and snapshot the plugin already reads. The
  plugin then adds the three plan-analysis arguments to the same build command
  and declares the plan sidecar as a second output; the opt-in file is declared
  as an input, so editing it invalidates the command. A target that does not
  opt in sees an unchanged invocation and pays nothing.

  Findings reach the build log and Xcode's issue navigator because the
  validator prints them in the `<path>: warning: <message>` form every Swift
  build system already parses, attributed to the manifest. There are two kinds
  of line: a diagnostic says what SQLite is doing that costs avoidable work,
  and a `plan.verified-index` recommendation says what to do about it and
  carries the `CREATE INDEX` statement to paste.

- `swiftql-index-advisor`, a command that turns verified recommendations into a
  checked-in artifact (issue #399), with `SwiftQLSQLiteIndexAdvisor` as its
  library. Report mode is the default: it prints every recommendation with its
  evidence and every rejected candidate with its reason, and changes nothing.
  `--apply` writes the statements as generated SQL and additionally requires
  `--output`, so the command can only ever write to a path the invocation
  names. The artifact's bytes are a pure function of the recommendations, and
  apply compares bytes before writing, so a second run on unchanged advice does
  not touch the file.

  A build never invokes it. A build-tool plugin emits diagnostics rather than
  fixits, and a macro cannot open a database without breaking hermetic,
  incremental builds, so applying the advice is one explicit invocation whose
  diff a developer approves.

### Changed

- The to-do demo carries nine indices, every one of them proposed and verified
  by the new advisor (issue #484). The demo had none before, because SwiftQL's
  generated `CREATE TABLE` declares no primary key: every lookup by identifier
  was a full table scan and every `ORDER BY` built a temporary B-tree. Every
  table access in the demo is now an index search. Three advisory warnings
  remain, each recorded with its reason in the demo's checked-in suppression
  file; all three are sorts no index can supply.

## [1.7.0] - 2026-09-07

### Added

- SwiftQL now ships the `regexp` implementation the `REGEXP` operator needs
  (issue #612). SQLite parses `X REGEXP Y` as a call to `regexp(Y, X)` and
  ships no such function, so before this release every query that used the
  operator failed with `no such function: regexp` unless the application
  registered a two-argument `regexp` itself. `XLExpression.regexp(_:)` now
  records SwiftQL's own implementation while the statement renders, and the
  driver registers it on whichever pooled connection executes the statement.
  The rendered SQL is unchanged.

  `XLRegexpFunction` is backed by Swift `Regex`, so the pattern syntax is
  Swift's. A pattern matches anywhere in the subject rather than having to
  match all of it, which is what the widely used `regexp` extensions for
  SQLite and PostgreSQL's `~` operator do; anchor a pattern with `^` and `$`
  to require a whole-subject match. A NULL on either side yields NULL. An
  invalid pattern raises `XLRegexpFunctionError.invalidPattern`, rather than
  returning false and reading like a pattern that matched nothing. An argument
  that is neither TEXT nor a UTF-8 BLOB raises `XLColumnReadError` instead of
  being converted silently.

- A `REGEXP` pattern is compiled once per statement execution rather than once
  per row (issue #613). SQLite calls a scalar function once for every candidate
  row and passes the pattern again on each call, so the compile dominated the
  cost of a scan. Each registration of the bundled function keeps a bounded
  cache of compiled patterns, holding at most 16 and caching a compile failure
  with the same rules as a success. A measured 2000-row scan against one pattern
  compiles once instead of 2000 times, about 46x less wall-clock time in the
  recorded run. A cache belongs to one registration and is never shared between
  connections, because Swift's `Regex` is not `Sendable`.

### Changed

- An application that registers its own two-argument `regexp` keeps it (issue
  #612). SwiftQL never replaces a `regexp` already on the connection, whether
  it was registered with `GRDBDatabaseBuilder.addFunction(_:)` or with
  `Configuration.prepareDatabase(_:)`, so upgrading does not change what
  `REGEXP` means for an application that already supplied one. Deciding that
  costs one `PRAGMA function_list` per database, not one per query.

- `XLRegexPattern`, a Swift `Regex` usable as the right operand of `REGEXP`
  (issue #614). A pattern written with `RegexBuilder` gets a compile-time check,
  composition, and named pieces, none of which a pattern string has. A compiled
  `Regex` cannot travel through SQLite, so the statement carries an opaque key
  and SwiftQL's `regexp` resolves it:

  ```swift
  let leadingA = XLRegexPattern {
      Anchor.startOfSubject
      "A"
      ZeroOrMore(.any)
  }

  Where(person.name.regexp(leadingA))
  ```

  A key carries a marker no regular expression contains, so a plain pattern is
  never mistaken for one; a key naming no registration raises
  `XLRegexpFunctionError.unregisteredPattern` rather than silently matching
  nothing. The registry does not keep a pattern alive: hold the
  `XLRegexPattern` for as long as statements using it can execute. A key names
  a registration in one process, so `XLStaticStatementDefinition` refuses a
  statement that carries one -- a descriptor's identity has to be reproducible.
  Captures are not exposed, because `REGEXP` answers only whether a subject
  matches.

- A statement that uses `REGEXP` with a string pattern now runs as a static
  query descriptor, and passes the SQLite build validator, without any
  registration by the caller (issue #615). One matching an `XLRegexPattern`
  does not: its key names a registration in one process, so
  `XLStaticStatementDefinition` refuses it. A descriptor cannot carry a registration closure, so
  `XLStaticStatementDefinition` records the *signatures* of the functions
  SwiftQL bundles, and the adapter rebuilds its own implementation from one
  when the statement is prepared. The build validator registers the same
  implementations on its snapshot connection, so a query the application can
  run no longer fails the build.

  An application's own custom function is unchanged: SwiftQL cannot rebuild an
  implementation it did not write, so such a statement still needs an upfront
  `GRDBDatabaseBuilder.addFunction(_:)` call to run as a static descriptor, and
  a `function:` capability naming it is still proven from the validator
  connection rather than from a declaration.

- Recorded the bundled `REGEXP` surface in the #190 canonical SQLite
  conformance inventory, and dropped the schema requirement the operator used
  to carry (issue #616). The inventory version is now 1.7.0. It records 117 public-surface feature records: 113
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  1 unimplemented. Of the 197 evidence records, 121 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.

- `XLCustomFunctionDefinition`, `XLRegexpFunctionError`, and the pattern matcher
  behind `REGEXP` moved from `SwiftQL` to `SwiftQLCore` (issue #615). Nothing is
  renamed and `SwiftQL` re-exports `SwiftQLCore`, so `import SwiftQL` is
  unaffected. The move is what lets the build validator, which does not depend
  on the GRDB adapter, register the same implementation the adapter registers.

## [1.6.0] - 2026-09-03

### Added

- `XLJSONPath`, a typed SQLite JSON path built from segments rather than
  written as a string literal (issue #588). `XLJSONPath.root` is the document
  root, `key(_:)` adds an object member, `index(_:)` adds an array element
  counted from the start, and `last` and `index(fromEnd:)` count back from the
  end. A key is quoted only where SQLite's path grammar needs it -- when the
  key is empty, or holds a `.` or a `[` -- so a key that holds either names
  that key instead of changing the shape of the path. A key holding a `"`, a
  `\`, or a control character resolves only on a SQLite that unescapes JSON
  labels: JSON stores such a key escaped, older engines match a path label
  against that raw escaped text, and newer engines unescape both sides first,
  so no single spelling suits both. SwiftQL renders for the newer behaviour,
  which is what SQLite documents. A path renders through the same text
  formatter as any other text operand, so it cannot carry raw SQL. SQLite has
  no negative array index, so `index(_:)` stops with a diagnostic message when
  it is given one, and names `last` and `index(fromEnd:)` as the remedy.
  `appended` names the position one past the last element, rendered `[#]`,
  which is SQLite's idiom for appending to an array.

- `jsonArrayLength(path:)` gains an `XLJSONPath` overload (issue #588). The
  existing `String` overload is unchanged.

- SQLite's two JSON selection operators, added in SQLite 3.38.0 (issue #589).
  `jsonElement(at:)` renders `->` and returns the selected element as JSON
  text, so a selected string keeps its quotes and a JSON `null` reads back as
  the four characters `null`. `jsonValue(at:as:)` renders `->>` and returns
  the element as a SQL value of the requested type, so a selected string loses
  its quotes and a JSON `null` reads back as SQL `NULL`. Both results are
  optional, because a path that matches nothing yields SQL `NULL`. Both are
  methods rather than Swift operators: the compiler reserves `->` and refuses
  to declare it. SQLite's bare-name form on the right of the operator is not
  exposed, because `XLJSONPath.key(_:)` already names any single key and also
  composes.

- The SQLite JSON constructor and inspection functions (issue #590).
  `jsonArray(_:)` and `jsonObject(_:)` build a JSON array and object.
  `jsonObject` takes its members as name/value pairs, so an incomplete member
  cannot be written and SQLite's "requires an even number of arguments" error
  cannot be reached from Swift. On an expression: `minifiedJSON()` renders
  `json(X)`, `prettyJSON()` renders `json_pretty(X)`, `jsonQuoted()` renders
  `json_quote(X)`, `jsonType()` and `jsonType(at:)` render `json_type`, and
  `jsonErrorPosition()` renders `json_error_position(X)`.

  Three of these need a SQLite newer than 3.9.0, and SwiftQL renders the SQL
  either way -- it is the engine that refuses. `json_error_position` needs
  **3.42.0**, `json_valid(X, F)` with flags needs **3.45.0**, and
  `json_pretty` needs **3.46.0**. The macOS cells in this repository's
  supported matrix run SQLite 3.43.2, so the last two are covered by tests
  that ask the connection what it defines and skip with a message naming the
  runtime, rather than by combinatorial cases, where a missing capability is
  a failure rather than a skip.

- `XLJSONValidationFlags`, a typed option set for the second argument of
  `json_valid` (issue #590), with one member per SQLite flag bit: `json`,
  `json5`, `jsonbShallow`, and `jsonbStrict`. An empty set renders as `json`,
  which is what SQLite uses when the argument is left out, because SQLite
  rejects a zero mask.

- `json_extract` and the five JSON mutation functions (issue #591).
  `jsonExtract(at:as:)` reads one path as a SQL value in the type the caller
  states. `jsonExtract(at:_:_:)` reads two or more paths and returns the JSON
  array SQLite builds from them; it requires two paths by its signature, so
  the two result types cannot be confused at the call site.

- `jsonInserting(_:_:)`, `jsonReplacing(_:_:)`, `jsonSetting(_:_:)`,
  `jsonRemoving(at:_:)`, and `jsonPatched(with:)` write values back into a
  document (issue #591). Each takes its path/value pairs as pairs, and each
  requires at least one, so an incomplete or empty argument list cannot be
  written. Every result is optional, because a `NULL` document gives `NULL`.

- SQLite's two JSON aggregates (issue #592). `jsonGroupArray(distinct:)`
  renders `json_group_array(X)` and collects every input row into a JSON
  array. `jsonGroupObject(name:value:)` renders `json_group_object(N, V)` and
  collects name/value pairs into a JSON object. Neither result is optional:
  an empty group gives `[]` and `{}`, not SQL `NULL`. `jsonGroupObject` has no
  `distinct` parameter, because SQLite allows `DISTINCT` only on an aggregate
  with exactly one argument.

- The JSONB function variants, which need SQLite 3.45.0 or later (issue #593).
  Eleven SQLite functions return the binary JSON representation instead of
  JSON text, reached through twelve Swift entry points because
  `jsonbExtract` has a single-path and a multiple-path form: `minifiedJSONB()`, `jsonbArray(_:)`, `jsonbObject(_:)`,
  `jsonbExtract(at:as:)` and `jsonbExtract(at:_:_:)`, `jsonbInserting(_:_:)`,
  `jsonbReplacing(_:_:)`, `jsonbSetting(_:_:)`, `jsonbRemoving(at:_:)`,
  `jsonbPatched(with:)`, `jsonbGroupArray(distinct:)`, and
  `jsonbGroupObject(name:value:)`. The functions whose result is a SQL value
  rather than JSON have no JSONB twin, because SQLite defines none: they read
  a JSONB input directly and keep their own result types.

- A JSON documentation page, `JSON.md`, covering the whole v1.6 surface: the
  path builder, the two operators, extraction, mutation, the constructors, the
  aggregates, when JSONB is worth using, and the SQLite version each group
  needs (issue #594). Every snippet on the page is built and executed by
  `XLDocumentationTests.testDocumentationJSON`. `BuiltinFunctions.md` links to
  it rather than repeating the list.

- Conformance inventory records for the whole JSON surface (issue #594). The
  `syntax.expression.json-functions` entry no longer names only
  `JSON_ARRAY_LENGTH` and `JSON_VALID`; it covers the constructors,
  inspection, extraction, mutation, and aggregates. Two new entries join it:
  `syntax.expression.json-path` for the typed path builder and
  `syntax.expression.json-operators` for `->` and `->>`, which record their
  own SQLite 3.38.0 minimum. `syntax.expression.jsonb-functions` records the
  JSONB surface and its 3.45.0 minimum. Thirteen evidence records cite the new
  test suites, and `Conformance/SQLite/REPORT.md` is regenerated.

- The to-do demo adopts the JSON surface (issue #479). A to-do's sub-tasks
  live in a `checklist` JSON column: adding, ticking, and deleting one are
  each a single `UPDATE` through `json_insert`, `json_set`, and
  `json_remove`, and the list rows show a count from `json_array_length` and
  a first title from `->>`, so no checklist array crosses the boundary to
  draw a row. `Examples/TodoApp/README.md` and the `TodoDemo` page explain
  why a JSON column is the honest choice for that one field.

- `sql { ... }` works as a subquery on Swift 6.1 and later, inferring a table
  row, a nullable table row, or a scalar value from the context expecting its
  result (issue #69). The six overloads are behind `#if compiler(>=6.1)`,
  because they crash the Swift 5.9 and 6.0 compilers when compiled with the
  rest of the package -- the reason this work was reverted once already, in
  pull request #408. On those toolchains nothing changes:
  `subqueryExpression { ... }` remains the spelling, and it is what the gated
  overloads forward to. Recorded in COMPATIBILITY.md beside `#row`'s
  multi-column shapes, which are gated for the same class of compiler bug.

### Changed

- Decoding a full result set is 39.4% faster (issue #353). `XLRowReader` gains
  a second `staticColumn(_:alias:)` requirement, constrained to a value type
  that conforms to `XLLiteral`. Generated row readers name one concrete Swift
  type per column, so the compiler selects the constrained requirement for
  every literal column, and the unconstrained requirement only for a
  contextual one. The unconstrained requirement has to find the literal
  conformance at run time and reopen the expression as a parameterised
  existential; a profile attributed about 54% of main-thread samples to that
  work, which ran 226,002 times for one 16,143-row, 14-column fetch. The
  constrained requirement receives the conformance statically and reads the
  value directly. Measured over six interleaved pairs on one machine: median
  72.38 ms to 43.88 ms, p95 74.67 ms to 45.32 ms, with every pair between
  -38.4% and -40.0%. See `Benchmarks/Comparison/Issue353/README.md`.

  No source change is needed to get this. Nothing in the macros changes, so
  every existing `@SQLTable` and `@SQLResult` reaches the faster path as it
  is. The new requirement has a default implementation that forwards to
  `column(_:alias:)`, so an `XLRowReader` conformance outside this package
  keeps compiling.

  One conformance is affected. A row reader that overrides the unconstrained
  `staticColumn(_:alias:)` to give literal columns behaviour that
  `column(_:alias:)` does not give will no longer see literal columns arrive
  there, because those columns now select the constrained requirement.
  Implement the constrained requirement as well to keep that behaviour. A
  reader that implements only `column(_:alias:)`, which is the documented
  shape, is unaffected.

- Decoding a full result set is a further 28.3% faster (issue #353). The row
  closure that `@SQLTable` and `@SQLResult` generate runs once per row, and it
  built each column's expression inside itself. For a 16,143-row, 14-column
  fetch that built 226,002 `XLColumnResult` values instead of 14. Each was
  built as its concrete type, so passing it to a read that takes
  `any XLExpression` boxed it again, and the value is larger than the
  existential's inline buffer, so each box was a heap allocation. The
  generated factory now binds every column expression once, before it builds
  its metadata value, and declares the binding as the erased type the read
  already takes. Measured over six interleaved pairs on one machine, against
  the constrained-requirement fix alone: median 42.74 ms to 30.63 ms, p95
  44.08 ms to 31.32 ms, with every pair between -26.9% and -30.1%. See
  `Benchmarks/Comparison/Issue353/README.md`.

  No source change is needed to get this, and the generated API does not
  change. The binding keeps the column's concrete type, so a literal column
  still selects the constrained `staticColumn(_:alias:)` requirement.
  `makeSQLTable` and `makeSQLNamedResult` now return explicitly, because a
  body that binds locals is no longer a single expression.

### Fixed

- The `Benchmarks/Comparison` harness can build its SwiftQL graph again (issue
  #353). The graph's pinned `Package.resolved` was captured before SwiftQL
  took its OpenCombine dependency, so SwiftPM added an OpenCombine pin during
  every build and the harness stopped, as it should, rather than measure
  dependency versions other than the pinned ones. The missing pin is now
  recorded at the version and revision SwiftPM resolves. No other pin changes.

### Deprecated

- `validJSON()`, in favour of `validJSONOrNull()` and
  `validJSONOrNull(flags:)` (issue #590). `json_valid(NULL)` returns SQL
  `NULL`, not false, so a non-optional `Bool` result cannot represent what
  SQLite returns. `validJSON()` still compiles and renders the same SQL; it
  will return an optional expression in SwiftQL 2.

## [1.5.7] - 2026-08-27

### Removed

- Four public types that nothing referenced, in SwiftQL or anywhere in this
  repository (issue #555): `XLDatabaseMetadata` and its only conformer
  `XLDatabaseMetadataObject`, `XLTableName`, and `XLUnionDependency`. Each was
  declared and never used -- no call site, no conformance, no mention outside
  its own declaration.

- Six unreferenced members of `SQLiteBuildValidationRuntimeMetadata` (issue
  #555). Five computed capability sets --  `compileOptionCapabilities`,
  `functionCapabilities`, `collationCapabilities`, `moduleCapabilities`, and
  `extensionCapabilities` -- which nothing read; the `has…(named:)` predicates
  beside them are how capabilities are actually resolved. And
  `hasFunction(named:argumentCount:)` loses its `argumentCount` parameter: no
  caller ever passed one, and arity was the wrong question to ask anyway, since
  SQLite reports `-1` for a variadic function.

### Changed

- `Select(_ meta:)` now traps with a diagnostic message when a dynamic
  projection cannot enumerate its columns against the definition reader, in
  place of the bare `try!` it used before (pull request #584). The message
  names the projection type, the underlying error, and the
  `XLStaticRowReadable` overload that skips the replay, which is the remedy
  when a static row layout was erased to `any XLRowReadable`. The same input
  trapped before this change, so no working code is affected; only the
  diagnostic is.

### Fixed

- A NaN `Double` bound through a `@SQLQuery` macro parameter is now rejected
  where the value is captured, rather than further down at the driver boundary
  (issue #554). SwiftQL's documented policy is that binding a NaN throws
  `XLSQLValueEncodingError.realBindingWouldBecomeNull` instead of letting SQLite silently store SQL `NULL` in its place, and
  `_xlQueryParameterBinding` -- the capture behind every macro parameter --
  was the one capture path missing that check. **Nothing was ever stored as
  `NULL` through it**: `GRDBDatabaseDriver` rejects a NaN `REAL` before the
  value reaches SQLite, so executing such a query already threw. It now throws
  from the capture, with the same error the driver produced, so every capture
  path agrees. A caller who invokes `_xlQueryParameterBinding` directly and
  inspects its result, rather than executing, sees the throw where they
  previously saw `.real(nan)`. Infinities are unaffected: they survive
  SQLite's binding round trip and remain valid bound values.

- A `RETURNING` request now registers custom functions that opt into implicit
  registration, so a data-changing statement whose clauses call one executes
  instead of failing with SQLite's "no such function" error (issue #553).
  `GRDBDatabase.makeRequest(with: any XLReturningStatement<Row>)` built its
  request without passing the rendered encoding's registrations, so the
  registration table reaching the connection was empty -- a predicate that
  worked in a plain `SELECT` failed once the same statement was written as
  `UPDATE ... RETURNING` or `DELETE ... RETURNING`. Functions registered
  upfront with `GRDBDatabaseBuilder.addFunction(_:)` were never affected.
  Static query descriptors still register nothing, which is deliberate and now
  documented: a descriptor keeps only deterministic SQL and parameter
  metadata, and a registration is a live closure that cannot survive into it.

## [1.5.6] - 2026-08-04

### Added

- `@SQLTable` and `@SQLResult` now declare a `Sendable` conformance for the
  models they expand, so a value built entirely from column values can be
  shared across isolation domains without the conformance being written out at
  every declaration (issue #531). Swift already infers `Sendable` for a struct
  whose stored properties are all `Sendable`, but withholds that inference from
  a type other modules can see, which is why a `public` model used to warn
  under complete strict-concurrency checking and left callers reaching for
  `nonisolated(unsafe)` to silence it. The macros fill in exactly that gap:
  a `public` or `package` model gets the conformance, and a model that is
  `internal` or narrower keeps the compiler's own inferred one and gets nothing
  generated. This is a public API addition. A model that already states
  `Sendable`, or `@unchecked Sendable`, keeps its own declaration and gets no
  second one, so existing declarations such as the `TodoKit` schema still
  compile unchanged. The generated conformance is checked rather than asserted,
  so a `public` model holding a non-`Sendable` stored property is now diagnosed
  on the generated extension where it previously compiled silently; declaring
  `@unchecked Sendable` on such a model takes responsibility for it and turns
  the generation off. Generic models are left alone, because the conditional
  conformance they need cannot be written by an extension macro without the
  compiler reporting `circular reference expanding extension macros`;
  `SQLScalarResult` and `SQLRow2`...`SQLRow6`, the shapes behind `#row`, are
  the affected types and they were not `Sendable` before this either. The
  conformance requires Swift 6.0 or later, since Swift 5.9 treats a
  macro-expanded extension as a separate source file for the rule that a
  `Sendable` conformance must be declared alongside its type and warns on every
  model; the 5.9 support point keeps the behaviour it had. See COMPATIBILITY.md.
- Added a `SwiftQLExamples` library product (issue #480), holding the
  pre-expanded schema and declared queries the Getting Started playground
  imports. A classic Xcode playground has no `Package.swift` of its own and
  cannot reliably load a Swift macro compiler plugin, so the example schema is
  built during the ordinary package build and the playground calls
  already-expanded API. It is example code rather than a supported API, and
  nothing in `SwiftQL` or `SwiftQLCore` depends on it.

### Changed

- `SQLiteBuildValidator` now reports the schema checks it could not run, and
  stops preparing queries once the snapshot's schema identity is already known
  not to match the manifest (issue #440). When
  `SQLiteBuildValidationRuntime.capture` fails, the row-count and fingerprint
  checks used to vanish from the report; they now appear as `.unsupported`
  `schema.row-count` and `schema.fingerprint` diagnostics, so a reader can tell
  a check that could not run apart from one that was never in the report. When
  a schema identity mismatch is already recorded, every manifest entry gets one
  deterministic `schema.mismatch-skipped` outcome instead of a preparation
  whose result is already meaningless. `overallVerdict` resolution, the
  manifest format, the CLI surface, and every existing pass/fail outcome are
  unchanged, and canonical reports remain byte-identical across repeated runs.

### Fixed

- Nullable columns can now be assigned in a `Setting` closure the way any
  Swift optional is: `row.occupationId = "occ-1"` sets the column,
  `row.occupationId = nil` sets it to SQL `NULL`, and an optional-typed
  expression — a `XLNamedBindingReference<String?>` whose bound value may be
  `NULL` at runtime, or another nullable column — assigns with the same
  spelling. Previously the generated setter's type was
  `Optional<any XLExpression<T?>>`, where the outer `Optional` meant "leave
  this column out of the `SET` clause"; that collided with the column's own
  optionality, and no assignment of a plain value or of `nil` compiled at
  all. Generated `MetaUpdate` types now route column assignment through
  key-path member lookup over typed per-column slots (`XLColumnUpdate` /
  `XLNullableColumnUpdate`), so participation in the `SET` clause is tracked
  separately from the value's own optionality and one column name resolves
  against every assignment shape. A column the closure never assigns still
  stays out of the statement, non-optional columns behave as before, and
  `MetaUpdate`'s memberwise initializer keeps its v1 shape, where a `nil`
  argument still means "omit this column".

- Fixed `SwiftQLSQLiteBuildValidationPlugin` failing every Xcode build of a
  plugin-adopting target (issue #492). `context.tool(named:)` resolves a
  build-tool plugin's tool to `$BUILD_DIR/$CONFIGURATION/<target name>`, while
  Xcode's build system names a package executable after its *product*. The
  validator's target (`SwiftQLSQLiteBuildValidationValidatorCLI`) and product
  (`swiftql-build-validate`) had different names, so Xcode built the
  validator's library dependencies, left the executable out of the adopting
  target's dependency graph, and failed with `Build input file cannot be found`
  before validation ran — on a valid manifest as much as an invalid one.
  `swift build` resolved the same graph correctly, which is why only Xcode was
  affected. The executable target is now named `swiftql-build-validate`,
  matching its product; its source directory is unchanged. Both build systems
  now agree: a valid manifest builds, and an invalid one fails with the
  validator's own diagnostic.
  `IntegrationTests/BuildValidationPluginFixture/verify-xcode.sh` drives that
  agreement through `xcodebuild` so the two names cannot drift apart again. No
  public API changed, and the `swiftql-build-validate` product and its CLI
  contract are unchanged.

## [1.5.5] - 2026-07-30

### Added

- Added canonical async live-query streams, `stream()`/`stream(bindings:)` and
  `streamOne()`/`streamOne(bindings:)`, to `XLRequest` (issue #308): a
  `for try await` loop is now the single source of truth for SwiftQL
  live-query observation — immutable-packet capture, retry, decoding, and
  buffering all live in one GRDB-native `AsyncThrowingStream` source
  (`GRDBLiveQueryAsyncBridge`, built directly on `ValueObservation.start`),
  rather than being duplicated per adapter.
- Defined the buffering, snapshot-lifecycle, and cancellation contract that
  the async streams and their adapters follow (issue #291): at most one
  undelivered snapshot is ever held per stream ("bound-1 newest wins"), and
  resuming or replenishing demand never forces a fresh fetch — it only
  surfaces whatever GRDB already produced. Recorded in
  <doc:LiveQueries>, "Buffering and Resumed-Demand Semantics", alongside the
  rejected alternatives.
- Added `XLObservableQuery`/`XLObservableQueryRow` (issue #97): `@Observable`
  (`iOS 17`/`macOS 14`+) wrappers over `stream()`/`streamOne()` exposing
  `rows`/`row`, `isLoading`, and `error` as `@MainActor` state, for SwiftUI
  clients on platforms that ship the `Observation` framework. Package's
  existing iOS 16/macOS 13 floor is unchanged.
- Added `XLResultSet` (issue #249): a connection-scoped, lazy, single-pass
  typed result set whose `next() throws -> Row?` steps and decodes exactly
  one row at a time, via new `withResultSet(_:)`/`withResultSet(bindings:_:)`
  methods on `XLRequest` and a driver-neutral pull-based streaming seam
  (`makeValuesStepper(_:)`) in `SwiftQLCore`.

### Changed

- Rebuilt `publish()`/`publish(bindings:)`/`publishOne()`/`publishOne(bindings:)`
  as Combine adapters over `stream()`/`streamOne()` (issue #309): Combine is
  now a leaf adapter mapping `Subscribers.Demand` onto a pull loop over a
  fresh async stream per subscriber, rather than an independent
  `ValueObservation`-backed observation engine. Public signatures are
  unchanged; a real demand-accounting over-delivery bug found during the
  rebuild is fixed as part of this change.

## [1.5.4] - 2026-07-28

### Added

- Added method-style scalar expression functions matching the existing
  majority style (issue #3): `all().count()`, `a.min(b, ...)`/`a.max(b, ...)`
  (at least one further expression, both because SQLite's scalar `MIN`/`MAX`
  is meaningless with fewer and to stay unambiguous against the deprecated
  zero-argument aggregate `min(distinct:)`/`max(distinct:)` methods of the
  same name), `condition.iif(then:else:)`, and `"...".printf(...)`. The
  previous free functions (`count(_:)`, `min(_:)`/`max(_:)`, `iif(_:then:else:)`,
  `printf(format:_:)`) are deprecated in favor of the new methods, matching
  the existing `sum()`/`average()` → `sumOrNull()`/`averageOrNull()`
  deprecation precedent.
- Added a `Setting(_:_:)` initializer that infers `Setting`'s row type from
  the same table reference already passed to the preceding `Update(_:)`,
  instead of requiring an explicit generic parameter (issue #96):
  `Update(person); Setting(person) { row in row.age = 42 }`. The existing
  `Setting { ... }` and `Setting(metaInstance)` initializers are unchanged.
- Restored the `#row` ad hoc row projection macro (issue #408, follow-up to
  #20; originally shipped in #383, then reverted after a Swift 5.9.2 IRGen
  compiler crash). The single-column shape (`SQLScalarResult`) is available
  on every compatibility cell; the two-to-six column shapes (`SQLRow2`
  through `SQLRow6`) are gated to Swift 6.1+ — SwiftQL's first source-level
  API divergence across compiler cells, documented in COMPATIBILITY.md's new
  "Swift 5.9 and Swift 6.0 API surface gaps" section. The underlying IRGen
  crash reproduces on both the pinned Swift 5.9.2 toolchain (Docker-verified)
  and the pinned Swift 6.0 cell (Xcode 16.2, observed directly in this
  release's CI), and isn't confined to one crossing point: `fetchAll()`,
  `publish()`, and `publishOne()` each hit it independently for a
  2+-generic-parameter row type. Swift 6.1 (Xcode 16.4) is the first cell
  confirmed free of the crash.
- Added `XLQueryObserver` and `XLQueryRowObserver` (issue #28):
  `ObservableObject` wrappers around `publish()`/`publishOne()` that expose
  `@Published rows`/`row` and `@Published error`, so a SwiftUI view model
  can adopt a live query directly without hand-writing a Combine sink. No
  new package dependency — the package conforms to `Combine.ObservableObject`
  (or `OpenCombine`'s equivalent on Linux) without importing SwiftUI itself.

### Changed

- `GRDBRequest.decodeRows(packet:)` accumulates into an outer array and
  returns `Void` from its `withReadConnection`/`withTransaction` closures,
  instead of returning `[Row]` directly. This protects every
  multi-generic-parameter `Row` type from the IRGen crash described above at
  zero cost on other `Row` types — motivated by, but not exclusive to,
  `#row`'s new shapes.

### Deprecated

- Deprecated the free functions `count(_:)`, `min(_:)`/`max(_:)`,
  `iif(_:then:else:)`, and `printf(format:_:)` in favor of their method-style
  equivalents (issue #3). Each keeps a source-compatible signature, including
  a deprecated single-argument `min(_:)`/`max(_:)` overload that preserves
  the prior variadic form's single-argument behavior (SQLite parses
  `MIN(expr)`/`MAX(expr)` as its aggregate function, not a scalar comparison)
  rather than changing it.

### Migration

No migration is required for v1.5.4. Every change is additive or a
source-compatible deprecation; `#row`'s two-to-six column shapes are the
package's first API surface unavailable on Swift 5.9 rather than a removal.

Confirmed and closed out two investigations opened as issues, with no
production code changes: chaining multiple optional fallbacks through
`coalesce`/`??` already composed correctly into SQLite's variadic
`COALESCE` (issue #7 — a footgun where `??` applied to a plain Swift
`Optional` silently falls back to the standard library's operator instead
of rendering `COALESCE` is now called out as a `> Warning` in
`Expressions.md`), and an already-optional scalar-subquery result already
flattened to a single-layer `T?` rather than `T??` (issue #162 — the three
observable NULL states now have direct real-SQLite test coverage).

## [1.5.3] - 2026-07-28

### Added

- Added `@SQLCodec(key)` (issue #66), a zero-storage property attribute
  macro that selects a named contextual value codec (from the v1.2 #188
  registry) on an individual `@SQLTable`/`@SQLResult` stored property,
  without wrapping the property, changing its Swift type, or altering the
  type's memberwise initializer, mutability, `Equatable`, or `Codable`
  behavior. Two properties of the same Swift type can now use two different
  storage conventions on one table. The macro emits the codec key as stable
  metadata (a `_swiftQLPropertyCodecKeys` dictionary keyed by column name)
  and generates a `staticResultField(...)` convenience per annotated
  property that already supplies `selection: .explicit(key)`, so callers
  never repeat the key by hand. Selection still resolves through the
  existing explicit-property/query-override/database-default precedence
  from #188; the attribute only supplies the "explicit" input.
- Added `XLJSONValueCodec` (issue #65), a codec factory that stores any
  application `Codable` value as SQLite `TEXT` or `BLOB`, with an immutable,
  `Sendable` snapshot of the relevant `JSONEncoder`/`JSONDecoder` strategies
  (key/date/data strategy, key sorting) captured at codec construction — no
  live shared encoder/decoder instance and no process-global JSON
  configuration. `TEXT` and `BLOB` are distinct, non-interchangeable storage
  identities. Malformed or incompatible data fails with a structured,
  catchable `XLValueCodecError` that wraps the underlying `EncodingError`/
  `DecodingError`, never a default value.
- Added three named SQLite numeric `Date` codec presets (issue #62):
  `UnixMilliseconds` (`INTEGER`, rounded to the nearest millisecond,
  rejecting `Int64` overflow), `UnixSeconds` (`REAL`,
  `Date.timeIntervalSince1970` stored as-is), and `JulianDay` (`REAL`,
  matching SQLite's own `julianday()` linear relationship). None is an
  implicit default — encoding without an explicit selector or a registered
  database default throws `.ambiguousCodec`. Every preset rejects a
  non-finite `Date` at encode time and a non-finite stored `REAL` at decode
  time with a structured error.
- Added `XLDateTextCodec` (issue #61): a versioned, SQLite-compatible
  standard `Date`-as-`TEXT` preset (fixed proleptic-Gregorian calendar, UTC
  offset, millisecond fractional precision, `Z`-suffixed
  `YYYY-MM-DDTHH:MM:SS.SSSZ` text, directly usable by SQLite's `date`/
  `time`/`datetime`/`julianday`/`strftime` and comparison operators without
  a dialect conversion expression), plus `XLDateTextCodec.custom(key:format:)`
  for applications that need a different fixed UTC offset or fractional
  precision via an explicit, immutable `XLDateTextFormat` — no process-global
  or shared mutable `DateFormatter`. The standard preset's supported
  proleptic-Gregorian year range is `0001...9999`; dates outside it fail to
  encode with a structured error rather than being silently clamped.
- Added `XLUUIDValueCodec.text` and `.blob` (issue #192): named, versioned
  presets that persist Foundation `UUID` as canonical lowercase hyphenated
  `TEXT` or the canonical 16-byte RFC 4122 `BLOB`, using only the existing
  #188 registry — no retroactive `UUID` conformance and no wrapper struct.
  Both target the same `(UUID, sqlite)` value/dialect pair, so they always
  agree on equality (case-insensitive text decode, canonicalized lowercase
  encode) but can never both be installed as the database default at once.
  Malformed input (invalid text, wrong `BLOB` length) surfaces as a
  structured `XLUUIDValueCodecError` carrying codec and property context.

### Migration

No migration is required for v1.5.3. Every codec preset and `@SQLCodec` are
new, additive surfaces built entirely on the existing v1.2 contextual
value-codec registry (#188) and v1.2 static query descriptors (#129); no
existing public API, persisted representation, or codec precedence rule
changed. Applying a new preset or `@SQLCodec` to an existing property is a
schema/data migration for that property alone, exactly like changing any
codec's key or version — the same rule the v1.2 registry already documents.

### Known limitations

- `@SQLCodec` selects among codecs already registered with the
  configuration passed to `staticResultField`; it does not register one
  itself. An unregistered key, or a key registered for a different Swift
  value type or dialect, fails the same way an explicit
  `XLValueCodecSelection` fails elsewhere — with the same `XLValueCodecError`
  cases, at the same "explicit" precedence tier, before any row is touched.
- The numeric and text `Date` codecs stay in SwiftQL's value-coding layer;
  none of them adds a SQL-level `julianday`/`strftime` expression-builder
  helper — value coding stays separate from SQLite's date/time operators
  and functions, which remain other issues' scope.
- PostgreSQL's native `UUID`/`JSONB`/timestamp mappings (tracked separately
  as issue #137) are untouched by this release; these presets are SQLite-
  specific, and a future PostgreSQL dialect module supplies its own mapping
  for the same Swift domain types without changing any codec added here.

## [1.5.2] - 2026-07-27

### Added

- Added a versioned, deterministic SQLite build-validation manifest
  (issue #292): `SwiftQLSQLiteBuildValidationManifest` projects static
  `XLStaticQueryDescriptor`s — SQL text, parameters, result columns, required
  capabilities, and a checked-in schema snapshot's identity/hash/fingerprint —
  into a canonical JSON sidecar. The manifest cross-checks declared
  parameters against the raw SQL text before any consumer runs, and resolves
  #190/#191/#254 conformance references through an injected
  `SQLiteBuildValidationReferenceRegistry` rather than depending on their
  test-only fixture targets. Same input always produces byte-identical
  output: sorted keys, no escaped slashes, sorted/deduplicated arrays.
- Added the standalone SQLite static-query build validator (issue #293): the
  `swiftql-build-validate` executable and its `SwiftQLSQLiteBuildValidationValidator`
  library consume a #292 manifest and its checked-in SQLite snapshot, open one
  dedicated read-only, query-only connection, and prepare every manifest entry
  with `sqlite3_prepare_v3` — proving the SQL parses, referenced
  tables/columns/functions/collations resolve, bind/result metadata matches
  the manifest, and declared capabilities are present in captured runtime
  evidence. Verdicts are fail-closed (`passed`/`failed`/`unsupported`, only
  `passed` succeeds) and the canonical JSON report is deterministic across
  repeated runs against the same inputs. It does not prove result values, row
  counts, or runtime behavior — those stay #214's responsibility, and every
  report names them explicitly under `delegated_checks`.
- Added `SwiftQLSQLiteBuildValidationPlugin` (issue #294), a SwiftPM
  `.buildTool()` plugin that wraps the #293 validator into an ordinary `swift
  build`. A target opts in by listing the plugin and placing a manifest and
  snapshot directly in its own source directory; the plugin declares them as
  explicit build-command inputs and the canonical report as an explicit
  output (never a `.prebuildCommand`), so SwiftPM's own incremental planner —
  not the plugin — decides when to re-run validation. A `failed` or
  `unsupported` verdict fails the build and forwards the validator's
  diagnostic to `swift build`'s output.

### Migration

No migration is required for v1.5.2. The manifest, validator, and plugin are
new, additive surfaces with no changes to any existing public API.

### Known limitations

- The validator proves schema/parameter/capability agreement with the real
  SQLite parser, not result values, row counts, or application behavior.
- Manifest entries can be generated in-process:
  `SQLiteBuildValidationQueryEntry(id:descriptor:declaredAliases:)` projects an
  existing `XLStaticQueryDescriptor` into sidecar form, deriving the SQL,
  parameter layout, and result columns, and recovering each parameter's
  physical placeholder index by scanning the rendered SQL. What no macro or
  tool in this release does is emit a manifest from a `@SQLQuery` declaration:
  the v1.5.1 declaration macro builds on the transitional `sql { }` statement
  path and does not lower to a descriptor, so that route stays a future #26
  boundary gated on the v2 catalog work (#212, #214). A target's snapshot is
  still supplied by you.
- The plugin is verified under `swift build`. Building a plugin-adopting
  package in Xcode 26.5 fails before validation runs, reporting `Build input
  file cannot be found` for the validator executable, on a valid manifest as
  well as an invalid one (#492). Fixed in v1.5.6; on v1.5.2 through v1.5.5 the
  plugin is usable from `swift build` and CI only.

## [1.5.1] - 2026-07-26

### Added

- Added `@SQLQuery` (issues #18/#26), an attached peer macro that lowers a
  query-specification function — an instance method on a database extension
  whose body builds a `sql { }` statement from its own parameters — into a
  value-free statement builder and a cached, cardinality-dispatched executor.
  Labeled parameters and result cardinality are derived from the function's
  own signature: `[Row]` fetches all rows, `Row?` fetches zero-or-one, a bare
  `Row` fetches exactly one (throwing `XLQueryCardinalityError.noRowsMatched`
  or `.moreThanOneRowMatched`), and the legacy `any/some
  XLQueryStatement<Row>` spelling fetches all rows. Every invocation
  constructs a fresh, immutable binding packet; callers never construct or
  mutate a binding themselves and never bind by textual SQL substitution.
- Added `@SQLQueries` (issues #18/#26, the recommended packaging), an
  attached member macro that reads every specification out of a nested
  `private struct Query` container inside one `@SQLQueries`-attached database
  extension, and generates the executors as members of the database itself —
  carrying the specification's own name (`personByName(name:)`, not
  `fetchPersonByName`) because they land in a different scope. Generates a
  connection-scoped `Context`, an `execute(_:)` entry point for running
  several declared queries in one scope, and one database-level convenience
  executor per specification.
- Added the frozen-literal guard: both macros reject, at the declaration
  site, every parameter-reference shape their signature-driven rewrite cannot
  turn into a named placeholder — a string interpolation, a nested-closure
  capture, a direct call argument, a local-binding initializer, a
  hand-constructed binding, a shadowing declaration, member access on a
  parameter, a collection-typed parameter, and an unreferenced parameter.
  Every remaining reference shape the rewrite reaches is rewritten to a named
  placeholder, so the encoding has no path that silently freezes a stale
  argument value into the cached SQL.
- Added `XLRenderOnceCache` and `XLPreparedQueryCacheKey`: each declaration
  renders its value-free statement to SQL at most once per
  `(databaseIdentifier, dialectIdentifier)` and reuses the resulting request
  on every later call, so the underlying GRDB connection reuses one physical
  prepared statement across calls with different argument values.
  `GRDBDatabase.preparedQueryCacheKey` opts the GRDB adapter into this
  reuse; `XLDatabase.preparedQueryCacheKey` defaults to `nil` (render on every
  call) so existing third-party adapters keep compiling.
- Added the `DeclaredQueries` DocC article covering the `@SQLQuery` and
  `@SQLQueries` forms, the frozen-literal guard, render-once caching and its
  concurrency/`Sendable` story, and the v1.5 transitional-syntax note.
- Added typed multi-statement transaction scopes (issue #284):
  `XLTransactionalDatabase.withTransaction(_:)` runs an ordered sequence of
  typed `XLRequest`/`XLWriteRequest` invocations — reads and writes alike —
  on one pinned GRDB connection as a single atomic unit, committing only
  after the whole body succeeds and rolling back every write on a
  preparation, binding, execution, decoding, or user-thrown failure, with no
  GRDB type anywhere in the contract. `@SQLQueries`'s generated `execute(_:)`
  is now sugar over this same primitive, so declared-query calls and
  `makeRequest(with:)` calls in one `execute(_:)` closure commit or roll back
  together. Calling `withTransaction(_:)` again from inside an active body —
  whether on the scope it was given or on the original database captured
  from the enclosing closure — is rejected with a catchable
  `XLTransactionScopeError.nestedTransactionUnsupported` before any pool
  access, instead of the uncatchable crash GRDB's own reentrant-write guard
  would otherwise raise. A scope value used after its body returns throws
  `.scopeEscaped`; `publish()`/`publishOne()` inside a transaction throws
  `.liveQueriesUnsupportedInTransaction`; an already-cancelled task throws
  `CancellationError` before the transaction opens. Documented in
  `GettingStarted`'s "Typed multi-statement transaction scopes".
- Added composite/nested result selection (issue #6): a stored property on an
  `@SQLTable`/`@SQLResult` type can now itself be another `@SQLTable`/
  `@SQLResult` type. The generated `staticRowLayout(using:...)` factory
  flattens every one of the nested type's own columns into the enclosing
  type's flat SQL result (re-aliased with the property name as a prefix, e.g.
  `employee_id`, `employee_name`), and reconstructs the nested value before
  building the enclosing type. Nesting composes to any depth, since a
  composite property's argument is itself the nested type's own
  `staticRowLayout(using:...)` result.
- Added the `XLStaticRowFieldSource` protocol and `XLStaticFieldGroup` type to
  `SwiftQL`. Every generated `staticRowLayout(using:...)` parameter now takes
  an `XLStaticRowFieldSource` value; both an ordinary `XLStaticSelectField`
  (through a default implementation, so no scalar call site changes) and an
  `XLStaticRowLayout` (for a nested composite property) conform to it. The
  macro has no semantic access to a property's type declaration, so it never
  has to detect which case applies -- Swift's own conformance checking
  resolves it from whichever value the caller passes to a given property.
- Extended the unsupported-column-type diagnostic to name both supported
  property shapes (a scalar `XLLiteral` column, or a nested `@SQLTable`/
  `@SQLResult` composite), so a property type the macro cannot resolve as
  either is rejected with an actionable message instead of only failing
  downstream with an opaque protocol-conformance error.
- Added the issue #256 `@SQLTable`/`@SQLResult` macro regression corpus:
  expansion and diagnostic tests for reserved/escaped and Unicode
  identifiers, SQL-keyword-like property names, doubly-wrapped optionals,
  every reserved generated-member name, mixed access-control modifiers, and
  a wide (12-property) row; and a checked-in downstream consumer fixture
  (`IntegrationTests/Swift5Client`) that compiles and executes BLOBs,
  optionals, `XLEnum` columns, a wide row, and composite/nested result
  selection against real SQLite without `@testable`. Each case's provenance
  and disposition (including the still-unsupported optional composite
  property, gated on issue #6) is recorded in
  `Tests/SQLMacrosTests/MacroRegressionCorpus.json`, a sibling to the #190
  SQL-syntax conformance inventory scoped to macro code-generation instead.
- Added the `@SQLFunction` macro (#25), which generates the `XLCustomFunctionDefinition`
  and `makeSQL(context:)` boilerplate for a custom `XLCustomFunction` conformer
  from its stored properties — one positional SQL argument per property, in
  declaration order. `execute(reader:)`, the actual computation, is still
  written by hand. The macro is opt-in sugar: hand-written `XLCustomFunction`
  conformances that implement `definition` and `makeSQL` themselves keep
  working unchanged.
- Added implicit custom-function registration. A custom function conforming to
  `XLCustomFunction` can opt in by calling the new
  `XLBuilder.customFunctionCall(_:parameters:)` from `makeSQL(context:)`
  instead of `simpleFunction(name:parameters:)`. `GRDBDatabase` then registers
  the function with SQLite automatically the first time a rendered statement
  referencing it executes, without requiring a `GRDBDatabaseBuilder.addFunction`
  call beforehand. Because `GRDB.DatabasePool` maintains several persistent
  reader connections and a registration only affects the one physical
  connection it runs on, the function is (cheaply) re-registered on every
  execution rather than tracked as "already registered" once, so it works
  correctly no matter which pooled connection services a given call.
  `GRDBDatabaseBuilder.addFunction` is unchanged and continues to work exactly
  as before for functions that keep calling `simpleFunction` directly, or for
  callers who prefer registering everything upfront.

### Migration

No migration is required for v1.5.1. `@SQLQuery` and `@SQLQueries` are new,
additive macros; the one new `XLDatabase.preparedQueryCacheKey` protocol
requirement has a default (`nil`) that keeps every existing conformer,
including third-party `XLDatabase` adapters, source-compatible.

### Known limitations

- Only `SELECT`-shaped specifications are supported; a write statement
  (`INSERT`/`UPDATE`/`DELETE`, with or without `RETURNING`) is not yet an
  accepted return shape. A `.command` cardinality dispatching to
  `XLWriteRequest.execute` remains future work.
- Collection-typed parameters (`[T]`, `Set`, `Dictionary`) are rejected,
  because a variable-length `IN` list would change the rendered SQL text with
  the element count.
- The generated executor is synchronous and throwing; an `async` variant is
  additive future work.
- Peer and member names are derived from the specification's base name only,
  so two `@SQLQuery` functions sharing a base name but differing in
  parameter list generate colliding peer declarations — a loud
  duplicate-declaration compile error, not a silent one.
- Only one `@SQLQueries`-attached extension is supported per database type; a
  second would redeclare `Context` and `execute(_:)`.
- A composite/nested `@SQLTable`/`@SQLResult` property must be
  non-optional; an optional nested composite (representing an absent
  value from an outer join, for example) is not yet supported.
- `withTransaction(_:)` does not support nested transactions or savepoints —
  a nested call is rejected outright rather than silently composed — and
  cancellation is checked only once, before the transaction opens; the
  synchronous body has no cooperative mid-transaction cancellation point.
  Both remain tracked by v2 issue #113, matching the disposition the shared
  `SQLiteTransactionConformanceFixtures` capability table (issue #253)
  already recorded for the driver-level contract.

## [1.4.6] - 2026-07-25

### Changed

- Reduced SwiftQL query construction-and-rendering allocations without changing
  rendered SQL, entity metadata, query semantics, or the public 1.x API. A
  deterministic allocation profile attributed roughly three-quarters of the
  `swiftql_construction_and_rendering` phase's allocations to rendering;
  single-argument token append, a single-token `build()` fast path, and a
  one/two-component `scopedName` fast path cut render allocations about 15% and
  the phase median about 13-17% across the #128 harness read cases, with
  byte-identical SQL. No absolute CI latency gate was added (#166).
- Reused one per-row normalization buffer on the incremental GRDB decode path,
  removing the per-row `[XLSQLiteValue]` allocation (and a redundant `Array`
  copy) while preserving the #248 bounded-memory guarantee — the typed decode
  path materializes no intermediate matrix. This is an allocation-only change
  and is latency-neutral on the #250 harness, which showed the incremental
  regression is decode-compute bound rather than allocation bound; the
  remaining latency work is tracked in #353 (#266).

### Added

- Added the `swiftql-construction-profile` diagnostic executable. It counts
  per-operation heap allocations through the in-process `malloc_logger` hook and
  splits construction versus rendering timing for the #128 read queries. It is
  diagnostic evidence for #166, not part of any product runtime or a CI gate.

### Migration

No migration is required for v1.4.6. Every change is internal; the public API,
entity metadata, and rendered SQL are unchanged.

## [1.4.5] - 2026-07-24

### Added

- Added `NATURAL JOIN` and `USING (columns...)` join constraints through
  `Join.Natural(_:)`, `Join.NaturalLeft(_:)`, `Join.Inner(_:using:)`, and
  `Join.Left(_:using:)`, plus the fluent `naturalJoin`/`naturalLeftJoin` and
  `innerJoin(_:using:)`/`leftJoin(_:using:)` methods (also on `QueryBuilder`).
  A join renders exactly one of `ON <expr>`, `USING (cols)`, or — for
  `NATURAL` — no constraint at all.
- Added `RIGHT JOIN` through `Join.Right(_:on:)` and the fluent/`QueryBuilder`
  `rightJoin` methods. The joined (right-hand) table stays non-nullable; the
  `FROM` (left-hand) table must be declared with `XLSchema.nullableTable(_:as:)`
  so its columns decode as optionals when a joined row has no match. Requires
  SQLite 3.39.0 (2022-06) or later.
- Added `FULL OUTER JOIN` and completed `CROSS JOIN` coverage on `QueryBuilder`
  through `Join.FullOuter(_:on:)` and the fluent/`QueryBuilder`
  `fullOuterJoin`/`crossJoin` methods. A full outer join requires both sides
  nullable — the joined table via `XLMetaNullableNamedResult`, the `FROM`
  table via `nullableTable(_:as:)` — unlike `LEFT JOIN`, where only the
  joined side is nullable. Requires SQLite 3.39.0 or later. The previously
  broken `Join.Outer`, which emitted an invalid bare `OUTER JOIN`, stays
  removed in favor of `Join.Left`/`Join.FullOuter`.
- Added `MATERIALIZED` / `NOT MATERIALIZED` hints on common table expressions
  through a `materialization: XLCommonTableMaterialization` parameter on
  `XLSchema.commonTable`, `recursiveCommonTable`, `recursiveCommonTableExpression`,
  and the new scalar common-table constructors below. Omitting it — the
  default, `.unspecified` — renders the unchanged `alias AS (...)` form.
- Added a direct scalar common-table-expression surface —
  `XLSchema.scalarCommonTable`, `recursiveScalarCommonTable`,
  `scalarCommonTableExpression`, and `recursiveScalarCommonTableExpression` —
  so a `T`-typed recursive or non-recursive CTE no longer needs a
  one-property `@SQLResult`/`SQLScalarResult<T>` wrapper solely to carry one
  scalar column. The CTE renders an explicit column list (`cte(value) AS
  (...)` by default) instead of changing every scalar `SELECT`'s visible
  column label. `SQLScalarResult` remains source-compatible as a legacy shim.
- `UNION`, `UNION ALL`, `INTERSECT`, and `EXCEPT` on a chained statement no
  longer require `Row: XLResult`; they now reuse the first branch's existing
  row reader instead of rebuilding one from `Row: XLResult`, so a compound
  query over a bare literal type (`Int`, `String`, ...) composes without a
  result wrapper.
- Replaced the internal mutable recursive-CTE completion cell with an
  alias-first, two-phase, value-semantic `XLRecursiveCommonTableDraft`. The
  self-reference passed to a recursive CTE's body is now derived from its
  reserved alias alone, and completion is transactional: a throwing body
  rolls the draft back to its declared state so it can be retried.
  `recursiveCommonTable` and `recursiveCommonTableExpression` keep their
  existing signatures and render byte-for-byte identical SQL.

### Migration

No migration is required for v1.4.5. Every change is additive: existing
joins, common table expressions, and `SQLScalarResult` usage compile and
render unchanged.

## [1.4.4] - 2026-07-23

### Added

- Added `INSERT OR ROLLBACK/ABORT/FAIL/IGNORE/REPLACE` through `Insert(_:or:)`
  and the functional `insert(_:or:)`. The conflict algorithm is part of the
  `INSERT` keyword and applies to every uniqueness constraint the statement
  violates.
- Added the `REPLACE INTO` statement through `Replace` and the functional
  `replace(_:)`, the SQLite shorthand for `INSERT OR REPLACE INTO`.
- Added `INSERT ... ON CONFLICT` upsert support through `OnConflict`, the
  functional `onConflict`/`onConflictDoNothing` methods, and `XLSchema.excluded`
  for referencing the proposed row. Both `DO NOTHING` and `DO UPDATE SET ...`
  (with an optional `WHERE` filter) forms are covered.
- Added `UPDATE` support scoped by a `WITH` common table expression through
  `XLWithStatement.update`, so a factored common table expression can drive an
  update, for example `with(cte).update(t).set { ... }.from(cte).where(...)`.
- Added `INSERT ... RETURNING` through the `Returning` clause and the
  `returning(_:)` method on insert statements (including `ON CONFLICT` upserts).
  A returning statement is fetchable — `makeRequest(with:).fetchAll()` yields the
  affected rows projected through the supplied result. SQLite rejects
  statement-aliased names in `RETURNING`, so the returned columns render
  unqualified; the statement executes on a write connection and is not
  observable as a live query. Requires SQLite 3.35.0.
- Added `DELETE ... RETURNING` through the same `returning(_:)` clause on delete
  statements, yielding the deleted rows. Requires SQLite 3.35.0.
- Added `UPDATE ... RETURNING` through the same `returning(_:)` clause on update
  statements, yielding the updated rows. This completes RETURNING for INSERT,
  UPDATE, and DELETE. Requires SQLite 3.35.0.
- Confirmed and recorded the SELECT forms of data-changing statements:
  `INSERT ... SELECT` and the `UPDATE ... SET ... FROM (SELECT ...)` form (built
  with `fromExpression`). Both now carry real-SQLite execution evidence in the
  conformance inventory.
- Recorded the new conflict-resolution, replace, upsert, update-with-CTE,
  RETURNING (insert, delete, update), and INSERT/UPDATE SELECT surfaces in the
  #190 canonical SQLite conformance inventory. It records 117 public-surface feature records: 113
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  1 unimplemented. Of the 193 evidence records, 117 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.

### Migration

No migration is required for v1.4.4. Every change is additive, and the existing
insert surface remains source-compatible.

## [1.4.3] - 2026-07-23

### Added

- Added the `date`, `time`, `datetime`, `julianDay`, `unixEpoch`, and `strftime`
  constructors on text time-value expressions. Each takes ordered
  `XLDateModifier` values, and SQLite applies them left to right, so the Swift
  argument order is the evaluation order — `moment.datetime(.months(1),
  .startOfMonth)` renders `datetime(..., '+1 months', 'start of month')`.
  Optional receivers preserve optionality.
- Added `XLDateModifier`, an ordered modifier type covering the relative-offset
  (`.days`/`.hours`/`.minutes`/`.seconds`/`.months`/`.years`), anchoring
  (`.startOfDay`/`.startOfMonth`/`.startOfYear`/`.weekday(_:)`), `.ceiling`,
  `.floor`, `.localTime`, `.utc`, and `.subsecond` modifiers available in every
  SQLite release the library validates against (3.42.0 and later). A modifier
  renders as a quoted string literal, so it cannot inject SQL; input-interpretation
  modifiers whose availability varies by release (`unixepoch`, `julianday`,
  `auto`) stay reachable through `XLDateModifier(_:)` rather than as named
  members.
- Added the `year`, `month`, `day`, `hour`, `minute`, `second`, `dayOfYear`,
  `dayOfWeek`, and `weekOfYear` component accessors, each reinterpreting a
  `strftime` substitution as an `Int` with `CAST(... AS INTEGER)`. An optional
  receiver preserves `NULL`.
- Moved `syntax.expression.date-functions` from partial to supported in the
  conformance inventory with new rendering and real-SQLite execution evidence,
  and regenerated the report.

### Changed

- `unixEpoch(_:)` returns `TimeInterval` rather than `Int`, because the
  constructor accepts arbitrary modifiers — including `.subsecond`, which makes
  SQLite return fractional seconds that an `Int` cannot represent. This mirrors
  the legacy `unixepoch(date:modifiers:)` surface. `toUnixTimestamp()` still
  returns `Int` for the no-modifier integer case.

### Migration

Date comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`) and julian-day subtraction
(`-`) reuse the existing generic `XLComparable` and floating-point operators
over date-function results rather than adding date-specific overloads, so
existing call sites are unaffected.

The legacy `unixepoch(date:modifiers:)`, `toUnixTimestamp()`, and
`XLDateFunctionModifiers` surface is retained for source compatibility.

## [1.4.2] - 2026-07-22

### Added

- Added `like(_:escape:)` across the same four optionality shapes as `like`.
  `ESCAPE` renders inside its own `LIKE` production, so a second `LIKE` in the
  same predicate cannot absorb it. SQLite requires the escape value to be
  exactly one character; a longer or empty value prepares and then fails when
  the statement is stepped, because no Swift type can express that constraint.
- Added `notIn` value-list, subquery, and common-table expressions mirroring the
  existing `in` shapes. The negation is carried by the `IN` node itself rather
  than by a wrapping `NOT`, so composing a predicate cannot move it outwards.
- Added optional-operand and NULL-candidate support to `in` and `notIn`,
  including the result-builder subquery form for optional receivers and NULL
  elements in a value list.
- Added `nullableSubquery(alias:_:)` and `nullableSubqueryExpression(alias:_:)`
  for subqueries on the nullable side of a `LEFT JOIN`, and flattened scalar
  subquery results so an optional inner statement no longer double-wraps
  `Optional`.
- Added connection-registered custom collating sequences.
  `GRDBDatabaseBuilder.addCollation(_:compare:)` registers a sequence on every
  connection the builder creates, mirroring the existing `addFunction`, and
  `XLCollation` gained `init(rawValue:)` so a name outside the three built-ins
  can be expressed.
- Added the `REGEXP` operator across the same four optionality shapes as `glob`.
  SQLite parses `X REGEXP Y` as a call to `regexp(Y, X)` and ships no
  implementation, so the operator prepares only once the application registers a
  two-argument `regexp` function. (As of 1.7.0 SwiftQL supplies that function,
  and the operator needs no registration by the caller.)
- Completed the generated real-SQLite operator conformance matrix. Every public
  operator overload now carries both prepare and semantic execution evidence,
  packed by operator family and optionality shape, and the corresponding
  inventory record moves from partial to supported.
- Added real-SQLite IN-subquery conformance cases for both query-backed entry
  points, and revived the same-table IN-subquery execution test so distinct
  aliases across two nesting levels are pinned by an executing test.

### Changed

- `XLCollation` is now a `RawRepresentable` struct rather than an enumeration.
  `.binary`, `.nocase`, and `.rtrim` remain available as static members and
  still render as bare grammar tokens. A custom name renders as a quoted
  identifier — `COLLATE "myCollation"` — which SQLite resolves to the same
  sequence, so `collate(_:)` does not become an arbitrary raw-SQL escape hatch.
  Equality and hashing fold ASCII case, matching how SQLite resolves collation
  names.

### Deprecated

- Deprecated the `subquery(alias:)` overload constrained to `XLMetaNullable`.
  It can never be selected, because no `select` function produces a statement
  over a nullable row type. Use `nullableSubquery(alias:_:)` instead.

### Migration

Existing `in`, `like`, `collate(_:)`, and `subquery(alias:)` call sites remain
source-compatible.

`XLCollation` changed from an enumeration to a struct. Code that switches
exhaustively over a collation value must gain a `default` case:

```swift
switch collation {
case .binary, .nocase, .rtrim:
    …
default:
    …
}
```

Register a custom collating sequence before naming it in a query. SQLite
resolves collations at preparation and reports `no such collation sequence`
otherwise:

```swift
builder.addCollation("localized") { lhs, rhs in
    lhs.compare(rhs, options: [], range: nil, locale: .current)
}
…
OrderBy(person.name.collate(XLCollation(rawValue: "localized")).ascending())
```

`REGEXP` requires the application to register a two-argument `regexp` function
on the connection. Without it, a statement using the operator fails to prepare
with `no such function: regexp`. (No longer true as of 1.7.0, which ships the
implementation.)

Select a scalar subquery on the nullable side of a join with
`nullableSubquery(alias:_:)`; the deprecated `XLMetaNullable` overload of
`subquery(alias:)` was never selectable.

## [1.4.1] - 2026-07-22

### Added

- Added constrained `cast(to:)` overloads across the Bool, integer, real, text,
  data, and optional conversion matrix. Source nullability is preserved and
  unsupported cast directions remain unavailable at compile time. The
  directional `toInt()`, `toDouble()`, `toString()`, and `toData()` helpers now
  delegate through the new API.
- Added a typed `all()` expression that renders an unqualified `*`, and
  `count(all())` with an `Int` result and exact `COUNT(*)` rendering. Row-count
  semantics are covered for populated, empty, and all-NULL SQLite inputs.
- Added typed `isBetween(_:_:)` and `isNotBetween(_:_:)` expressions. Nullable
  operands yield optional Boolean results, and each complete predicate is
  grouped so SQLite precedence is unambiguous. Compile-fail fixtures reject
  mismatched and non-comparable operand types in every compatibility cell.
- Added `total()` overloads for integer, real, nullable integer, and nullable
  real expressions. They preserve SQLite's non-null `Double` semantics,
  returning `0.0` for empty and all-NULL inputs, in deliberate contrast with
  the optional `sum()` API.
- Broadened `averageOrNull(distinct:)` to integer and real expressions and to
  their nullable forms, preserving a `Double?` result and plain `AVG(...)`
  rendering.
- Extended the bounded combinatorial SQLite corpus from 141 to 168 cases with
  explicit function, aggregate, JSON, `PRINTF`, and cast coverage. Every new
  case executes against real SQLite with an independent raw-SQL semantic
  oracle, including exact JSON capability attestation for `JSON_VALID/1` and
  `JSON_ARRAY_LENGTH/1,/2`.

### Changed

- Both real Swift 5.9 compatibility cells moved from the retiring `macos-14`
  runner to `ubuntu-22.04`. The cells install the exact official Swift 5.9.2
  archive under pinned detached-signature and signing-key verification, and
  privately link a checksum-verified SQLite 3.53.3 build so an older system
  SQLite cannot silently reduce the conformance surface. The complete
  compatibility build and the full package test suite continue to run in both
  committed- and clean-resolution modes.

### Migration

No migration is required for v1.4.1. Every change is additive or confined to
continuous integration, and the v1.3 public source and runtime contracts are
preserved.

## [1.3.0] - 2026-07-20

### Added

- Added the #190 canonical SQLite conformance inventory and deterministic
  generated report. It records 105 public-surface feature records: 97
  supported, 0 partial, 2 capability-gated, 1 intentionally unsupported, and
  5 unimplemented. Of the 141 evidence records, 89 exercise real SQLite and
  cite one captured SQLite 3.51.0 environment.
- Added the #191 bounded combinatorial SQLite corpus with 141 stable generated
  cases across joins, subqueries, common table expressions, grouping,
  bindings, and related interactions, plus a deliberately broken-renderer
  negative control. Deterministic manifests and runtime provenance keep the
  exercised combinations reviewable without presenting them as exhaustive
  SQL coverage.
- Added the #254 immutable Northwind SQLite snapshot and 18 stable correctness
  scenarios for realistic joins, aggregates, subqueries, compound queries,
  common table expressions, decoding, CRUD, and rollback behavior.
- Added the #255 live-query observation stress suite with 12 stable cases for
  concurrent writes, invalidation, delivery, cancellation, transient-busy
  retries, and database isolation.
- Added the #132 research prototype for deterministic build-time preparation
  of static query descriptors against the checked-in Northwind snapshot. The
  prototype owns a read-only validation connection, finalizes every prepared
  statement, and emits a reproducible report; it is internal research, not a
  public validator, build plugin, macro, schema system, or v1.3 API.

### Migration

No migration is required for v1.3. The milestone adds conformance evidence,
correctness and stress coverage, internal research artifacts, and refreshed
documentation while preserving the v1.2 public source and runtime contracts.

## [1.2.0] - 2026-07-19

### Added

- Added the GRDB-free `SwiftQLCore` product with orthogonal SQL-dialect,
  dialect-value, logical-statement, validated database-driver, and transaction
  contracts. The existing `SwiftQL` product remains the application-facing
  facade with the current GRDB-backed SQLite implementation.
- Added immutable `XLStaticQueryDescriptor` definitions with durable canonical
  identities, explicit dialect requirements, parameter/result layouts,
  referenced entities, and cardinality. Raw prepared static-query handles are
  database-bound and `Sendable` without retaining a physical statement.
- Added generated static row layouts for `@SQLTable` and `@SQLResult`, including
  contextual value encoding and typed decoding without constructing default
  model instances or requiring `sqlDefault()`.
- Added immutable, value-free `XLQueryCapture` declarations and fresh
  `XLInvocationBindings` packets. Repeated calls keep runtime values out of
  logical requests, descriptors, identities, and statement caches.
- Added immutable contextual value-codec registries and database configuration
  snapshots. One Swift type can select different versioned SQLite
  representations without a process-global registry or retroactive literal
  conformance.
- Added shared adapter-neutral SQLite value/storage and transaction contract
  suites, each exercised against the production GRDB driver with stable case
  identities and durable semantic oracles.
- Added an independent cross-library SQLite benchmark baseline and a
  reproducible first-party source-coverage topology check.

### Changed

- GRDB result rows are stepped and decoded incrementally while their leased
  connection is active. Public `fetchAll()` and `fetchOne()` behavior remains
  eager and source-compatible, but intermediate GRDB and normalized row arrays
  are no longer retained.
- Literal decoding now uses a scoped field reader, and the sequential row reader
  is a value type, removing per-row reference allocation from the legacy typed
  decode path.
- `Select` no longer requires the result type itself to conform to `XLResult`;
  typed selection is carried by its row layout. Existing `XLResult` models
  continue to compile.
- First-party SQL renderers now use semantic `XLSeparator.list` and `.tuple`
  names. The legacy `.comma`, `.space`, raw-value, and custom-string separator
  APIs remain available throughout v1.
- Table and common-table `FROM` dependencies now share one dependency model,
  including value-semantic recursive common-table definitions and references.

### Fixed

- Non-finite `Double` literals now fail through validated encoding instead of
  emitting invalid SQLite tokens or silently changing the value.
- `COLLATE` names render as SQL grammar tokens, fluent `INSERT ... SELECT`
  clause chains execute against real SQLite, and the query builder's
  missing-`FROM` failure is covered by its documented contract.
- Generic list composition now implements `BETWEEN`, static result descriptors
  remove hidden default-value requirements, and separator cleanup preserves
  byte-identical SQL and binding order.

### Migration

Existing `makeRequest(with:)`, `XLNamedBindingReference`, `XLCustomType`,
`XLLiteral`, `XLResult`, explicit packet, and raw separator APIs remain
source-compatible in SwiftQL 1.x. No application must adopt the lower-level
v1.2 contracts merely to keep an existing query working.

For a new reusable query that needs durable identity, cross-task raw-value
execution, or contextual result layouts, construct and register an
`XLStaticQueryDescriptor` before opening a database, prepare it against that
database, and create a fresh `XLInvocationBindings` packet for every call. Do
not share the current `XLRequest` facade across tasks; it remains task-local.

Prefer `XLValueCodec` plus an immutable `XLValueCodingConfiguration` when one
application type has multiple persisted representations. Keep a legacy
`XLCustomType` wrapper only when preserving its existing v1 storage bytes and
introspection behavior is required. Changing a codec key, version, stable type
identifier, dialect, or storage identifier is a schema/data migration.

Validated encoding is now the explicit error boundary for unsupported literal
values such as non-finite `Double`. Code that constructs SQL from untrusted or
computed floating-point values should propagate that error instead of assuming
every `Double` has a SQLite literal spelling.

## [1.1.0] - 2026-07-17

### Added

- Added a verified tag-release workflow that reuses the complete Swift compiler
  matrix and DocC build, publishes deterministic provenance/checksum assets
  through an idempotent draft-first GitHub Release, and provides read-only test
  tags plus documented partial-release recovery.
- Added a least-privilege GitHub Pages workflow that builds documentation on
  pull requests and deploys only authorized `main` commits, with artifact and
  deployed-site provenance tied to the exact commit SHA.
- Added a non-mutating, warnings-as-errors DocC site generator with built-in
  validation for the SwiftQL landing page and all ten source articles. CI
  smoke-tests the same command used locally.
- Added an `XLEnum` guide with compile-checked integer- and string-backed enum
  examples and real SQLite coverage for valid and unknown stored raw values.
- Added compile-time-checked scenario mappings for every Swift example in the
  DocC landing page and source articles, with a catalog test that rejects
  untyped fences, stale API spellings, and unknown test markers.
- Added a provenance-aware warnings-as-errors gate for every supported compiler
  lane. It blocks SwiftQL-owned and unclassified warnings while reporting
  dependency and toolchain diagnostics separately.
- Added an external Swift package fixture that uses SwiftQL's public macros,
  typed queries, binding, and SQLite execution from Swift 5 language mode under
  the supported Swift 6 compiler. CI runs it with pinned and clean resolution.
- Added a reproducible `swiftql-benchmark` executable that reports raw samples,
  median, and p95 for SwiftQL construction/rendering, uncached SQLite
  preparation, statement-cache hits, reset/binding, execution, and production
  row decoding. All supported compiler lanes run a structure-only smoke test.
- Added `minOrNull(distinct:)`, `maxOrNull(distinct:)`, `sumOrNull(distinct:)`,
  `averageOrNull(distinct:)`, `groupConcatOrNull(distinct:)`, and
  `groupConcatOrNull(separator:)` APIs whose expression types represent SQLite
  NULL results.
- Added an opt-in GRDB live-query retry policy for transient `SQLITE_BUSY`
  failures. It performs three serialized retries after deterministic 0.1, 0.2,
  and 0.4 second delays, resets after a delivered value, and preserves terminal
  behavior by default.

### Deprecated

- Deprecated the nonoptional `min`, `max`, `sum`, `average`, and `groupConcat`
  aggregate APIs. Their signatures remain available throughout SwiftQL 1.x.
  The canonical APIs will return optional expressions in SwiftQL 2.

### Fixed

- Removed stale generated documentation from version control. Local static-site
  output is ignored and can no longer stage or commit unrelated work.
- Updated DocC examples and key public symbol documentation to the current API.
  Source documentation now generates cleanly with DocC warnings treated as
  errors.
- Prefix bitwise NOT (`~`) is now constrained to integer SQL expressions.
  Real-valued expressions such as `Double` are rejected by the Swift type
  checker.
- Generated `.columns(...)` helpers no longer call the deprecated `result`
  helper, and immutable table macros no longer emit never-mutated-local
  warnings. Projection factories are emitted as nominal macro members so their
  static lookup works across files on Swift 5.9. First-party sources, tests,
  benchmarks, and macro expansions now build without ordinary compiler
  warnings.
- All first-party product and test targets now compile without complete
  strict-concurrency warnings under the supported Swift 6 compiler. The
  compatibility matrix checks this without enabling Swift 6 language mode.
- String concatenation now renders as an explicitly grouped binary expression,
  so `COLLATE` and surrounding operators apply with unambiguous SQLite
  precedence.
- Empty and all-NULL aggregate results can now be modeled and decoded as Swift
  `nil` through the new optional-result APIs.

### Migration

Use an `OrNull` aggregate when SQLite can return NULL:

```swift
let total = invoice.amount.sumOrNull()
```

Choose a nonoptional fallback explicitly when required:

```swift
let total = invoice.amount.sumOrNull().coalesce(0)
```

The deprecated v1 APIs retain their old result types and may still throw when
SQLite returns NULL. Projects that treat warnings as errors must migrate
deprecated calls when adopting SwiftQL 1.1.

The deprecated `NotificationCenter.sqlEntitiesChangedObserver` and
`sqlCommitObserver` callbacks are now explicitly `@Sendable`, matching
Foundation's callback contract. Existing calls remain source-compatible, but
strict-concurrency checking may require captured mutable state to gain explicit
isolation.

Scalar subqueries already add an optional layer because they may return no row.
Selecting an `OrNull` aggregate — or any other already-optional expression —
inside `subquery` or `subqueryExpression` composes directly into a single
`Int?`, not `Int??`, so Swift models SQLite's single NULL state without an
explicit type-affinity wrapper:

```swift
let total = subquery {
    select(invoice.amount.sumOrNull()).from(invoice)
}
```
