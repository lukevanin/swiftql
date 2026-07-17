# Value-Semantic Recursive CTE Construction

## Status

This note records the issue #41 research prototype. The prototype lives entirely
in `RecursiveCTEConstructionPrototypeTests.swift`; it is not a supported API.
The recommendation is to replace the current mutable recursive-definition cell
with an alias-first, two-phase value model when recursive CTE construction is
implemented for the public API.

The test prototype proves value semantics only for alias reservation, reference
layout, and completion state. It creates current-v1 generated references and an
`XLCommonTableDependency` only as short-lived compatibility adapters. Those
existing types contain mutable classes or unconstrained existential payloads,
so this note does not call either adapter deeply immutable or `Sendable`.

## Problem in the current implementation

`XLSchema.recursiveCommonTable` and
`XLSchema.recursiveCommonTableExpression` currently create an
`XLRecursiveCommonTableStatement` class, put it behind an
`XLCommonTableDependency`, construct the self-reference, and then assign the
class's implicitly unwrapped `statement` property.

That solves the circular construction problem, but it gives recursive CTEs
reference semantics that ordinary query nodes do not advertise:

- an incomplete definition traps when rendered instead of returning a
  construction error;
- copies share the same mutable completion cell;
- the body can be replaced after references and enclosing statements exist;
- failure while building the body requires reasoning about cleanup of shared
  state;
- the cell is unsuitable for independent concurrent construction; and
- the definition object mixes query construction with lifecycle state.

No database, connection, prepared statement, or execution state is needed to
solve the circularity. The circular dependency is only between a stable SQL
name and a statement body.

## Prototype model

The prototype separates three concepts:

1. **Declared alias.** Allocate the CTE alias before evaluating the body. It is
   an immutable value and is the only information a self-reference needs.
2. **Reference layout.** Retain only immutable names and result-layout data.
   Construct a fresh current-v1 typed reference for each completion attempt; the
   draft never stores an `XLNamespace`, generated result, body, or dependency.
3. **Completion lifecycle.** Evaluate the body transactionally. The prototype
   stores only `declared`, `building`, or `completed` in the draft, then returns
   the current mutable `XLCommonTableDependency` as a rendering adapter. The
   recommended production completed definition is a separate immutable value.

The test-only state machine is:

```text
declared(alias, value layout) -- begin --> building(alias)
building -- body succeeds --> completed(alias)

building -- body throws --> declared
building -- begin again --> reentrantCompletion error
completed -- complete again --> alreadyCompleted error
declared -- request definition --> incomplete error
```

The draft is a struct. Copying it copies the state. Completing one copy neither
completes nor invalidates another copy. Both copies retain the same explicitly
declared alias, so callers must not insert independently completed copies into
the same `WITH` scope without normal duplicate-alias validation.

The implementation enters `building` before evaluating the body, restores
`declared` if the body throws, and stores no body in the lifecycle state. The
second-completion and reentry checks happen before evaluating another body,
preventing hidden work or side effects.

### Reentrancy

Completion is synchronous and nonescaping. Its closure receives only the typed
self-reference, never the draft itself. The lifecycle owner has a concrete
`building` state and reports `reentrantCompletion` if a second begin reaches the
same draft. Swift exclusive access prevents ordinary same-variable reentry;
the explicit state also covers internal callbacks and makes the diagnostic
testable. Completing a copied draft is independent. Nested construction uses a
different draft created inside the active outer completion.

## Typed references

The prototype exercises both result shapes needed by later work.

### Generated composite result

An `@SQLResult` with `value` and `depth` fields uses its generated
`MetaNamedResult`. An immutable test layout creates that generated reference on
demand through `XLFromTableDependency(commonTable:alias:)`; the draft itself never
retains the generated result or its mutable `XLNamespace`. Recursive expressions
therefore keep their existing typed columns and result decoding shape while the
lifecycle proof remains independent of current reference storage.

The prototype supplies an alias-only dependency with an unrenderable sentinel
body because the public compatibility initializer still accepts a complete CTE
definition. Issue #42's unified production reference immediately snapshots only
that alias as an immutable name token; neither the sentinel nor any real body is
retained. The remaining lifecycle work is therefore independent of definition
storage.

