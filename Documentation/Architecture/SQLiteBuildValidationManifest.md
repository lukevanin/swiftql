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

`SQLiteBuildValidationManifest` (`format_version: 2`; version 1 is still
read) carries:

- `format_version` — the manifest schema version (see below).
- `conformance_inventory_version` — the #190 `inventory_version` the manifest
  was authored against. Required in version 1. Optional in version 2, where
  its absence means the manifest was not authored against SwiftQL's fixtures.
- `combinatorial_manifest_version` — the #191 `generator_version` the manifest
  was authored against. Required in version 1; optional in version 2, with the
  same meaning.
- `schema_snapshot` — the pinned checked-in SQLite database identity (SHA-256,
  byte count, schema row count, schema fingerprint). Byte identity is
  authoritative; the fingerprint is exact runtime provenance evidence (it
  includes root pages and raw schema SQL) and is not a semantic migration or
  catalog fingerprint. Required in every version: the validator checks the
  database it opens against it.
- `queries` — one `SQLiteBuildValidationQueryEntry` per static query,
  canonically sorted by `id`. Version 1 requires at least one; version 2
  accepts an empty list, so a target that declares no queries still has a
  valid manifest.

Each query entry records exact UTF-8 SQL, dialect identifier/minimum
version/capabilities, cardinality, canonically ordered parameter and result
entries (logical index, physical SQLite bind position, value type,
nullability, storage identifier, optional codec identity, and — for results —
a declared `AS` alias where one exists), required engine capabilities, and
cross-references into #190 (`conformance_feature_ids`), #191
(`conformance_case_ids`), and #254 (`northwind_anchor_case_ids`).

### Version 2 shape

This is what a generator (#659) emits. `?` marks a key that may be omitted;
every other key is required. No other key is accepted at any level.

```text
{
  "format_version": 2,
  "conformance_inventory_version"?: "<nonempty>",
  "combinatorial_manifest_version"?: "<nonempty>",
  "schema_snapshot": { "kind": "checked-in-snapshot", "identifier",
                       "database_sha256", "database_byte_count",
                       "schema_row_count", "schema_fingerprint" },
  "queries": [ {
    "id", "definition_identity", "descriptor_identity", "sql",
    "dialect_identifier", "minimum_dialect_version"?,
    "dialect_capabilities_raw_value", "cardinality",
    "conformance_feature_ids", "conformance_case_ids",
    "northwind_anchor_case_ids", "required_capabilities": [ { "id" } ],
    "parameters": [ { "logical_index", "physical_index", "identity",
                      "key_kind", "key_name"?, "key_index"?,
                      "value_type_identifier", "value_type_name"?,
                      "nullability", "storage_identifier", "codec"? } ],
    "results": [ { "index", "identity", "declared_alias"?,
                   "value_type_identifier", "value_type_name"?,
                   "nullability", "storage_identifier", "codec"? } ]
  } ]
}
```

A `codec` object has `key_id`, `key_version`, `value_type_identifier`,
`dialect_identifier`, and `storage_identifier`. The three reference lists are
still required, and are empty when a query has no fixture references. A query
with a `conformance_feature_ids` entry requires
`conformance_inventory_version`, and a query with a `conformance_case_ids`
entry requires `combinatorial_manifest_version`, so a fixture reference can
always be traced to the inventory it names. `northwind_anchor_case_ids` has
no version field, so it has no such rule.

### Per-slot metadata

- `value_type_name` is optional in version 2. It is the Swift spelling of the
  value type, and the validator never reads it: `value_type_identifier` is the
  stable identity. A producer that knows the spelling, such as the
  `init(id:descriptor:)` projection, may still write it for a human reading the
  manifest. When it is present it must not be empty. Version 1 requires it.
- `nullability` stays required in every version. The validator does not use it
  at prepare time, but structural validation checks it against
  `XLParameterNullability`, and every descriptor slot carries it, so a
  generator can always write it truthfully. Removing it would remove that
  check.

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
   unsupported `format_version`; an empty inventory/manifest version (or, in
   version 1, an absent one); an empty query list in version 1; an
   invalid schema snapshot (empty identifier, non-positive byte/row counts,
   malformed SHA-256/fingerprint hex); a duplicate query id; noncontiguous or
   physically-colliding parameter slots; a malformed indexed-parameter key;
   an absent or empty `value_type_name` in version 1, or an empty one in
   version 2; a #190/#191 reference without its inventory version; and
   incomplete codec metadata. `SQLiteBuildValidationManifest.decode(_:)`
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

Each released `format_version` is frozen, mirroring the `XLQueryIdentity` v1
policy this sidecar was designed to complement: field inclusion, a field's
required-ness, canonical JSON normalization, and the reference-kind vocabulary
(`conformance_feature`, `conformance_case`, `northwind_anchor`) cannot change
under a released version. Any schema change, additive or not, requires a new
integer `format_version`. A reader of the current version reads every earlier
version: the version 2 reader decodes and validates a version 1 manifest with
every version 1 check, and re-encodes it to the same bytes. An optional field
that is absent is omitted from the JSON, not written as `null`.

**Decoding is version-first.** `SQLiteBuildValidationManifest.decode(_:)`
decodes `format_version` alone before anything else, and the type's
`init(from:)` also checks it before any other key. A version the reader does
not know fails with `unsupportedFormatVersion`, whatever the body contains; it
never surfaces as a `keyNotFound` or type-mismatch decoding error. The plan
suppression file (`swiftql-plan-analysis.json`) is decoded the same way.

**Unknown keys fail closed.** Every manifest type, and both plan-suppression
types, rejects a key it does not define with `unknownKey(path:)`, where `path`
locates the key (for example `queries[0].parameters[1].key_nmae`). Synthesized
`Decodable` ignores such a key, so a misspelled optional key used to decode as
"absent" and silently change what the manifest said.

**There are no additive v1.x fields.** A version 1 reader does not accept a
version 1 document with extra fields. SwiftQL 1.9 and later reject the extra
key. SwiftQL 1.8 ignored it, but that was never a compatibility promise. SwiftQL
1.8 also cannot read a version 2 manifest: it rejects the version, or fails to
decode a manifest that omits the provenance fields.

`conformance_inventory_version` and `combinatorial_manifest_version` are not
manifest-schema versions; they record which #190/#191 snapshot a manifest was
authored against, purely as provenance. A manifest referencing an older
inventory/combinatorial version than what a validator's registry was built
from is still structurally valid — `validating(against:)` only requires that
the specific referenced IDs still resolve, not that the versions match
exactly. Producers that want stricter drift detection can compare these
fields themselves. A manifest that is not authored against SwiftQL's fixtures,
such as one generated from an application's own declarations, omits both
fields in version 2 rather than copying SwiftQL's values.

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
