# Northwind correctness fixture

`northwind.db` is the immutable real-database correctness fixture for SwiftQL
issue #254. It is deliberately small and deterministic. It is not a throughput,
concurrency, or production-scale benchmark.

## Pinned identity

- Repository: `Northwind-swift/NorthwindSQLite.swift`
- Commit: `865de0872e61692a49cd6069cd2df8f9ac04541e`
- Upstream path: `dist/northwind.db`
- Database SHA-256: `cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8`
- Database size: 602,112 bytes
- License: MIT; the verbatim notice is retained in `LICENSE.txt`

The machine-readable identity, expected schema, row sentinels, and immutable-use
policy live in `PROVENANCE.json`. The Swift fixture helper independently embeds
the release gates so a changed provenance file cannot make changed database
bytes pass validation.

The canonical resource is opened with SQLite read-only and `query_only` modes.
Tests that perform CRUD, transaction, rollback, or observation work must use
`NorthwindFixture.withTemporaryCopy`. That helper creates a UUID-named directory,
validates the copy before use, closes its pool, and removes the database plus any
WAL/SHM sidecars after the closure. After a successful closure, cleanup failures
are surfaced to the caller. If the closure throws, that body error remains primary
while close and removal are attempted on a best-effort basis.

## Expected contents

Validation requires `PRAGMA integrity_check` to return `ok`, the exact 13
application tables and 17 views recorded in `PROVENANCE.json`, and these row
sentinels:

- `Customers`: 93
- `Orders`: 830
- `Order Details`: 2,155
- `Products`: 77
- order 10248: three detail rows totalling 440.0

## Updating the fixture

Fixture updates are intentional review events, never runtime downloads:

1. Select and record an immutable upstream commit. Do not use a branch, tag that
   can move, or the upstream unseeded/current-date population script.
2. Download `dist/northwind.db` and `LICENSE` from that exact commit outside the
   test run.
3. Verify the database SHA-256, byte count, `PRAGMA integrity_check`, exact table
   and view sets, fixed row counts, and the order-10248 sentinel independently.
4. Replace `northwind.db` and `LICENSE.txt`, then update `PROVENANCE.json` and the
   matching constants in `NorthwindFixture.swift` in one reviewed change.
5. Run the focused fixture tests and full Swift test suite from a clean checkout.
6. Review licensing, fixture immutability, resource loading on every supported
   platform, and whether semantic expectations need their own issue updates.

Do not substitute the separately licensed and checksummed
`Benchmarks/Comparison/Fixtures/northwind-performance.sqlite.gz`. That fixture
contains 16,143 orders and exists only for the performance methodology in #250.
