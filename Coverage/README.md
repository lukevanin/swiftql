# SwiftQL Source Coverage

SwiftQL records first-party source coverage before the v1.2 dialect, codec,
binding, and descriptor refactors. Coverage is diagnostic evidence: it does not
replace SQLite prepare/execution tests, macro expansion and diagnostic tests, or
establish an arbitrary percentage release gate.

## Pinned CI environment

Source coverage runs inside the `Swift 6.0 / committed resolution` cell of the
compatibility job in `.github/workflows/swift.yml`, on `macos-15` with Xcode
16.2 (`DEVELOPER_DIR=/Applications/Xcode_16.2.app/Contents/Developer`) and the
committed `Package.resolved`. That cell runs the full test suite once, under
coverage, in place of its plain test run. The capture records the source
commit and clean-tree state; Xcode, Swift, SDK, `llvm-cov`, and
`llvm-profdata` versions; runner platform and architecture; dependency graph;
package-resolution digest; and exact coverage command in its retained
artifact.

The cell captures and verifies coverage on every event, pull requests
included, so a change that breaks the capture fails before the merge. Only
pushes to `main` and release runs upload the report to Codecov. A pull
request's capture records the merge commit GitHub tested, which is not a
durable commit, so treat pull-request artifacts as diagnostics only.

### Verifying the source selection

Coverage used to be a job of its own that ran the full suite twice, in
independent scratch directories, and compared the two reports. The comparison
never included hit counters, so the second run re-proved only the source
selection and the provenance around it. Both of those follow from the checked
out tree and the coverage config, so the second run is gone.
`scripts/ci/verify-source-coverage-reproducibility.sh` now checks the single
capture against a selection it derives itself:

- it re-enumerates tracked `.swift` files under each configured target root
  with `git ls-files`, with the same enumeration the report uses, and requires
  the capture's `included-sources.txt` and
  `allowed-uninstrumented-sources.txt` to equal that derivation byte for byte;
- it requires the capture's target names and source roots to equal the config;
- it requires every configured uninstrumented allowance to be a tracked file;
- it requires the recorded source commit to be the checked-out `HEAD`, the
  recorded `Package.resolved` digest to match the file, and the capture to be
  of a clean tree; and
- it validates the report's structure, including per-file, per-target, and
  overall static line, function, and region counts that must sum consistently.

Covered and uncovered hit counters, their derived percentages, and the ranked
largest-gap list are retained as diagnostic evidence but are not verified.
Concurrent tests can legitimately merge a different number of hits into two
otherwise equivalent LLVM profiles, which is why they never formed part of the
old two-run identity either. The static counts are now checked for internal
consistency within the one capture rather than compared across two runs; a
compiler that reported different static counts for the same source on a
second run would no longer be caught. No percentage threshold is enforced.

`reproducibility.json` records the result with `schema_version` 2 and
`coverage_captures` 1. Its `*_matches*` fields are all `true` whenever the gate
succeeds. The checked-in 2026-07-17 baseline predates this and keeps its
`schema_version` 1 two-run record, including `normalized_reports_match`.

## Filtering contract

The raw SwiftPM LLVM JSON contains dependencies, tests, build products, and
generated files. `scripts/ci/source-coverage-report.py` includes only tracked
`.swift` files found under the target roots declared in
`scripts/ci/source-coverage-config.json`:

- `Sources/SQLMacros`
- `Sources/SwiftQL`
- `Sources/SwiftQLCore`
- `Sources/SwiftQLSQLiteBuildValidationManifest`
- `Sources/SwiftQLSQLiteBuildValidationValidator`
- `Sources/SwiftQLSQLiteIndexAdvisor`

Tests, temporary fixtures, benchmarks, package checkouts, build products, and
generated macro expansion files therefore cannot contribute to the reported
first-party totals. Fixture tests inject each excluded category and verify that
the totals and manifest remain unchanged.

## Target membership

Every tracked `.swift` file under `Sources/` must sit inside one of those target
roots or inside an `excluded_source_roots` entry of the same config. An excluded
root records a directory the coverage test binary never links, with the reason.
The two executable targets are excluded this way:

- `Sources/SwiftQLSQLiteBuildValidationValidatorCLI`
- `Sources/SwiftQLSQLiteIndexAdvisorCLI`

