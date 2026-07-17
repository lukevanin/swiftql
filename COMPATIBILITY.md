# Compiler compatibility

SwiftQL 1.x keeps `swift-tools-version: 5.9` and supports two explicit compiler
points. The Swift 6 compiler runs the package in Swift 5 language mode; SwiftQL
does not opt into Swift 6 language mode.

| Support point | GitHub runner | Xcode | Swift | macOS SDK |
| --- | --- | --- | --- | --- |
| Swift 5.9 | `macos-14` | 15.2 (`15C500b`) | 5.9 series | 14.2 |
| Swift 6.0 | `macos-15` | 16.2 (`16C5032a`) | 6.0 series | 15.2 |

The workflow selects Xcode with an exact `DEVELOPER_DIR`, verifies the Xcode
version and build number, verifies the compiler family and SDK, and reports the
complete compiler, OS, runner image, and architecture details. A runner image
update that removes or changes a selected toolchain therefore fails instead of
silently redefining support. The compatibility test target also contains a
compile-time `#if swift(>=6.0)` failure, which proves that the Swift 6.0 compiler
is still compiling in Swift 5 language mode.

## Dependency resolution

Each compiler runs two independent dependency modes:

- **Committed resolution** uses the checked-in `Package.resolved` and fails if
  resolution changes it.
- **Clean resolution** exports the source into a new temporary directory,
  removes the exported lockfile, resolves from the manifest's declared ranges,
  and reports the resulting versions. It never modifies the checkout.

All four cells run `swift build` and the complete test suite. No cell is
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

Select the same Xcode and run the environment check with the values from
[`.github/workflows/swift.yml`](.github/workflows/swift.yml):

```sh
export DEVELOPER_DIR=/Applications/Xcode_15.2.app/Contents/Developer
EXPECTED_XCODE_VERSION=15.2 \
EXPECTED_XCODE_BUILD=15C500b \
EXPECTED_SWIFT_SERIES=5.9 \
EXPECTED_SDK_VERSION=14.2 \
EXPECTED_DEVELOPER_DIR="$DEVELOPER_DIR" \
scripts/ci/check-compatibility-environment.sh

xcrun swift package resolve
scripts/ci/report-resolved-dependencies.sh
scripts/ci/check-first-party-warnings.sh
xcrun swift test --filter XLCompatibilityReportTests
xcrun swift test --skip-build -v
```

To reproduce clean resolution without modifying the checkout:

```sh
clean_source="$(mktemp -d)"
git archive --format=tar HEAD | tar -xf - -C "$clean_source"
rm "$clean_source/Package.resolved"
cd "$clean_source"

xcrun swift package resolve
scripts/ci/report-resolved-dependencies.sh
scripts/ci/check-first-party-warnings.sh
xcrun swift test --filter XLCompatibilityReportTests
xcrun swift test --skip-build -v
```

The workflow is the canonical executable specification for both procedures.

## Downstream Swift 5 language-mode client

The supported Swift 6 compiler also builds and runs
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

## Complete strict concurrency

SwiftQL's supported Swift 6 compiler also checks every first-party product and
test target with complete strict-concurrency diagnostics while remaining in
Swift 5 language mode. Select the pinned Xcode 16.2 support point, then run:

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

Compiler and test failures in either support point are release blockers.
The warning gates print first-party, dependency, toolchain, and unclassified
warnings in separate, searchable sections for every applicable cell:

- First-party warnings and unclassified warning headers are release blockers;
  there is no message-based exception list.
- Complete strict-concurrency warnings are release blockers in the Swift 6.0
  lanes; `check-strict-concurrency.sh` enforces that boundary after the standard
  build and tests.
- Verbose builds on both support points currently emit dependency-prefixed
  manifest compiler command lines for `swift-docc-plugin`, `grdb.swift`,
  `swift-syntax`, and `swift-docc-symbolkit`. They are recorded separately under
  the gate's dependency-warning section. The structurally identified root
  `Package.swift` compiler invocation is reported as build-system output rather
  than a source warning. Exact resolved versions are reported earlier in each
  lane.

The matrix suppresses neither category.

## Hosted runner lifetime

GitHub has announced that hosted `macos-14` runners will be retired on
2 November 2026. Later hosted macOS images do not include Xcode 15, so replacing
the real Swift 5.9 lane requires a maintained self-hosted environment or another
pinned toolchain strategy. [#164](https://github.com/lukevanin/swiftql/issues/164)
tracks that migration; the Swift 5.9 gate must not be removed or advanced
silently.
