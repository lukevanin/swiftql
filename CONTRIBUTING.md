# Contributing to SwiftQL

## Local setup

SwiftQL is a Swift package. You need:

- **Xcode 15** or later (macOS), or the **Swift 5.9** toolchain or later
  (Linux). The CI matrix covers Swift 5.9, 6.0, 6.1, 6.2, and 6.3.
- **macOS 13** or later (for macOS builds). iOS 16 or later is the minimum
  supported iOS version.

Clone and resolve dependencies:

```sh
git clone https://github.com/lukevanin/swiftql.git
cd swiftql
swift package resolve
```

Build the package:

```sh
swift build
```

## Running the tests

Run the full test suite:

```sh
swift test
```

### Test directory layout

The `Tests/` directory contains several distinct kinds of targets, and the split
is not obvious at first glance:

| Directory | Kind | Purpose |
|---|---|---|
| `Tests/SwiftQLCoreTests/` | `testTarget` | Unit tests for the GRDB-free `SwiftQLCore` contract layer (dialect contracts, static query descriptors, invocation bindings). |
| `Tests/SQLMacrosTests/` (inside `Tests/`) | `testTarget` | Tests for the `@SQLTable` and `@SQLResult` macro expansions. |
| `Tests/SQLTests/` | `testTarget` | Integration tests for the full `SwiftQL` API — queries, joins, expressions, aggregates, and the GRDB driver. |
| `Tests/SwiftQLCodecIntegrationTests/` | `testTarget` | Codec integration tests isolated from `SQLTests` so Foundation codecs do not inherit its retroactive literal conformances. |
| `Tests/SwiftQLNorthwindFixturesTests/` | `testTarget` | Fixture-contract tests that verify the immutable Northwind database fixture. |
| `Tests/SwiftQLSQLiteCombinatorialSupportTests/` | `testTarget` | Tests for the constraint-aware combinatorial SQL generator and real-SQLite replay support. |
| `Tests/CompileFail/` | negative tests | Swift files that **must not compile**. Each file exercises a type-system constraint (e.g. `HavingWithoutGroupBy.swift`). These are checked by CI separately from the `swift test` run. |
| `Tests/SwiftQLSQLiteConformanceFixtures/` | fixture library | A test-only library target (not a test target) that provides SQLite value cases shared across the core and integration tests. |
| `Tests/SwiftQLNorthwindFixtures/` | fixture library | A test-only library target that bundles the Northwind SQLite database for semantic corpus tests. |
| `Tests/SwiftQLSQLiteCombinatorialSupport/` | support library | A test-only library target for the combinatorial SQL generator. |

Benchmark and profiling executables live under `Benchmarks/` and have their own
test target (`SwiftQLBenchmarkTests`). Research targets live under `Research/`.
Neither belongs to the package's public products.

## Code style

SwiftQL follows the conventions of the existing source. A few things worth
noting before you send a patch:

- **No raw query strings.** SQL is expressed through the typed DSL; string
  literals appear only where the abstraction deliberately exposes them (e.g.
  custom SQL functions, raw `SQLFragment` values).
- **No ORM-style indirection.** Keep the relational model visible; do not hide
  it behind object-graph abstractions.
- **Documentation examples are executable.** Code snippets in the DocC guides
  and this README are backed by test scenarios. New public API should include a
  corresponding test rather than a documentation-only example.
- **Swift language mode.** The package uses Swift 5 language mode across all
  five supported compiler series. Do not opt individual files or modules into
  Swift 6 language mode.
- **No unused imports.** Keep the dependency surface of each target narrow.

## Branch naming

| Purpose | Pattern | Example |
|---|---|---|
| Agent-driven issue work | `agent/issue-NNN` | `agent/issue-405` |
| Human-driven feature or fix | `claude/<kebab-description>` | `claude/add-cross-join` |
| Milestone base branch | `version/x.y.z` | `version/1.5.0` |
| Release-preparation (changelog date) | `release/vX.Y.Z-changelog` | `release/v1.4.1-changelog` |
| Experiment or spike | `experiment/<name>` | `experiment/build-validation` |

## Commit messages

Write commit messages in the imperative mood with a concise subject line.
Reference related GitHub issues in parentheses at the end of the subject when
relevant:

```
Add NATURAL JOIN and USING clause support (#NNN)
Fix off-by-one in pagination offset binding (#NNN)
```

Multi-paragraph bodies are fine for context that doesn't fit in the subject.
Avoid restating what the diff already shows.

## Pull request process

1. Open a PR from your branch against `main` (or the milestone base branch
   `version/x.y.z` when the milestone owns a dedicated branch).
2. Request a Copilot review.
3. Address every actionable Copilot comment — either fix the code or add a
   brief explanation of why not in a reply. Push the updated commits and
   re-request review until Copilot has no further useful feedback.
4. A human maintainer merges the PR. PRs are never self-merged.

Patch releases that land on a preparation branch (`release/vX.Y.Z-changelog`)
must use a **merge commit** when merging into `main`. Squash and rebase merges
orphan the branch commit and break the release workflow's reachability gate.

## Releases

Releasing SwiftQL involves an exact-tag validation pipeline, a seven-cell Swift
compatibility matrix, immutable release settings, and a protected tag ruleset.
That process is documented in full in [RELEASING.md](RELEASING.md). Do not
publish a release directly through the GitHub API — publication is owned by the
tag-triggered workflow (`.github/workflows/release.yml`).