### Direct scalar result

The test-only `PrototypeScalarReference<Value>` exposes one
`XLColumnReference<Value>` with a stable column alias. It proves that a direct
scalar self-reference does not need `SQLScalarResult<Value>` or a generated row
wrapper.

SwiftQL's current compound-query helpers constrain union rows to `XLResult`, so
the scalar test uses a tiny test-only `UNION ALL` encoding node. Removing that
constraint and publishing the scalar reference belongs to issue #43. Issue #41
does not change the public compound-query surface.

## Alias allocation and concurrency

Aliases must be reserved before body evaluation and then remain unchanged
through references, completion, nesting, copying, and retry after failure. The
prototype uses explicit aliases to isolate this property from the current
`XLNamespace` allocator.

`XLNamespace` is currently a mutable class. A production value-semantic design
should not share it between concurrent builders. Two viable implementation
directions are:

- make the construction context a value containing independent common-table,
  table, and parameter alias allocators; or
- allocate immutable alias tokens in the enclosing builder before child tasks
  begin, then pass tokens into independent drafts.

The prototype constructs and renders independent drafts concurrently while
passing only rendered strings out of each task. It does not claim that the
existing `XLSchema`, `XLNamespace`, returned v1 dependency, or arbitrary query
existential is `Sendable`. Mutable drafts are task-confined. The recommended
production reference and completed values may be `Sendable` only when their
sealed layout and body snapshots are also `Sendable`.

## Nesting

The prototype creates and completes an inner draft while the outer draft is in
its `building` state, then uses the returned v1 dependency in the outer anchor.
It renders the exact nested SQL through `XLiteEncoder` and executes it with real
SQLite. No shared completion registry or parent pointer is required. The test
proves nested construction, not same-draft reentry.

Lexical SQL scope remains authoritative. A future builder should validate
duplicate aliases within each `WITH` list, but the production completed value
should not retain or mutate an enclosing scope.

## Recommended production seam

The production names remain open. The important boundary is that SwiftQL must
not erase an arbitrary `any XLEncodable` into a type advertised as immutable or
`Sendable`. The implementation should use a sealed internal protocol whose
conformers are audited immutable SQL-node structs, or an immutable token-tree
snapshot with equivalent guarantees. The minimum responsibilities look like
this:

```swift
protocol XLImmutableRecursiveCTEBody: XLEncodable, Sendable {}

struct XLRecursiveCTEDraft<Layout> where Layout: Sendable {
    let name: XLCommonTableName
    let layout: Layout
    private var state: State // declared, building, completed

    mutating func complete<Body: XLImmutableRecursiveCTEBody>(
        _ body: (XLCommonTableReference<Layout>) throws -> Body
    ) throws -> XLCompletedCommonTable<Layout, Body>
}

struct XLCommonTableReference<Layout>: Sendable where Layout: Sendable {
    let name: XLCommonTableName
    let tableAlias: XLName
    let layout: Layout
}

struct XLCompletedCommonTable<Layout, Body>: Sendable
where Layout: Sendable, Body: XLImmutableRecursiveCTEBody {
    let name: XLCommonTableName
    let body: Body
    let layout: Layout
}
```

If body type erasure is needed, its initializer must accept only the sealed
immutable-body protocol and capture a value snapshot; accepting arbitrary
classes or `@unchecked Sendable` payloads would recreate the rejected hidden
mutation. A mutable draft is task-confined while it is building. Rendering
accepts only a completed value. The typed reference depends on the immutable
name and static result layout, never the body or execution adapter.

### Error ownership

- `XLRecursiveCTEDraft` owns `incomplete`, `alreadyCompleted`, and
  `reentrantCompletion`.
- Completion owns `resultLayoutMismatch` before producing a completed value.
- `XLCommonTablesBuilder` owns `duplicateAlias` because duplicates are a
  property of one lexical `WITH` list, not one definition.

The internal construction seam is throwing and testable. Existing nonthrowing
v1 helpers never expose a draft: they create one fresh reservation, invoke one
body closure, and complete it exactly once. Lifecycle misuse is therefore an
internal invariant on that bridge. Layout or duplicate-alias failures must be
retained as structured construction failures on the returned encoding and
surfaced by validation/preparation, rather than trapping during rendering.

