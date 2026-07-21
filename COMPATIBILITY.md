# Compiler compatibility

SwiftQL 1.x keeps `swift-tools-version: 5.9`. CI retains two pinned compiler
support points and also runs the complete package test suite with every Swift
series currently listed by Swift Package Index: Swift 6.0 through Swift 6.3.
All Swift 6 compilers run the package in Swift 5 language mode; SwiftQL does not
opt into Swift 6 language mode.

## v1.3 public products and runtime boundaries

The package supports iOS 16 or later and macOS 13 or later. Its public products
have separate responsibilities:

- `SwiftQLCore` is the GRDB-free contract layer for SQL dialects, dialect
  values, logical statements, immutable parameter layouts and invocation
  packets, static query descriptors, and database drivers. It is intended for
  adapter packages and does not provide a usable SQLite connection by itself.
- `SwiftQL` is the application-facing library. It includes `SwiftQLCore`, the
  macros and typed SQL DSL, contextual value codecs, and the current
  GRDB-backed SQLite driver.
- `swiftql-benchmark` is a repository performance diagnostic executable, not an
  application runtime dependency or a database adapter.

The manifest's dependency bounds are SwiftSyntax 509.0.0, GRDB 6.29.3 or later,
Swift-DocC plugin 1.0.0 or later, and exact OpenCombine 0.14.0. SwiftSyntax also
retains its existing compatible-from-509.0.0 manifest range.
Committed-resolution jobs prove the checked-in
graph; clean-resolution jobs prove that the declared ranges still resolve and
pass. The exact resolved versions and loaded SQLite source ID are CI evidence,
not a promise that every future dependency version in those ranges is already
supported.

The reusable-query ownership model introduced in v1.2 remains unchanged in
v1.3. An `XLStaticQueryDescriptor` and `XLInvocationBindings` are immutable,
database-independent values. A raw `GRDBPreparedStaticQuery` or
`GRDBPreparedInvocation` is `Sendable` and database-bound without owning a
connection-bound statement. The high-level `XLRequest` facade and
closure-backed typed static-row wrapper remain task-local. Each execution may
lease a different connection and prepare or cache a physical GRDB statement on
that connection. These ownership rules are part of the supported API contract,
not only implementation details.

SwiftQL currently ships only a SQLite dialect and a GRDB database driver. Apple
platforms use Combine; Linux uses OpenCombine for the same request-publisher
surface. The core protocols are extension seams, not claims that another
dialect, driver, nested transaction/savepoint API, asynchronous cursor, or
Swift 6 language mode is supported.

## SQLite conformance inventory

The [SQLite conformance report](Conformance/SQLite/REPORT.md) summarizes the
evidence recorded in the canonical, versioned
[SQLite conformance inventory](Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json).
The report is evidence for SwiftQL's existing public SQLite subset; it is not a
claim of complete SQLite grammar coverage. The inventory remains the source of
truth, while the report is its readable generated view.

The v1.3 inventory contains 101 feature records and 108 evidence records. Its
support-status totals are exact and mutually exclusive:

| Support status | Features |
| --- | ---: |
| Supported | 89 |
| Partial | 2 |
| Capability-gated | 2 |
| Intentionally unsupported | 1 |
| Unimplemented | 7 |

Of those 108 evidence records, 70 exercise real SQLite and
cite one captured environment, SQLite 3.51.0. An inventory entry is counted in
the 89 supported features only when it links to successful preparation by a
real SQLite engine whose version and source ID are recorded. Partial,
capability-gated, intentionally unsupported, and unimplemented entries remain
visible with their evidence, requirements, or rationale, but are excluded
from the supported total. Evidence records are reusable proofs, so the count
of 100 is not intended to match the feature count one for one.

The v1.3 work has distinct ownership and claims:

