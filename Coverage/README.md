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
directories. The reproducibility identity requires the same source commit,
clean-tree state, toolchain and dependency provenance, coverage command,
filtering metadata, target membership, included and allowed-source manifests,
and per-file, per-target, and overall static line/function/region counts.

Covered and uncovered hit counters, their derived percentages, and the ranked
largest-gap list are retained as diagnostic evidence but are not part of that
identity. Concurrent tests can legitimately merge a different number of hits
into two otherwise equivalent LLVM profiles. The gate records whether the
complete dynamic reports matched, but it does not turn that observation into a
percentage threshold or source-selection failure.
`reproducibility.json` preserves `normalized_reports_match` as the exact-report
equality observation, so it can be `false` while
`reproducibility_identity_matches` remains `true` and the gate succeeds.

## Filtering contract

The raw SwiftPM LLVM JSON contains dependencies, tests, build products, and
generated files. `scripts/ci/source-coverage-report.py` includes only tracked
`.swift` files found under the target roots declared in
`scripts/ci/source-coverage-config.json`:

- `Sources/SwiftQL`
- `Sources/SwiftQLCore`
- `Sources/SQLMacros`

Tests, temporary fixtures, benchmarks, package checkouts, build products, and
generated macro expansion files therefore cannot contribute to the reported
first-party totals. Fixture tests inject each excluded category and verify that
the totals and manifest remain unchanged.

LLVM does not currently report executable regions for `Sources/SwiftQL/SQL.swift`,
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

Then run two real package-test captures with independent clean output and
scratch directories and compare their reproducibility identities:

```bash
coverage_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftql-coverage.XXXXXX")"

SWIFTQL_COVERAGE_SCRATCH_PATH="$coverage_root/build-1" \
  scripts/ci/run-source-coverage.sh "$coverage_root/run-1"

SWIFTQL_COVERAGE_SCRATCH_PATH="$coverage_root/build-2" \
  scripts/ci/run-source-coverage.sh "$coverage_root/run-2"

scripts/ci/verify-source-coverage-reproducibility.sh \
  "$coverage_root/run-1" \
  "$coverage_root/run-2" \
  "$coverage_root/run-1/reproducibility.json"
```

The output directory contains:

- `llvm-coverage.json`: SwiftPM's unfiltered machine-readable LLVM export;
- `llvm-coverage.lcov`: the same profile exported in standard LCOV form;
- `first-party-coverage.json`: normalized per-target and per-file evidence;
- `included-sources.txt`: deterministic source manifest used by the two-run check;
- `allowed-uninstrumented-sources.txt`: explicit zero-region exceptions;
- `summary.md`: the same concise target totals shown in the GitHub job summary;
- toolchain, dependency, command, source-commit, and test-log provenance.

After a successful comparison, the first output also contains
`reproducibility.json` and a copy of the second run's manifest as
`repeated-included-sources.txt`. Both run directories retain their complete raw
JSON, LCOV, normalized report, summary, and test log.

Use a new output directory for every run. The script refuses to overwrite a
prior report and refuses to assign a commit to dirty source content. During
coverage-tool development only, `SWIFTQL_ALLOW_DIRTY_COVERAGE=1` permits a
diagnostic report marked `dirty`; the two-run reproducibility verifier rejects
such reports.

## Baselines and follow-ups

The [initial pinned Xcode 16.2 baseline](Baselines/2026-07-17-xcode-16.2-swift-6.0/README.md)
records two byte-identical clean reports from source commit
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
