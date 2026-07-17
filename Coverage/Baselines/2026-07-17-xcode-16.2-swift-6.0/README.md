# Initial Xcode 16.2 source-coverage baseline

This directory is the compact, checked-in baseline produced by the dedicated
Swift 6 coverage lane for issue [#189](https://github.com/lukevanin/swiftql/issues/189).
The raw LLVM JSON, LCOV, and test logs remain in the retained workflow artifact
rather than in Git.

## Provenance

- Source commit: `9152d8409aa55df5bc96e9c74411b3c4fb166429`
- Source tree: clean
- Workflow: [Swift compatibility run 118](https://github.com/lukevanin/swiftql/actions/runs/29580545409)
- Artifact: [ID 8406963181](https://github.com/lukevanin/swiftql/actions/runs/29580545409/artifacts/8406963181),
  `swiftql-source-coverage-9152d8409aa55df5bc96e9c74411b3c4fb166429-1`
- Artifact SHA-256: `c090061ab72580296bd0e6600bb868209181c661fb251c70c096c11d3325dc56`
- Artifact retention: created 2026-07-17; scheduled to expire 2026-08-16
- Runner image: `macos15 20260715.0234.1`, arm64
- Xcode: 16.2 (`16C5032a`)
- Swift: 6.0.3
- macOS SDK: 15.2
- Apple LLVM coverage tools: 16.0.0 (`clang-1600.0.26.6`)
- Command: `xcrun swift test --scratch-path <scratch-path> --enable-code-coverage`
- `Package.resolved` SHA-256: `69015064d53cbf9f4682b3d690bb34fcb59f9fc229f9e20f898b6399fb6c75f6`
- Included-source digest: `af252c4cb1d2aa86edc0b301d1f0334b6e2032962b5a2b372899b79ed5645fe2`

Two clean runs used independent SwiftPM scratch directories. Their normalized
reports, included-source manifests, explicit uninstrumented-source manifests,
toolchains, commands, source commits, and dependency-resolution digests were
identical.

## First-party totals

| Target | Instrumented sources | Allowed uninstrumented | Lines | Functions |
| --- | ---: | ---: | ---: | ---: |
| SQLMacros | 4 | 0 | 2164/2218 (97.57%) | 154/157 (98.09%) |
| SwiftQL | 45 | 2 | 2822/3628 (77.78%) | 703/939 (74.87%) |

The two allowed uninstrumented sources are `Sources/SwiftQL/SQL.swift` and
`Sources/SwiftQL/SQLScalarResult.swift`; the pinned LLVM export reports no
executable regions for them. The reporter fails if another tracked production
source disappears or either allowance becomes stale.

These totals are evidence, not a percentage gate. Real SQLite execution,
compiler diagnostics, and semantic assertions remain the acceptance criteria
for production changes.

## Checked-in files

- `first-party-coverage.json`: normalized target and per-file metrics plus full
  toolchain and filtering provenance;
- `included-sources.txt` and `repeated-included-sources.txt`: the two matching
  first-party source manifests;
- `allowed-uninstrumented-sources.txt`: the explicit zero-region exceptions;
- `reproducibility.json`: the two-clean-run verdict and shared provenance;
- `resolved-dependencies.txt`: the resolved dependency graph;
- `summary.md`: the concise CI table and ranked uncovered files.

## Gap triage

The baseline produced two non-duplicate atomic follow-ups in milestone v1.2:

- [#195](https://github.com/lukevanin/swiftql/issues/195) (P3) covers the 32
  zero-count public fluent `INSERT ... SELECT` transitions with exact rendering
  and real SQLite execution.
- [#194](https://github.com/lukevanin/swiftql/issues/194) (P4) covers
  `QueryBuilder`'s documented missing-`FROM` rejection path.

Other large uncovered areas already have direct owners, notably
[#131](https://github.com/lukevanin/swiftql/issues/131) for dialect/driver
boundaries, [#82](https://github.com/lukevanin/swiftql/issues/82) for immutable
invocation bindings, and [#191](https://github.com/lukevanin/swiftql/issues/191)
for generated combinatorial SQLite conformance cases. Duplicate umbrella issues
were intentionally not created.