### Exact v1 bridge

`recursiveCommonTable` and `recursiveCommonTableExpression` retain their current
signatures and `T.MetaCommonTable` return type. Internally each helper:

1. reserves the existing namespace-derived CTE alias and static result layout;
2. creates a fresh task-confined draft;
3. constructs the current `(XLSchema, T.MetaCommonTable.Result.MetaNamedResult)`
   closure arguments from the draft's immutable name/reference layout;
4. invokes the existing nonthrowing closure once;
5. completes the draft and adapts the completed value into the existing
   `MetaCommonTable`; and
6. stores any layout validation failure for structured preparation-time
   reporting.

No call-site syntax, return type, generated column shape, alias order, or SQL
bytes change in v1. The old `XLRecursiveCommonTableStatement` may remain only as
an ABI compatibility shim, but new construction does not use or mutate it. V2
removes that shim and may expose the validated throwing draft/completed API.

## Alternatives considered

### Alias-first value lifecycle — selected

Reserve the immutable name and layout, build references from those values, and
transactionally produce a completed immutable definition. Copies own their
lifecycle state, failure rollback is local, and the body never needs a back
pointer to its definition.

### Isolated indirection box — compatibility fallback only

A lock-protected or actor-isolated box can make completion race-free, but copies
still share definition identity and completion history. Actor isolation also
forces async construction into today's synchronous DSL; a lock adds reentrancy
and lifetime complexity. Such a box could contain a legacy ABI shim, but it
must not be presented as value semantics or leak into the public model.

### Unsynchronized mutable placeholder — rejected

The current implicitly unwrapped, replaceable statement cell can trap when
incomplete, race under concurrent access, and change after enclosing queries are
built. Hiding the same cell inside a struct does not improve its semantics.

### Rebuild-to-fixpoint or two-pass body evaluation — rejected

Evaluating the user's body once to discover references and again to complete it
duplicates work and observable closure side effects. It also risks assigning
different aliases between passes. Reserving the alias first solves the cycle
without reevaluating user code.

## Evidence from the prototype

The tests compile and run the following cases:

- generated composite typed self-reference;
- direct scalar typed self-reference;
- exact recursive SQL rendering;
- execution by a real SQLite engine;
- independent state after copying a draft;
- nested recursive definitions;
- concurrent independent construction;
- incomplete and multiply-completed definitions;
- structured reentrant-completion ownership;
- transactional cleanup after a throwing body; and
- alias stability across completion, copying, failure, and retry.

These tests prove the alias/layout/lifecycle model. The exact rendering and
SQLite cases pass through current v1 query nodes, but do not promote those
mutable compatibility adapters to immutable or `Sendable` production values.

## Scope boundaries

This research does not:

- modify the existing v1 recursive CTE API or its rendered SQL;
- implement issue #43's public direct-scalar CTE rows;
- expose the prototype types as SwiftQL API;
- move GRDB, a database connection, or prepared state into a definition or
  reference;
- claim that the current generated references, `XLNamespace`,
  `XLCommonTableDependency`, or arbitrary query existentials are deeply
  value-semantic or `Sendable`;
- redesign `XLNamespace`; or
- select final public names before the static result-layout work is available.

The safe next step is to implement an internal immutable CTE-name/reference
type and make completed definitions the only renderable recursive definition.
The generated composite layout can adopt that seam first. Direct scalar
publication and compound-query constraint removal should remain in #43.

## Follow-up implementation contracts

- [Issue #42](https://github.com/lukevanin/swiftql/issues/42) makes a FROM
  reference retain only the immutable CTE alias instead of its definition body.
- [Issue #205](https://github.com/lukevanin/swiftql/issues/205) implements the
  alias-first draft/completion lifecycle for generated composite layouts. It
  depends on the static result layout from #40 and the alias-only reference from
  #42, and records the v2 removal of the legacy mutable compatibility shim.
- [Issue #43](https://github.com/lukevanin/swiftql/issues/43) consumes #205's
  adapter-neutral name/reference contract to publish direct scalar CTE rows.
  Scalar publication and compound-query constraint removal stay entirely in
  that issue.