- [#190](https://github.com/lukevanin/swiftql/issues/190) owns the canonical
  feature taxonomy, status decisions, evidence references, generated report,
  and the totals above.
- [#191](https://github.com/lukevanin/swiftql/issues/191) supplies a bounded,
  deterministic 141-case combinatorial manifest for joins, subqueries, common
  table expressions, grouping, bindings, and related interactions, plus a
  deliberately broken-renderer negative control. It contributes real-SQLite
  evidence to the inventory without claiming exhaustive SQL combinations.
- [#254](https://github.com/lukevanin/swiftql/issues/254) supplies the pinned
  Northwind SQLite snapshot and 18 stable correctness scenarios over realistic
  joins, aggregates, subqueries, compound queries, common table expressions,
  decoding, CRUD, and rollback behavior.
- [#255](https://github.com/lukevanin/swiftql/issues/255) supplies 12 stable
  observation-stress cases and their evidence for concurrent writes,
  invalidation, delivery, cancellation, retries, and database isolation.
- [#132](https://github.com/lukevanin/swiftql/issues/132) is research only. Its
  internal prototype prepares static descriptors against the checked-in
  Northwind snapshot and emits a deterministic validation report. It ships no
  public validator, build plugin, macro, schema system, or new v1.3 API, and it
  does not expand the supported inventory total.

From the repository root, reproduce the validation and confirm that the report
matches the canonical inventory with:

```sh
python3 scripts/ci/sqlite-conformance-inventory.py check
```

## Pinned compiler support points

| Support point | GitHub runner | Platform toolchain | Swift | Runtime surface |
| --- | --- | --- | --- | --- |
| Swift 5.9 | `ubuntu-22.04` | official Swift 5.9.2 Linux | 5.9.2 | GRDB + OpenCombine + SQLite 3.53.3 |
| Swift 6.0 | `macos-15` | Xcode 16.2 (`16C5032a`) | 6.0 series | macOS 15.2 SDK + Combine |

The Swift 5.9 cells use GitHub's maintained Ubuntu 22.04 image and install the
exact official Swift 5.9.2 Ubuntu 22.04 archive from Swift.org. CI verifies its
detached signature against Swift's pinned signing-key fingerprint before
extracting it. The detached signature bytes also have a pinned SHA-256 digest
with bounded download retries. The signing key comes from Swift.org's published
bundle, with Swift's documented Ubuntu keyserver as an exact-fingerprint
fallback; the imported full fingerprint is checked before signature
verification. SwiftQL uses Apple's Combine on Apple platforms and the exact
OpenCombine 0.14.0 dependency on Linux. A small GRDB observation bridge
preserves positive-demand startup, independent subscriber state, error
delivery, and cancellation. The same publisher, retry-policy, codec, SQLite,
macro, benchmark, and full-suite tests execute on Linux; the lane does not
remove or skip the live-query surface.

Ubuntu 22.04's system SQLite 3.37 predates `UNIXEPOCH`, which is a required
capability in SwiftQL's real-SQLite conformance corpus. The Linux cells
therefore compile and link the official SQLite 3.53.3 amalgamation from an
immutable SQLite.org release URL. CI verifies SQLite's published SHA3-256
before extraction, enables the FTS5, math-function, and column-metadata
surfaces used by the package, and fails unless GRDB reports exact SQLite
3.53.3. Required SQL capabilities remain executable instead of being skipped
for the older runner library.

Every cell verifies the compiler series, runner OS family, architecture, and
target metadata, then reports the runner image version, dependency graph, and
SQLite runtime. Linux additionally verifies exact Swift 5.9.2, Ubuntu 22.04,
and the `x86_64-unknown-linux-gnu` target. macOS additionally verifies the exact
Xcode version, build, and SDK. Toolchain or image drift therefore fails instead
of silently redefining support.

GRDB 6.29.3's Swift 5.9 Linux condition assumes the linked SQLite exports its
optional snapshot symbols. The pinned amalgamation intentionally leaves that
optional API disabled, so the Linux cells consistently define GRDB's documented
`GRDBCUSTOMSQLITE` build path through SwiftPM's compiler override. This removes
only the unavailable snapshot API branch. The override delegates SwiftPM's
module-wrapping phase directly to the matching `swift-frontend` and remains next
to the selected compiler so SwiftPM loads that toolchain's index-store runtime.
The exact-version runtime probe, capability report, and full tests remain
authoritative for the pinned SQLite surface.

## Swift 6 series coverage

| Swift series | GitHub runner | Xcode | Swift | macOS SDK |
| --- | --- | --- | --- | --- |
| Swift 6.0 | `macos-15` | 16.2 (`16C5032a`) | 6.0 series | 15.2 |
| Swift 6.1 | `macos-15` | 16.4 (`16F6`) | 6.1 series | 15.5 |
| Swift 6.2 | `macos-15` | 26.3 (`17C529`) | 6.2.3 | 26.2 |
| Swift 6.3 | `macos-26` | 26.5 (`17F42`) | 6.3.2 | 26.5 |

The Swift 6.0 row is exercised by both pinned resolution cells above. Swift 6.1,
6.2, and 6.3 each have an additional release-blocking clean-resolution cell.
Every cell selects an exact Xcode version and build, verifies the compiler
series and SDK, resolves dependencies without either committed lockfile, runs
the first-party warning gate, executes the SQLite runtime probe, and runs the
complete test suite.

Apple builds continue to expose Apple's Combine types without source or ABI
changes. Linux builds import matching OpenCombine types and exercise the same
typed publisher contracts through real GRDB observations.

The compatibility test target contains a compile-time `#if swift(>=6.0)`
failure. Because `swift()` tests the active language mode, every Swift 6.0–6.3
job proves that SwiftQL remains in Swift 5 language mode.

## Dependency resolution

Each pinned compiler support point runs two independent dependency modes:

- **Committed resolution** uses the checked-in `Package.resolved` and fails if
  resolution changes it.
- **Clean resolution** exports the source into a new temporary directory,
  removes the exported lockfile, resolves from the manifest's declared ranges,
  and reports the resulting versions. It never modifies the checkout.

All four pinned support cells and all three additional Swift-series cells form
seven release-blocking compiler cells. Every cell builds every first-party
target and runs the complete test suite. No cell is
conditional, allowed to fail, or represented by a skipped job. The workflow
does not share build caches across compilers or resolution modes.

After resolution,
[`scripts/ci/report-resolved-dependencies.sh`](scripts/ci/report-resolved-dependencies.sh)
prints the complete graph and calls out the exact GRDB and SwiftSyntax versions.
`XLCompatibilityReportTests.testSQLiteRuntimeVersionIsReported` executes
`sqlite_version()` and `sqlite_source_id()` through GRDB, so CI reports the
SQLite library the package actually loaded rather than an unrelated `sqlite3`
command-line tool.

## Reproducing a cell

On Ubuntu 22.04 x86_64, install exact Swift 5.9.2 so its `swift` and `swiftc`
executables lead `PATH`. Build official SQLite 3.53.3 with the exact URL,
published SHA3-256, compiler flags, and library/include environment from
[`.github/workflows/swift.yml`](.github/workflows/swift.yml), then run the
environment check with the workflow values:

```sh
EXPECTED_PLATFORM=linux \
EXPECTED_SWIFT_SERIES=5.9 \
EXPECTED_SWIFT_VERSION=5.9.2 \
EXPECTED_SWIFT_COMMAND_MODE=path \
EXPECTED_IMAGE_OS=ubuntu22 \
EXPECTED_ARCHITECTURE=x86_64 \
EXPECTED_OS_ID=ubuntu \
EXPECTED_OS_VERSION_ID=22.04 \
EXPECTED_TARGET_TRIPLE=x86_64-unknown-linux-gnu \
scripts/ci/check-compatibility-environment.sh

swift package resolve
scripts/ci/report-resolved-dependencies.sh
scripts/ci/check-first-party-warnings.sh
swift test --filter XLCompatibilityReportTests
swift test --skip-build -v
```

To reproduce clean resolution without modifying the checkout:

```sh
clean_source="$(mktemp -d)"
git archive --format=tar HEAD | tar -xf - -C "$clean_source"
rm "$clean_source/Package.resolved"
cd "$clean_source"

swift package resolve
scripts/ci/report-resolved-dependencies.sh
scripts/ci/check-first-party-warnings.sh
swift test --filter XLCompatibilityReportTests
swift test --skip-build -v
```

The workflow is the canonical executable specification for both procedures.
Use the Xcode values in the Swift-series table to reproduce a 6.1, 6.2, or 6.3
cell. Those jobs use the same clean-source procedure and remove both lockfiles
before resolution.

## Downstream Swift 5 language-mode client

The pinned Swift 6.0 support point also builds and runs
[`IntegrationTests/Swift5Client`](IntegrationTests/Swift5Client) as an external
package. The fixture depends on the repository root through SwiftPM, imports
only the public `SwiftQL` product, expands representative `@SQLTable` and
`@SQLResult` macros, constructs a typed query, binds a named value, and executes
the query against a temporary SQLite database.

The fixture's manifest explicitly selects Swift 5 language mode. Compile-time
guards fail if it is built by a pre-Swift-6 compiler or if a Swift 6 compiler
silently enables Swift 6 language mode. Run its committed-resolution path with:

```sh
export DEVELOPER_DIR=/Applications/Xcode_16.2.app/Contents/Developer
SWIFTQL_DOWNSTREAM_SCRATCH_PATH="$(mktemp -d)" \
  scripts/ci/check-downstream-swift5-client.sh committed
```

The committed fixture lockfile must remain byte-identical to the repository
lockfile. The clean-resolution CI source export removes both lockfiles before
resolution, then runs the same checker in `clean` mode. To reproduce that path
without modifying the checkout:

```sh
clean_source="$(mktemp -d)"
git archive --format=tar HEAD | tar -xf - -C "$clean_source"
rm "$clean_source/Package.resolved"
rm "$clean_source/IntegrationTests/Swift5Client/Package.resolved"
cd "$clean_source"

xcrun swift package resolve
SWIFTQL_DOWNSTREAM_SCRATCH_PATH="$(mktemp -d)" \
  scripts/ci/check-downstream-swift5-client.sh clean
```

The checker performs a clean fixture build, requires exactly one runtime success
marker, and keeps build products outside the source tree. The compatibility
matrix runs both fixture resolution paths only in its pinned Swift 6.0 cells;
the ordinary package matrix continues to prove Swift 5.9 compiler support.

## First-party warnings as errors

Every supported compiler and dependency-resolution cell performs a clean build
of all first-party products and test targets, then treats SwiftQL-owned compiler
warnings as errors:

```sh
scripts/ci/check-first-party-warnings.sh
```

The script runs `swift build --build-tests -v` after cleaning its scratch
directory. It classifies complete diagnostic blocks by their source origin:
warnings from `Sources/`, `Tests/`, `Benchmarks/`, or first-party macro
expansions fail the build; dependency and toolchain diagnostics are printed in
separate sections; otherwise-unrecognized, non-excerpt warning headers fail
closed. This is intentionally a first-party gate instead of a global
`-warnings-as-errors` flag, which SwiftPM would also apply while compiling GRDB
and SwiftSyntax.

Set `SWIFTQL_SCRATCH_PATH` to keep build products in a chosen directory or to
reuse a dependency checkout across local worktrees:

```sh
SWIFTQL_SCRATCH_PATH=/path/to/swiftql/.build \
  scripts/ci/check-first-party-warnings.sh
```

## DocC generation

Build and inspect the static SwiftQL documentation site with the repository's
single non-mutating command:

```sh
./make-docs.sh
```

The command treats first-party DocC diagnostics as errors, writes the static
site to the ignored `docs/` directory, and validates the SwiftQL landing page
and all twelve source articles. Pass an existing external destination when a
separate output is useful, for example `./make-docs.sh /tmp/swiftql-docs`.
The command never stages or commits files.

Every Swift fence carries a marker for a named `XLDocumentationTests` scenario.
`SQLDocumentationCatalogTests` verifies the complete source file set, marker
registry, fence languages, and current API spellings. Generated documentation
is a build artifact and is not tracked in Git.

## Complete strict concurrency

The pinned Swift 6.0 support point also checks every first-party product and test
target with complete strict-concurrency diagnostics while remaining in Swift 5
language mode. Select Xcode 16.2, then run:

```sh
export DEVELOPER_DIR=/Applications/Xcode_16.2.app/Contents/Developer
scripts/ci/check-strict-concurrency.sh
```

The script performs a clean build with the equivalent command:

```sh
xcrun swift build --build-tests -v \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warn-concurrency
```

`--build-tests` is required: together with the package's products it covers all
seven first-party targets, including the benchmark executable and its library,
the macro implementation, and all test targets. Cleaning first prevents an
incremental no-op from appearing warning-free without invoking the compiler.

The strict-concurrency check uses the same provenance-aware, fail-closed
classifier as the ordinary warning gate. It has no first-party warning
allowlist: any ordinary or concurrency warning owned by SwiftQL blocks the
build. Automatic positive and negative classifier fixtures protect that
boundary before each build. The checker does not suppress compiler output.

For local worktrees that share an existing SwiftPM dependency checkout, set
`SWIFTQL_SCRATCH_PATH` before invoking the script:

```sh
SWIFTQL_SCRATCH_PATH=/path/to/swiftql/.build \
  scripts/ci/check-strict-concurrency.sh
```

## Diagnostics policy

Compiler and test failures in any support point or Swift-series lane are release
blockers.
The warning gates print first-party, dependency, toolchain, and unclassified
warnings in separate, searchable sections for every applicable cell:

- First-party warnings and unclassified warning headers are release blockers;
  there is no message-based exception list.
- Complete strict-concurrency warnings are release blockers in the pinned Swift
  6.0 cells; `check-strict-concurrency.sh` enforces that boundary after the
  standard build and tests.
- Verbose builds on both pinned compiler support points currently emit
  dependency-prefixed manifest compiler command lines for `swift-docc-plugin`,
  `grdb.swift`, `swift-syntax`, `OpenCombine`, and `swift-docc-symbolkit`. They
  are recorded
  separately under the gate's dependency-warning section. The structurally
  identified root `Package.swift` compiler invocation is reported as
  build-system output rather than a source warning. Exact resolved versions are
  reported earlier in each lane.

The matrix suppresses neither category.

## Swift 5.9 runner maintenance and recovery

The Swift 5.9 cells no longer use the hosted `macos-14` image that GitHub will
retire on 2 November 2026. They use maintained `ubuntu-22.04` runners and
install exact Swift 5.9.2 independently of Xcode. The archive and detached
signature use immutable release URLs, and signature verification requires the
pinned Swift project key fingerprint. The detached-signature SHA-256 rejects a
wrong or transient response body before GPG runs. The Swift.org signing-key
bundle is allowed to evolve for revocations and key rotation; if it is not
importable, the job retrieves only the pinned fingerprint from Swift's
documented Ubuntu keyserver and verifies that fingerprint before use. The
download receives no repository secret or persistent runner access. Each job
runs on a fresh GitHub-hosted VM with read-only contents permission.

Repository maintainers own the Swift.org release URLs, signature digest,
signing-key fingerprint and fallback, SQLite.org amalgamation URL and published
SHA3-256, OpenCombine pin, GRDB Linux compiler define, and environment pins.
Review them when GitHub changes the Ubuntu 22.04 image, Swift publishes a
signing-key revocation, SQLite publishes a security update, or the GRDB/SQLite
dependency changes.
A missing or invalid download, signature, compiler, distribution, runner-family,
architecture, target-triple, SQLite digest/version, dependency, link, or
OpenCombine bridge is a hard failure. Do not skip the lane or advance it to
Swift 6 as recovery. If the exact toolchain can no longer run on the hosted
image, move the same full-suite checks to a digest-pinned official Swift 5.9.2
container or another maintained provider before removing this strategy.
