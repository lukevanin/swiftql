# Northwind performance fixture

`northwind-performance.sqlite.gz` is the authoritative fixture for the
cross-library full-fetch baseline. Its provenance is the MIT-licensed
[`jpwhite3/northwind-SQLite3`](https://github.com/jpwhite3/northwind-SQLite3)
database at revision `4f56e7f5906dfd23b25244c5bfe8fb5da6402efd`, expanded by that
project's `src/populate.py` before this snapshot was captured.

The population script is nondeterministic: it uses unseeded random values and
the current date. The revision alone therefore cannot recreate these exact
database bytes. The committed compressed snapshot and its checksums are the
source of truth:

- compressed SHA-256: `7f6c2731fc6f160d874f7d8ab9527066a8d54515e667948dec9ee05ef41dd6b5`
- database SHA-256: `22c8a23a6db7720128c22c7082d0bc7922bd40c9e2c14da756300f21c178b43a`
- uncompressed size: 24,412,160 bytes
- SQLite page size/count: 4,096 bytes / 5,960 pages
- `Orders` rows/columns: 16,143 / 14

The fixture is deliberately separate from the pinned 830-order correctness
corpus tracked by issue #254. The original Northwind license is retained in
`Northwind-LICENSE.txt`.
