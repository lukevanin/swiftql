# Issue 248 incremental-row candidate

This directory records the comparable candidate run for issue #248. It uses
the accepted comparison baseline in `../2026-07-18-mac16-8.json`; the checked-in
JSON and 84 raw files under `Runs/` are the source of truth for the numbers
below.

## Comparable setup

- Baseline SwiftQL revision: `6b417ef9d09ef8a68f787903cbc9ed31bfaad47b`
- Candidate SwiftQL revision: `51749252dc7f0022bdcfb50d1e4c59bd463347a4`
  from a clean checkout
- Candidate report: `2026-07-19-mac16-8-streaming.json`
- Fixture source revision: `jpwhite3/northwind-SQLite3@4f56e7f5906dfd23b25244c5bfe8fb5da6402efd`
- Compressed fixture SHA-256:
  `7f6c2731fc6f160d874f7d8ab9527066a8d54515e667948dec9ee05ef41dd6b5`
- Database SHA-256:
  `22c8a23a6db7720128c22c7082d0bc7922bd40c9e2c14da756300f21c178b43a`
- Schema/workload: all 16,143 `Orders` rows and the same 14 columns:
  `OrderID`, `CustomerID`, `EmployeeID`, `OrderDate`, `RequiredDate`,
  `ShippedDate`, `ShipVia`, `Freight`, `ShipName`, `ShipAddress`, `ShipCity`,
  `ShipRegion`, `ShipPostalCode`, and `ShipCountry`
- Build and lifecycle: release builds of both pinned dependency graphs, one
  implementation per fresh process, 10 warmups, 100 timed full fetches, three
  independent processes, rotated adjacent graph controls, and a 180-second
  post-build cooldown
- Timing boundary: complete SQLite stepping and typed output materialization;
  connection creation, warmups, and result checksums are outside timing
- Peak RSS: maximum `/usr/bin/time -l` process RSS across the three processes;
  it includes the executable, dependencies, connection, warmups, and retained
  typed output
- Machine: Mac16,8, Apple M4 Pro, 14 cores, 24 GiB, macOS 26.5.1, Xcode 26.5,
  Swift 6.3.2

All six paired-control drifts passed the harness's 5% comparability guard. The
candidate range was 0.11% to 3.18%.

## SwiftQL result

| Metric | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Median latency | 43.72 ms | 67.23 ms | +53.78% |
| p95 latency | 45.00 ms | 70.01 ms | +55.58% |
| Throughput | 369,240 rows/s | 240,104 rows/s | -34.97% |
| Process spread | 4.11% | 2.34% | -1.77 pp |
| Peak RSS | 51.2 MiB | 31.9 MiB | -37.63% |

The RSS reduction is the scale evidence for the intended bounded-intermediate-
memory behavior: the eager typed result array is still retained by the public
API, but the complete GRDB-row and normalized-value matrices no longer coexist
with it. Instrumented contract tests separately prove that early stop and a
decode error at row N do not step later rows.

This change is not a latency improvement. Cursor callback dispatch and per-row
normalization increased median and p95 latency materially on this workload.
That is a recorded limitation owned by follow-up issue #266; no
machine-dependent latency threshold is imposed by issue #248.

## Validation command

```sh
python3 Benchmarks/Comparison/summarize.py \
  --baseline Benchmarks/Comparison/2026-07-18-mac16-8.json \
  --candidate Benchmarks/Comparison/Issue248/2026-07-19-mac16-8-streaming.json
```
