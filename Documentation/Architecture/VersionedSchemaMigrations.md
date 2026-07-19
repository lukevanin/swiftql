# Explicit Versioned Schema Migrations

## Status

This note records the research and SQLite prototype for
[issue #216](https://github.com/lukevanin/swiftql/issues/216). The prototype
lives entirely in `SchemaMigrationArchitecturePrototypeTests.swift`; it is not
a supported API.

The recommendation is to make user-authored, immutable, forward-only migration
definitions the execution source of truth. Schema diffs may produce read-only
reports and confirmation-required proposals, but a live schema difference or a
changed Swift model must never execute a migration by itself.

Migration support is scheduled for
[v2.5](https://github.com/lukevanin/swiftql/milestone/11). It does not block
[catalog bootstrap #215](https://github.com/lukevanin/swiftql/issues/215) or the
v2 catalog release.

## Decision summary

SwiftQL should eventually provide:

1. Catalog-owned semantic schema snapshots and fingerprints.
2. An immutable ordered migration registry with stable definition hashes.
3. An auditable, namespaced history table for SwiftQL-managed execution.
4. Dialect-specific migration operations behind an adapter-neutral executor.
5. One atomic transaction per migration, with the history row committed in the
   same transaction as the schema and data change.
6. Explicit baseline adoption for an existing unmanaged database.
7. A separate external-runner mode for applications that already use GRDB or
   another migration framework.
8. Forward-only application behavior. Downgrade means restore a backup or ship
   a new explicit forward recovery migration, not automatically reverse code.

The initial implementation should be SQLite-specific. Other dialects may reuse
registry and snapshot concepts, but they must own their grammar, capabilities,
locking, transaction rules, and validation.

## Why current SwiftQL cannot migrate safely

The current boundaries are useful foundations, but none is a migration system:

- `sqlCreate` and generated `MetaCreate` currently render table/column names and
  nullability. They do not preserve complete types, defaults, keys, checks,
  indexes, triggers, or views. Typed DDL remains tracked by
  [#139](https://github.com/lukevanin/swiftql/issues/139).
- `XLValueCodecIdentity` already has stable codec, value-type, dialect, and
  storage identities. A codec key/version change is explicitly a data
  migration, so these identities must participate in schema fingerprints.
- `XLDatabaseDriver.withValidatedTransaction` proves pinned-connection commit
  and rollback behavior, but the migration path also needs a serialized/barrier
  writer, schema inspection, runtime dialect version, foreign-key policy outside
  the transaction, and history access.
- Each ordinary `GRDBInvocationExecutor.execute` call starts its own
  transaction. Calling several write requests cannot provide one atomic
  multi-statement migration.
- `GRDBDatabase` initializes `XLSQLiteDialect` without a runtime SQLite version.
  Migration capability selection therefore cannot safely assume which native
  `ALTER TABLE` forms exist.
- Catalog bootstrap is intentionally create-missing only. `CREATE TABLE IF NOT
  EXISTS` neither proves compatibility nor upgrades an existing table.

## Strategy comparison

| Strategy | Role | Decision |
| --- | --- | --- |
| Explicit user-authored migrations | Durable source describing old state, target state, data mapping, validation, and risk | Primary execution model |
| Generated proposals requiring confirmation | Authoring aid that emits exact fingerprints, warnings, unresolved mappings, and reviewable source/artifacts | Recommended after snapshots exist |
| Live schema diff that executes automatically | Infers intent from model/live drift | Rejected |

The distinction is important. A diff can observe that `full_name` disappeared
and `display_name` appeared. It cannot know whether that is a rename, a new
field, intentional data loss, or two unrelated changes. The same ambiguity
exists for type, constraint, and codec changes.

## Recommended contract

The names below are illustrative. The responsibilities and ownership are the
decision.

```swift
struct XLSchemaMigration<Dialect> {
    let catalogID: XLCatalogID
    let sequence: Int
    let migrationID: XLMigrationID
    let definitionFingerprint: XLMigrationDefinitionFingerprint
    let fromSchema: XLSchemaSnapshot
    let toSchema: XLSchemaSnapshot
    let dialectRequirement: XLDialectRequirement
    let foreignKeyPolicy: XLForeignKeyMigrationPolicy
    let risk: XLMigrationRisk
    let operations: [Dialect.MigrationOperation]
    let validations: [Dialect.MigrationValidation]
}
```

### Catalog and fingerprint ownership

- A stable catalog identity owns a specific set of schema objects. Unrelated
  user-managed tables are outside its fingerprint.
- A schema snapshot is a semantic, immutable value produced from typed DDL and
  catalog metadata. It includes tables, columns, physical storage, nullability,
  defaults, keys, constraints, indexes, triggers, views, dialect capabilities,
  and codec identities.
- A dialect inspector converts the live database into the same semantic shape.
  Fingerprints are computed from canonical snapshot values, not raw formatted
  SQL alone.
- Every migration freezes both its old and new snapshot. Migration source must
  not reach into the latest application model to reconstruct a historical
  state.
- SQLite cannot introspect Swift codec meaning from a database file. Historical
  codec/storage metadata therefore comes from the frozen migration definition
  and committed history. An unmanaged baseline needs explicit adoption against
  a supplied expected snapshot.
- The migration definition fingerprint covers the immutable operation tree,
  mappings, risk acknowledgement, dialect requirements, and validations. It
  cannot be derived from an opaque Swift closure identity.

The prototype found one concrete canonicalization requirement: SQLite stores a
directly created table as `CREATE TABLE members ...`, but after rebuilding and
renaming it may store `CREATE TABLE "members" ...`. Those schemas are equivalent.
A raw `sqlite_schema.sql` hash rejected the valid migration; the passing
prototype canonicalizes the object-name quoting before hashing. Production
fingerprints should use the typed semantic representation from #139 and test
all supported SQLite object forms.

### Registry and ordering

Each catalog owns a contiguous positive sequence. Registration order is
explicit, not inferred from identifiers, filenames, model declaration order, or
timestamps.

Before database access, registry validation requires:

- unique catalog/sequence and catalog/migration-ID pairs;
- no sequence gaps;
- each migration's `from` fingerprint equals its predecessor's `to`
  fingerprint;
- every dialect/capability requirement is declared; and
- every destructive operation has an explicit acknowledgement and validation.

After acquiring the migration writer, stored history must be an exact prefix of
the registered definitions. A renamed, removed, reordered, or modified applied
migration is a structured error. Unknown future history means the database is
too new; an older app must refuse migration/writes instead of trying to
downgrade.

### History

SwiftQL-managed mode should use a namespaced internal table rather than SQLite
header pragmas. The prototype uses this shape:

```sql
CREATE TABLE _swiftql_schema_migrations (
    catalog_id TEXT NOT NULL,
    sequence INTEGER NOT NULL CHECK (sequence > 0),
    migration_id TEXT NOT NULL,
    definition_fingerprint TEXT NOT NULL,
    from_schema_fingerprint TEXT NOT NULL,
    to_schema_fingerprint TEXT NOT NULL,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (catalog_id, sequence),
    UNIQUE (catalog_id, migration_id)
);
```

Production may add dialect/runtime version, application build identity, duration,
or a validation summary. The required invariant is that the history row is
inserted after postflight validation and in the same transaction as the change.

`PRAGMA schema_version` is SQLite-owned statement-cache state; writing it can
cause stale statements or corruption. `PRAGMA user_version` is application-owned
but is only one shared integer, cannot represent multiple catalogs or immutable
definition hashes, and may already belong to a host framework. Neither is the
migration ledger.

## Execution algorithm

For each pending migration, the executor should:

1. Acquire one adapter-owned serialized/barrier writer. Migrations should run
   before queries, observations, or prepared handles are exposed.
2. Validate the registered list and re-read stored history under that writer.
3. Inspect the catalog-owned live schema and require the exact `from`
   fingerprint.
4. Validate runtime dialect identity, version, and capabilities.
5. Select the declared foreign-key policy. For a SQLite rebuild, disable
   `PRAGMA foreign_keys` before beginning the transaction and remember the prior
   state.
6. Start an immediate transaction.
7. Execute the frozen dialect-owned operations.
8. Run data-copy invariants and custom validation queries.
9. Run `PRAGMA foreign_key_check` when deferred checks are required, then the
   declared integrity checks.
10. Inspect the live target and require the exact `to` fingerprint.
11. Insert the history row.
12. Commit.
13. Restore the original foreign-key setting outside the transaction, preserving
    the primary operation/commit error if restoration also fails.

SQLite documents that changing `PRAGMA foreign_keys` inside a transaction is a
no-op. This is why migration execution needs a boundary above the existing
transaction closure, not just another statement type.

### Transaction and recovery policy

Use one transaction per migration, not one transaction for all pending
migrations. This gives each released version one durable checkpoint and lets a
restart resume at the first unapplied definition. Within one migration, schema,
data, validation, and history remain atomic.

If an operation, copy check, foreign-key check, target fingerprint, or history
insert fails, the transaction rolls back. An application-level interruption is
the same: no history row means the version was not committed. SQLite is designed
to recover interrupted transactions, but the prototype only injected thrown
errors; it did not perform power-loss or process-kill testing.

SQLite permits only one writer. Use an immediate transaction so lock failure is
reported before expensive copy work. Busy retry/timeouts belong to the adapter
policy and must be visible in the result.

### Downgrades

The initial contract is forward-only:

- `migrate(upTo:)` may stop at a registered future target only when the database
  has not already passed it.
- An older app opening newer history receives a `databaseTooNew` result and
  should remain read-only only if its compatibility policy explicitly proves
  that safe.
- Reversing a destructive transform is not generally possible. Recovery is a
  backup restore or a new explicit forward migration.
- A future reversible-migration feature would need separately authored and
  tested reverse operations; it must not be synthesized from the forward plan.

## SQLite table rebuild

The prototype evolves a real seeded `members` table by:

- renaming `full_name` to `display_name` through an explicit mapping;
- removing `legacy_code` only after mapping it into a new checked `status`
  column;
- adding a nonempty-name check and an active/inactive check/default;
- preserving the primary key and foreign key to `teams`;
- recreating a renamed composite index and a rewritten audit trigger;
- comparing every copied row and transformed value before dropping the source;
- checking foreign keys and database integrity; and
- comparing the rebuilt live schema with an independently created v2 schema.

It follows SQLite's safe order:

1. Create a collision-free new table with the target definition.
2. Copy using explicit target columns and source expressions, never `SELECT *`.
3. Validate the copy.
4. Drop the old table.
5. Rename the new table to the final name.
6. Recreate declared indexes, triggers, and affected views.

The superficially similar rename-old/create-new/copy/drop order is unsafe
because SQLite may rewrite references in triggers, views, and foreign keys.

## What can be generated

| Change | Generator behavior | Execution requirement |
| --- | --- | --- |
| Snapshot/fingerprint/diff report | Generate automatically, read-only | None |
| Create missing object | Keep in explicit bootstrap #215 | Never call it migration |
| Add nullable/defaulted column or index | May generate a proposal after dialect/version checks | User accepts immutable source/registry definition |
| Possible table/column rename | Report candidates only | Explicit old-to-new mapping |
| Drop table/column or remove constraint/index | Mark destructive | Explicit acknowledgement and validation/data disposition |
| Type/nullability/key/check/unique change | Mark data-dependent | Explicit transform plus failure/copy validation |
| Codec key/version/storage change | Mark data migration even if Swift type is unchanged | Old and new codecs plus explicit transform/validation |
| Trigger/view rewrite | Report dependency and target definition | Explicit target semantics; never blind text cloning |
| Unsupported dialect/object | Blocking diagnostic | Add dialect/object support or use an audited raw escape hatch |

A raw dialect-specific operation may be necessary, but it must still declare
before/after fingerprints, capability requirements, risk, and validation. It
does not become portable merely because it is wrapped in a shared Swift type.

## Existing migration frameworks

SwiftQL must not force existing applications to replace a mature migration
runner. Provide two explicit modes:

### SwiftQL-managed mode

SwiftQL owns registry ordering, its namespaced history table, the transaction,
foreign-key policy, validation, and result.

### External-runner mode

GRDB `DatabaseMigrator` or another framework owns ordering, journal, serialized
writer, transaction, and recovery. SwiftQL supplies one frozen operation with
preflight/postflight validation and declares the required foreign-key policy.
It does not create `_swiftql_schema_migrations`, start a nested transaction, or
claim the migration was applied.

An application must choose one owner per catalog. Running two independent
histories over the same objects is rejected. GRDB's existing behavior is a good
SQLite reference: named migrations run once in order, each in its own
transaction; rebuild migrations defer foreign-key enforcement, check all foreign
keys before commit, and restore enforcement afterward.

## Dialect and adapter responsibilities

Shared core owns identities, immutable registry/history values, semantic schema
concepts, risk classifications, and structured outcomes.

Each dialect owns:

- supported native alter operations and minimum server/runtime versions;
- rebuild or alternative lowering rules;
- identifier and schema-object canonicalization;
- type, storage, default, constraint, index, trigger, and view semantics;
- transaction/locking requirements; and
- introspection needed for a live snapshot.

Each adapter owns serialized connection access, statement execution, binding,
transactions, cancellation/busy policy, foreign-key/configuration state, and
error normalization.

The SQLite prototype is evidence only for SQLite 3.51.0. It says nothing about
PostgreSQL transactional DDL, MySQL implicit commits, SQL Server batches, or
their online migration features.

## Required rejections and edge cases

Initial implementations should reject rather than weaken validation when they
encounter:

- ambiguous renames or unmapped target columns;
- a changed applied migration definition;
- missing, gapped, or unknown future history;
- an unexpected catalog-owned live object;
- codec changes without both historical and target semantics;
- unsupported virtual/FTS tables, generated columns, STRICT/WITHOUT ROWID
  options, partial/expression indexes, or dependent triggers/views;
- foreign-key cycles without a proven deferred-check plan;
- attached/temp schemas when only `main` is supported;
- attempts to migrate after statements/observers are already active; or
- insufficient disk/lock budget for a table rebuild.

Large table rebuilds can need roughly another copy of the table plus journal/WAL
space and can hold the writer for a long time. Chunked or online migration is a
separate architecture, not an automatic fallback. The executor should expose
estimates/progress hooks where possible and fail before destructive steps when
the required capability or resource policy is absent.

## Prototype evidence

Validation command:

```text
swift test --filter SchemaMigrationArchitecturePrototypeTests
```

Environment:

- SQLite CLI/runtime family checked during the run: 3.51.0.
- Apple Swift 6.3.2, target `arm64-apple-macosx26.0`.
- Five focused tests, zero failures.

The tests prove:

- a real v1-to-v2 SQLite rebuild preserves/transforms seeded rows;
- row values, removed/renamed/new columns, foreign keys, checks, defaults,
  index, trigger, audit data, integrity, and target fingerprint are inspected;
- reapplying the same definition is idempotent;
- unexpected live schema fails before mutation;
- a copy constraint failure rolls back and restores foreign-key enforcement;
- an injected failure after rebuild validation but before history insertion
  restores the complete v1 schema/data/history; and
- changed history plus ambiguous rename/codec/dialect proposals fail explicitly.

## Prototype limitations

- The prototype is private test code over GRDB, not an adapter-neutral public
  implementation.
- Its FNV-1a fingerprint and narrow SQLite quote canonicalization demonstrate
  the contract but are not production fingerprint algorithms.
- It uses small in-memory tables and synchronous execution.
- It does not test a process kill, power loss, disk full, busy timeout,
  concurrent process, attached database, huge copy, views, virtual tables,
  generated columns, STRICT/WITHOUT ROWID, or cross-dialect behavior.
- It uses explicit SQL to freeze the historical schemas because #139 and the
  complete catalog metadata are not implemented yet.

## Accepted follow-up issues

- [#276 — Catalog-owned live-schema snapshots and migration fingerprints](https://github.com/lukevanin/swiftql/issues/276)
- [#277 — Immutable versioned migration registry and history contract](https://github.com/lukevanin/swiftql/issues/277)
- [#278 — Atomic SQLite migration executor and history commit boundary](https://github.com/lukevanin/swiftql/issues/278)
- [#279 — Typed SQLite table rebuilds with explicit data transforms](https://github.com/lukevanin/swiftql/issues/279)
- [#280 — Catalog migration integration and bootstrap handoff](https://github.com/lukevanin/swiftql/issues/280)
- [#281 — Read-only schema diffs and confirmation-required proposals](https://github.com/lukevanin/swiftql/issues/281)

## References

- [SQLite ALTER TABLE and the generalized rebuild procedure](https://www.sqlite.org/lang_altertable.html#making_other_kinds_of_table_schema_changes)
- [SQLite transaction behavior](https://www.sqlite.org/lang_transaction.html)
- [SQLite PRAGMA reference](https://www.sqlite.org/pragma.html)
- [SQLite foreign-key behavior](https://www.sqlite.org/foreignkeys.html)
- [GRDB 6.29.3 migration guidance](https://github.com/groue/GRDB.swift/blob/v6.29.3/Documentation/Migrations.md)
- [Typed DDL #139](https://github.com/lukevanin/swiftql/issues/139)
- [Catalog bootstrap #215](https://github.com/lukevanin/swiftql/issues/215)
- [GRDB adapter boundary #113](https://github.com/lukevanin/swiftql/issues/113)
