# SQLite Build-Validation Manifest (#292)

This is the versioned, deterministic sidecar contract recommended by the
[#132 research](SQLiteBuildValidation.md) and produced by
[#292](https://github.com/lukevanin/swiftql/issues/292). It is the input the
standalone validator ([#293](https://github.com/lukevanin/swiftql/issues/293))
and its SwiftPM build-tool plugin wrapper
([#294](https://github.com/lukevanin/swiftql/issues/294)) consume. This module
performs no SQLite database I/O, ships no build-tool plugin, and does not
change the frozen `XLQueryIdentity` v1 representation or make
`XLStaticQueryDescriptor` wholesale `Codable`.

## Package surface

`SwiftQLSQLiteBuildValidationManifest` (`Sources/SwiftQLSQLiteBuildValidationManifest`)
is a regular library target depending only on `SwiftQLCore`. It intentionally
does not depend on the test-only targets that own the #190 inventory, #191
combinatorial cases, or #254 Northwind fixture (`SwiftQLSQLiteConformanceFixtures`,
`SwiftQLSQLiteCombinatorialSupport`, `SwiftQLNorthwindFixtures`); a regular
SwiftPM target cannot depend on a `.testTarget`, and this codebase's existing
targets already follow that boundary (see
`SwiftQLSQLiteBuildValidationValidator`, which likewise avoids depending on
them).

## Schema

`SQLiteBuildValidationManifest` (`format_version: 1`) carries:

- `format_version` — the frozen manifest schema version (see below).
- `conformance_inventory_version` — the #190 `inventory_version` the manifest
  was authored against.
- `combinatorial_manifest_version` — the #191 `generator_version` the manifest
  was authored against.
- `schema_snapshot` — the pinned checked-in SQLite database identity (SHA-256,
  byte count, schema row count, schema fingerprint). Byte identity is
  authoritative; the fingerprint is exact runtime provenance evidence (it
  includes root pages and raw schema SQL) and is not a semantic migration or
  catalog fingerprint.
- `queries` — one `SQLiteBuildValidationQueryEntry` per static query,
  canonically sorted by `id`.

Each query entry records exact UTF-8 SQL, dialect identifier/minimum
version/capabilities, cardinality, canonically ordered parameter and result
entries (logical index, physical SQLite bind position, value type,
nullability, storage identifier, optional codec identity, and — for results —
a declared `AS` alias where one exists), required engine capabilities, and
cross-references into #190 (`conformance_feature_ids`), #191
(`conformance_case_ids`), and #254 (`northwind_anchor_case_ids`).

`XLStaticQueryDescriptor` fields remain authoritative where they overlap. The
manifest only adds fields the frozen `XLQueryIdentity` v1 identity
deliberately excludes: physical placeholder positions (recovered by scanning
the rendered SQL, since SwiftQL emits only `:name` and one-based `?N`),
declared result aliases, pinned schema-snapshot identity, and the #190/#191/
#254 cross-references.

## Determinism and canonical JSON

Canonical JSON is `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`
with exactly one trailing newline. Every set-like field (`conformance_feature_ids`,
`conformance_case_ids`, `northwind_anchor_case_ids`, `required_capabilities`)
is deduplicated and sorted at construction time, and `queries` is sorted by
`id` at construction time — so two manifests built from the same content in a
different order encode to byte-identical bytes. The schema has no timestamp,
hostname, process ID, local path, or elapsed-time field anywhere; determinism
is structural, not something callers must remember to exclude.

## Validation is two separate, composable steps

1. **`validating()`** — structural, registry-independent. Fails closed on: an
   unsupported `format_version`; an empty inventory/manifest version; an
   invalid schema snapshot (empty identifier, non-positive byte/row counts,
   malformed SHA-256/fingerprint hex); a duplicate query id; noncontiguous or
   physically-colliding parameter slots; a malformed indexed-parameter key;
   and incomplete codec metadata. `SQLiteBuildValidationManifest.decode(_:)`
   calls this automatically.
2. **`validating(against:)`** — exhaustive reference resolution. Every
   `conformance_feature_id`, `conformance_case_id`, and
   `northwind_anchor_case_id` in every query must resolve against an injected
   `SQLiteBuildValidationReferenceRegistry`; an unresolved reference throws
   `.unresolvedReference` and fails closed.

These are separate because registry membership is external data (the #190/
#191/#254 JSON/enum sources), not part of the manifest's own bytes — decoding
a manifest cannot, by itself, know whether an ID it references still exists.
Treat a manifest as trustworthy input to the validator (#293) only after both
steps succeed.

### Wiring the real registries

`SQLiteBuildValidationReferenceRegistry` is a protocol so the manifest module
never depends on the concrete #190/#191/#254 sources. A caller that has loaded
them (typically a test target, or eventually the standalone validator) wires:

```swift
let registry = SQLiteBuildValidationStaticReferenceRegistry(
    conformanceFeatureIDs: Set(try SQLiteConformanceInventory.load().features.map(\.id)),
    conformanceCaseIDs: Set(try SQLiteCombinatorialSuite.makeManifest().cases.map(\.id)),
    northwindAnchorCaseIDs: Set(SQLiteNorthwindConformanceCaseID.allCases.map(\.rawValue))
)
try manifest.validating(against: registry)
```

This does not mint a parallel inventory: the registry only reports whether an
ID appears in the canonical sources it was constructed from; it never curates
or duplicates the ID lists themselves.

## Versioning and upgrade policy

`format_version: 1` is frozen, mirroring the `XLQueryIdentity` v1 policy this
sidecar was designed to complement: field inclusion, field ordering, canonical
JSON normalization, and the reference-kind vocabulary (`conformance_feature`,
`conformance_case`, `northwind_anchor`) cannot change under version 1. A
backward-incompatible schema change requires a new `format_version`.
`SQLiteBuildValidationManifest.decode(_:)` rejects any format version other
than `.current` — an unrecognized version fails closed rather than attempting
best-effort compatibility.

`conformance_inventory_version` and `combinatorial_manifest_version` are not
manifest-schema versions; they record which #190/#191 snapshot a manifest was
authored against, purely as provenance. A manifest referencing an older
inventory/combinatorial version than what a validator's registry was built
from is still structurally valid — `validating(against:)` only requires that
the specific referenced IDs still resolve, not that the versions match
exactly. Producers that want stricter drift detection can compare these
fields themselves.

## What this does not do

Per the #132 research decision (§16-17), this module owns only the "freeze the
sidecar manifest schema and deterministic serialization without database I/O"
step. It does not:

- open a SQLite connection, prepare a statement, or otherwise perform database
  I/O (owned by #293);
- provide a build-tool plugin or declare SwiftPM build-command inputs/outputs
  (owned by #294);
- implement or lower the `@SQLQuery` macro (owned by #26); or
- change `XLQueryIdentity` v1, make `XLStaticQueryDescriptor` wholesale
  `Codable`, or mint a competing #190/#191/#254 inventory.
