# Dialect surface separation

**Status:** accepted, 18 September 2026. Shapes the v2.0 public API.

SwiftQL does not translate one dialect's SQL into another. A query written
against PostgreSQL is written in PostgreSQL's vocabulary, and an operation
that PostgreSQL does not have is not offered by the API.

This note records why, and what it changes.

## The problem

The [PostgreSQL rendering spike](PostgreSQLRenderingGaps.md) delivered a second
dialect through the rendering seam that issues #673 and #674 built. It also
found the seam's limit.

The seam was a *vocabulary*: a node names the operation it means, and the
dialect spells the keyword. That works when two dialects perform the same
operation and spell it differently. It fails when one dialect cannot perform
the operation at all, because a vocabulary can only spell — it cannot refuse.

Two cases in the spike rendered SQL that was legal and wrong:

- `INSERT OR IGNORE` became a plain `INSERT INTO`, which raises on conflict
  instead of skipping the row.
- `COLLATE NOCASE` became `COLLATE "C"`, which compares case-sensitively.

A third case, `IIF` becoming `CASE WHEN`, worked only because a fallback
happened to exist. Relying on that is the error: the next divergence will have
no fallback, and the failure will be silent again.

## The distinction

Two kinds of difference were put behind one mechanism.

| Kind | Examples | Translate? |
| --- | --- | --- |
| **Lexical** — the same operation, spelled differently | `=` and `==`, `IS NULL` and `ISNULL`, `$1` and `?1`, identifier quoting, blob literals | Yes. The operation exists everywhere with identical semantics. |
| **Surface** — the operation differs, or is absent | `INSERT OR`, `NOCASE` and `RTRIM` collations, SQLite date modifiers, PostgreSQL arrays and `ILIKE` | No. There is nothing to translate to. |

Lexical divergence belongs to the dialect's formatter and a reduced
vocabulary. Surface divergence belongs to the type system.

## The root cause

`XLExpression<T>` carries no dialect. The dialect is therefore known when SQL
is rendered, not when the code is type-checked, so a call that no backend can
satisfy still compiles.

Half the system already avoids this. `XLValueCodec<Value, Dialect>` and
`XLStaticSelectField` are parameterised by dialect. The query-construction
half is not, and that asymmetry is the defect.

## The decision

**1. The dialect becomes a type parameter on the query surface.**

Expressions, columns, scopes, and statements carry the dialect they were built
for. A SQLite-only operation is then absent from a PostgreSQL query at compile
time, at the call site.

**2. Each dialect vends its own surface, as its own product.**

| Product | Contents |
| --- | --- |
| `SwiftQLCore` | Rendering machinery, the formatter and placeholder seams, and the universal surface: `SELECT`, `FROM`, joins, comparisons, null tests |
| `SwiftQLSQLite` | `XLSQLiteDialect` and SQLite's own surface: `INSERT OR`, `NOCASE` and `RTRIM`, date modifiers, `REGEXP`, JSON |
| `SwiftQLPostgreSQL` | `XLPostgreSQLDialect` and PostgreSQL's own surface: `ON CONFLICT`, `ILIKE`, arrays, native `uuid` and `jsonb` |
| `SwiftQL` | An umbrella over Core and SQLite, so v1 code keeps compiling |

These are products of one package, not separate repositories. Separate
repositories buy one thing — a SQLite-only application not fetching a
PostgreSQL driver's dependencies — and that is a *driver* problem. Split when
the first driver with heavy dependencies arrives, or use package traits.

The type parameter and the product split are complementary, not alternatives.
The products make each surface discoverable and keep driver dependencies out.
The type parameter is what makes the separation binding: a project that
imports both products still cannot call a SQLite operation on a PostgreSQL
query.

## Evidence

A throwaway harness compared the full type parameter against a narrower
variant that parameterised only the scope, table, and column. It modelled the
shapes that degrade Swift diagnostics: a result builder, opaque return types,
and operator overloads. Swift 6.4.

The prototype was throwaway and is not retained here. Its measurements are.

**Diagnostics are unaffected.** Three ordinary mistakes produced byte-identical
error text and position under both variants:

| Mistake | Reported as |
| --- | --- |
| `person.name == 42` | `cannot convert value of type 'Int' to expected argument type 'String'` |
| `person.nmae` | `value of type 'Scope<SQLiteDialect>' has no member 'nmae'` |
| `person.name == person.age` | `operator function '==' requires the types 'String' and 'Int' be equivalent` |

This refuted the main argument against the full parameter, which was that an
inferred generic would make result-builder errors worse.

**The narrower variant leaks.** A SQLite-only operation on a *column* of a
PostgreSQL query is rejected by both. The same operation on a *composed*
expression — `(first + last).collate(.nocase)` — is rejected only by the full
parameter. The narrower variant compiles it with no diagnostic, which is the
failure this decision exists to prevent.

**The cost is two signature shapes.** A helper taking a composed expression
needs the parameter, and a stored predicate is annotated
`any Expr<Bool, SQLiteDialect>` rather than `any Expr<Bool>`. The query body
itself is unchanged, and the dialect is named once where the query begins.

**The open risk is compile time.** Type-checking a synthetic query took 0.17s
against 0.16s at 120 clauses, and 0.56s against 0.48s at 450 clauses: a gap
near 17% that grows with query size. The harness carries far fewer overloads
than SwiftQL does, so this must be measured again against the real overload
set before the parameter is adopted wholesale. Issue #773 already tracks macro
compile cost.

## Consequences

- `XLCollationName` and `XLInsertTarget` leave the shared vocabulary. They are
  surface, and belong to their dialect's product.
- `XLConditionalForm` is removed. `CASE WHEN` is standard and SQLite accepts
  it, so emitting it for every dialect removes the translation rather than
  abstracting it. This changes SQLite's rendered bytes, which is a deliberate
  v2.0 change.
- The vocabulary keeps only the lexical set: comparisons, null tests, the
  common-table prefix, and the regular-expression match operator.
- The formatter and placeholder seams delivered by #673 and #674 are unchanged.
  They were lexical from the start.
- The macro output becomes dialect-parameterised rather than dialect-neutral.
- A PostgreSQL dialect cannot be completed until the type parameter lands,
  because the operations it must refuse have to be absent rather than
  mis-rendered.

## What this does not change

SwiftQL still shares everything that is genuinely shared. Rendering, binding,
codecs, and the universal SQL surface stay in one place. This is not a
lowest-common-denominator API and it is not four separate libraries: it is one
core with a dialect-specific surface on top, which is what the
[roadmap](../../ROADMAP.md) has said since its first direction principle.