`scripts/ci/check-source-target-membership.py` enforces this rule. It needs only
`git ls-files` and the config, so the Linux `Release tooling fixtures` job runs it
on every pull request. A pull request that adds a new target without a config
entry therefore fails before the merge, not in the post-merge coverage job. The
check also fails when an excluded root no longer holds a tracked Swift file.

Run it locally with:

```bash
python3 scripts/ci/check-source-target-membership.py
```

The coverage report itself no longer checks membership. It still rejects LLVM
coverage for a file inside a configured root that git does not track.

Swift files inside a `.docc` catalog are excluded as well, even though they sit
under a configured target root. SwiftPM copies a documentation catalog as a
resource bundle rather than compiling what is in it, so those files are the code
snapshots the DocC tutorial displays through `@Code(file:)` and LLVM never
reports a region for one. `Tests/SQLTests/SQLDocumentationCatalogTests.swift`
checks each snapshot against the compiled walkthrough it was cut from, which is
where their type checking comes from.

LLVM does not currently report executable regions for `Sources/SwiftQL/SQL.swift`,
`Sources/SwiftQL/SQLRowMacro.swift`, `Sources/SwiftQL/SQLRowResult.swift`,
`Sources/SwiftQL/SQLScalarResult.swift`, or the import-only
`Sources/SwiftQL/SwiftQLCore.swift` compatibility shim. They are explicit
exceptions in the configuration. Any other production source missing from LLVM
data fails the report, and an exception that starts reporting coverage also
fails until the stale allowance is removed.

## Local reproduction

Run the fixture tests first:

```bash
python3 scripts/ci/test-source-coverage-report.py
```

Then run one real package-test capture into a clean output directory and
verify its source selection against `git ls-files` and the coverage config:

```bash
coverage_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-coverage.XXXXXX")"

SWIFTQL_COVERAGE_SCRATCH_PATH="$coverage_root/build" \
  scripts/ci/run-source-coverage.sh "$coverage_root/capture"

scripts/ci/verify-source-coverage-reproducibility.sh \
  "$coverage_root/capture" \
  "$coverage_root/capture/reproducibility.json"
```

The output directory contains:

- `llvm-coverage.json`: SwiftPM's unfiltered machine-readable LLVM export;
- `llvm-coverage.lcov`: the same profile exported in standard LCOV form;
- `first-party-coverage.json`: normalized per-target and per-file evidence;
- `included-sources.txt`: deterministic source manifest the verifier checks;
- `allowed-uninstrumented-sources.txt`: explicit zero-region exceptions;
- `summary.md`: the same concise target totals shown in the GitHub job summary;
- toolchain, dependency, command, source-commit, and test-log provenance.

After a successful verification, the output also contains
`reproducibility.json` and the verifier's own derivation as
`derived-included-sources.txt` and
`derived-allowed-uninstrumented-sources.txt`, so the retained artifact shows
both sides of the comparison.

Use a new output directory for every run. The script refuses to overwrite a
prior report and refuses to assign a commit to dirty source content. During
coverage-tool development only, `SWIFTQL_ALLOW_DIRTY_COVERAGE=1` permits a
diagnostic report marked `dirty`; the verifier rejects such reports.

## Baselines and follow-ups

The [initial pinned Xcode 16.2 baseline](Baselines/2026-07-17-xcode-16.2-swift-6.0/README.md),
captured under the former two-run procedure, records two byte-identical clean
reports from source commit
`9152d8409aa55df5bc96e9c74411b3c4fb166429`, including the source manifests,
resolved dependencies, full toolchain provenance, target totals, retained
artifact identity, and two-run verdict.

The first baseline reports SQLMacros at 2164/2218 lines and 154/157 functions,
and SwiftQL at 2822/3628 lines and 703/939 functions. Those numbers rank
follow-up candidates; they are not an automatic failure threshold.

Material non-duplicate gaps are tracked by
[#195](https://github.com/lukevanin/swiftql/issues/195) for the public fluent
`INSERT ... SELECT` transition matrix and
[#194](https://github.com/lukevanin/swiftql/issues/194) for QueryBuilder's
missing-`FROM` rejection. Both issues carry an explicit priority and the v1.2
milestone so coverage work cannot silently expand unrelated architecture PRs.
