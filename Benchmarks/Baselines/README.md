# Checked-in performance baseline

This directory contains the first reproducible SwiftQL performance baseline.
It establishes evidence for future profiling and regression investigation; it
does not define absolute CI performance thresholds.

## Method

All three reports were produced by independent release-mode processes from the
same clean repository revision:
`6645cc570228a1cec16c375384454fc2502a8f9f`.

Each measured phase used 50 warmup operations followed by 500 individually
timed operations. The harness records raw `UInt64` nanosecond samples using
`DispatchTime.uptimeNanoseconds`, retains each operation's real result beyond
the end timestamp, and verifies checksums outside the measured interval.
Reported p95 values use the nearest-rank method.

The four cases cover:

- an indexed, parameterized lookup returning one row;
- a representative two-join read returning 32 rows;
- a bounded update of exactly 64 rows, rolled back after every operation; and
- deterministic decoding of two wide rows spanning SQLite storage classes,
  booleans, and nullable values.

The six phase slots separate SwiftQL construction/rendering, uncached statement
preparation, same-connection statement-cache lookup, argument reset/binding,
SQLite execution/stepping, and the production SwiftQL/GRDB row-decoding path.
For each read case, execution and decoding both process the complete result set.
Row decoding is intentionally not applicable to the bounded write, leaving 23
measured case/phase combinations.

`cold_statement_preparation` means an uncached statement prepared on an already
open, schema-warm connection. It is not application startup or a cold database.

## Environment

- Machine: Mac16,8, Apple M4 Pro, arm64, 14 logical processors, 24 GiB memory
- OS: macOS 26.5.1 (25F80)
- Build/toolchain: release, Xcode 26.5 (17F42), Swift 6.3.2, macOS SDK 26.5
- GRDB: 6.29.3 at revision
  `2cf6c756e1e5ef6901ebae16576a7e4e4b834622`
- SQLite: 3.51.0, source ID
  `2025-06-12 13:14:41 f0ca7bba1c5e232e5d279fad6338121ab55af0c8c68c84cdfb18ba5114dcaapl`
- Database: temporary file-backed database, WAL journal mode,
  `synchronous = 1`, 4096-byte pages
- Fixture: 8 companies, 32 departments, 512 people, and 2 deterministic
  decode rows

Each JSON report also records the complete SQLite compile-option set, schema,
rendered SQL, typed parameters, query plans, fixture counts, phase boundaries,
raw samples, and checksums.

## Reports

- [Run 1](2026-07-17-mac16-8-run-1.json)
- [Run 2](2026-07-17-mac16-8-run-2.json)
- [Run 3](2026-07-17-mac16-8-run-3.json)

## Median results

Values are microseconds per operation. Spread is
`(maximum run median - minimum run median) / mean run median`. A high relative
spread on sub-microsecond phases can still represent only a few dozen
nanoseconds, so both relative and absolute values matter.

| Case | Phase | Run 1 | Run 2 | Run 3 | Spread |
| --- | --- | ---: | ---: | ---: | ---: |
| Simple lookup | Construction/render | 41.438 | 40.291 | 40.834 | 2.8% |
| Simple lookup | Uncached prepare | 14.063 | 14.209 | 14.167 | 1.0% |
| Simple lookup | Cache lookup | 0.250 | 0.250 | 0.250 | 0.0% |
| Simple lookup | Reset/bind | 0.167 | 0.167 | 0.208 | 22.7% |
| Simple lookup | Execute | 1.750 | 1.750 | 1.750 | 0.0% |
| Simple lookup | Decode | 9.292 | 9.500 | 9.459 | 2.2% |
| Multi-join read | Construction/render | 40.791 | 40.750 | 41.042 | 0.7% |
| Multi-join read | Uncached prepare | 20.000 | 19.875 | 20.209 | 1.7% |
| Multi-join read | Cache lookup | 0.291 | 0.250 | 0.250 | 15.5% |
| Multi-join read | Reset/bind | 0.167 | 0.167 | 0.167 | 0.0% |
| Multi-join read | Execute | 32.750 | 33.208 | 33.000 | 1.4% |
| Multi-join read | Decode | 149.687 | 155.521 | 154.188 | 3.8% |
| Bounded write | Construction/render | 11.209 | 10.250 | 11.334 | 9.9% |
| Bounded write | Uncached prepare | 3.792 | 3.500 | 3.875 | 10.1% |
| Bounded write | Cache lookup | 0.083 | 0.084 | 0.083 | 1.2% |
| Bounded write | Reset/bind | 0.167 | 0.167 | 0.167 | 0.0% |
| Bounded write | Execute | 22.375 | 22.208 | 24.375 | 9.4% |
| Deterministic decode | Construction/render | 23.583 | 24.084 | 21.792 | 9.9% |
| Deterministic decode | Uncached prepare | 10.375 | 10.542 | 10.375 | 1.6% |
| Deterministic decode | Cache lookup | 0.208 | 0.208 | 0.208 | 0.0% |
| Deterministic decode | Reset/bind | 0.125 | 0.125 | 0.125 | 0.0% |
| Deterministic decode | Execute | 1.166 | 1.250 | 1.208 | 7.0% |
| Deterministic decode | Decode | 11.750 | 13.000 | 12.875 | 10.0% |

## Assessment

Two SwiftQL-controlled phases are material enough to justify focused profiling:

- Construction and rendering costs 40.291–41.438 microseconds for the simple
  lookup and 40.750–41.042 microseconds for the multi-join read. Follow-up
  [#166](https://github.com/lukevanin/swiftql/issues/166) owns profiling and
  reducing that overhead without weakening SQL correctness.
- Production row decoding costs 9.292–9.500 microseconds for the simple
  one-row result, compared with 1.750 microseconds for SQLite execution;
  149.687–155.521 microseconds for the complete 32-row join result, compared
  with 32.750–33.208 microseconds for execution; and 11.750–13.000 microseconds
  for the complete two-row wide result, compared with 1.166–1.250 microseconds
  for execution. Follow-up
  [#167](https://github.com/lukevanin/swiftql/issues/167) owns attribution and
  optimization of that path.

The 32.750–33.208 microsecond multi-join execution and 22.208–24.375
microsecond bounded-write execution values establish workload references, but
do not by themselves demonstrate a SwiftQL defect. Uncached preparation spans
3.500–20.209 microseconds and crosses SQLite/GRDB boundaries; it should be
profiled before assigning an optimization issue. Same-connection cache lookup
and reset/binding remain at or below 0.291 and 0.208 microseconds respectively,
so this baseline does not justify work on either phase.

Future comparisons should use the raw reports and matching case/phase
boundaries, and should record changed hardware, toolchain, dependency, SQLite,
schema, or fixture conditions rather than treating these numbers as portable
limits.
