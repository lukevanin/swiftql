# SwiftQL Source Coverage

SwiftQL records first-party source coverage before the v1.2 dialect, codec,
binding, and descriptor refactors. Coverage is diagnostic evidence: it does not
replace SQLite prepare/execution tests, macro expansion and diagnostic tests, or
establish an arbitrary percentage release gate.

## Pinned CI environment

The `Swift 6.0 / first-party source coverage` job in
`.github/workflows/swift.yml` runs on `macos-15` with Xcode 16.2
(`DEVELOPER_DIR=/Applications/Xcode_16.2.app/Contents/Developer`) and the
committed `Package.resolved`. The job records the source commit and clean-tree
state; Xcode, Swift, SDK, `llvm-cov`, and `llvm-profdata` versions; runner
platform and architecture; dependency graph; package-resolution digest; and
exact coverage command in its retained artifact.

Every coverage job performs two clean builds in independent SwiftPM scratch
directories. The job fails if their normalized first-party source manifests
differ.

## Filtering contract

The raw SwiftPM LLVM JSON contains dependencies, tests, build products, and
generated files. `scripts/ci/source-coverage-report.py` includes only tracked
`.swift` files found under the target roots declared in
`scripts/ci/source-coverage-config.json`:

- `Sources/SwiftQL`
- `Sources/SQLMacros`

Tests, temporary fixtures, benchmarks, package checkouts, build products, and
generated macro expansion files therefore cannot contribute to the reported
first-party totals. Fixture tests inject each excluded category and verify that
the totals and manifest remain unchanged.

LLVM does not currently report executable regions for `Sources/SwiftQL/SQL.swift`
or `Sources/SwiftQL/SQLScalarResult.swift`. They are explicit exceptions in the
configuration. Any other production source missing from LLVM data fails the
report, and an exception that starts reporting coverage also fails until the
stale allowance is removed.

## Local reproduction

Run the fixture tests first:

```bash
python3 scripts/ci/test-source-coverage-report.py
```

Then run the real package tests with coverage into a clean output and scratch
directory:

```bash
SWIFTQL_COVERAGE_SCRATCH_PATH="${TMPDIR}/swiftql-coverage-build" \
  scripts/ci/run-source-coverage.sh \
  "${TMPDIR}/swiftql-coverage-report"
```

The output directory contains:

- `llvm-coverage.json`: SwiftPM's unfiltered machine-readable LLVM export;
- `llvm-coverage.lcov`: the same profile exported in standard LCOV form;
- `first-party-coverage.json`: normalized per-target and per-file evidence;
- `included-sources.txt`: deterministic source manifest used by the two-run check;
- `allowed-uninstrumented-sources.txt`: explicit zero-region exceptions;
- `summary.md`: the same concise target totals shown in the GitHub job summary;
- toolchain, dependency, command, source-commit, and test-log provenance.

Use a new output directory for every run. The script refuses to overwrite a
prior report and refuses to assign a commit to dirty source content. During
coverage-tool development only, `SWIFTQL_ALLOW_DIRTY_COVERAGE=1` permits a
diagnostic report marked `dirty`; the two-run reproducibility verifier rejects
such reports.

## Baselines and follow-ups

The initial pinned Xcode 16.2 baseline is stored under `Coverage/Baselines/`.
Large uncovered areas are ranked as follow-up candidates, not treated as an
automatic failure. Material gaps are tracked in linked atomic GitHub issues so
coverage work cannot silently expand the architecture PRs.
