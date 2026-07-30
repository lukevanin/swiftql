# Designing SwiftQL

Why SwiftQL looks the way it does, what was tried before it, and what it cost.

This document records design rationale. [ROADMAP.md](../ROADMAP.md) states
current direction, and [COMPATIBILITY.md](../COMPATIBILITY.md) records what is
actually supported. Where they disagree with this document, they are right and
this one is out of date.

## The problem this came from

Every iOS app I have worked on that stored real data eventually forced the same
choice, and both options were bad.

Core Data is an object-graph manager. Apple is careful to say it is not an ORM,
and that is technically true, but it presents the same bargain: you work with
objects and the store is someone else's problem. In practice queries are hard to
reason about and slow, ordinary object-graph inserts and updates are slow in a
way that is difficult to fix, and the memory and threading model is
unpredictable. Managed objects are heap-allocated and comparatively expensive,
and they are bound to their context, so moving data across threads means passing
object IDs and re-faulting on the other side rather than passing values. The
batch APIs exist and are genuinely faster, but they work by bypassing the object
graph - which is the tell. The abstraction that was supposed to save work
generates its own work, and its fast path is the one that steps around it.

SQLite is the other option. It is stable, efficient, predictable, and simple.
But in Swift its queries are strings, which means no compile-time checking at
all. Every query is a shot in the dark that breaks at runtime the moment
anything changes.

This came to a head on EventCloud, a white-label events product whose iOS app I
built: offline-first, large data set, and it needed
sync. It started on Core Data, and a disproportionate share of both development
time and runtime went to the database layer. I ended up writing a system that
generated managed objects and the server API from a backend schema, which helped
with the boilerplate but not with the underlying model. While trying to make it
faster and more stable, it became clear SQLite was the better foundation. That
solved the performance and predictability problems and replaced them with a new
one: hand-rolled query strings.

I had used LINQ previously, and the idea followed from there. Swift should be
able to express SQL natively, so queries are type-checked like any other code.

## What "native" had to mean

The goal was first-class support for *SQL*, not a new query language that
happens to be written in Swift.

Most persistence libraries invent a proprietary API and, with it, a switching
cost. What you learn is not transferable, and what you write cannot be moved
back out. SwiftQL's constraint from the start was that code should be directly
translatable in both directions: read SQL, write the SwiftQL, and vice versa,
without a mental compiler in between.

That constraint is the reason the library is SQL-shaped rather than
ORM-shaped, and the reason clause names and clause order match SQL exactly. It
also sets the boundary on what SwiftQL is willing to do: it does not hide the
relational model, and it does not attempt to be the authority on semantics
SQLite already owns.

### On ORMs

The stronger claim underneath that: relational databases are the correct way to
handle data, and ORMs are an unnecessary layer of indirection that misrepresents
what is actually happening.

Most languages do not expose the relational model directly. They ship an ORM
instead, on the theory that objects are easier for programmers than tables. The
theory does not survive contact with real schemas, and it fails in a consistent
pattern:

- **Relationships that are not object-shaped.** An object graph models
  containment and reference well. It does not model a left join, a grouped
  aggregate, or a projection across three tables, because none of those produce
  an object - they produce a row shape that exists only for that query.
- **Performance that degrades invisibly.** Fetching an object with many children
  is the case every ORM handles badly, and every ORM answers with a set of
  workarounds: prefetching hints, fault batching, relationship faulting rules.
  These are configuration knobs for a problem the relational model does not
  have, because a join is one query.
- **A query syntax with no fixed form.** Predicates, chained methods, functional
  combinators, or plain loops over in-memory collections all end up expressing
  queries, often in the same codebase. There is no canonical way to say what you
  mean, so equivalent queries look nothing alike and their cost is impossible to
  read off the page.

Each workaround adds complexity, and the complexity is spent buying back
performance the abstraction gave away. The indirection is dishonest in a
specific sense: it advertises that the relational model is gone, while the
relational model is still doing all of the work underneath and still determines
whether the program is fast or slow. When it leaks, and it always leaks, the
programmer has to understand both the database and the abstraction over it.

SQL is a good language for this. It is declarative, it has been in use for
roughly fifty years, it is
the same across projects and largely across engines, and it already expresses
exactly the operations that object graphs struggle with. The problem was never
SQL. The problem was that Swift could not see it.

## Three attempts before macros

The idea was viable long before Swift could express it well.

The first exploratory versions used a third-party code generator, which was the
standard approach before Swift macros existed. It worked, but it put a separate
tool and a generated-file lifecycle between you and your code.

The second required programmers to annotate their structs by hand. It was
rudimentary and needed a lot of manual boilerplate, but it proved the core idea:
if the compiler knows the shape of the table, it can check the query.

The third tried to remove that boilerplate with the tools Swift had at the time:
`Codable`, property wrappers, and `Mirror`. This is where it stalled. Those
mechanisms can describe a type at runtime, but the entire point was to be
checked at *compile* time. Reflection was the wrong shape for the problem.

By then it was clear what the missing piece was. When a member of the Swift team
asked on Twitter what people wanted from the language, my answer was macros:
compile-time code generation, in the language, without a separate tool. Macros
arrived in Swift 5.9 in September 2023, and SwiftQL moved onto them immediately.

Macros have since become, in my view, the most useful addition to Swift after
generics and the concurrency primitives. They are also the reason the earlier
approaches are gone rather than rejected: native compile-time code generation is
simply the right mechanism for this, and everything before it was working around
its absence.

## Why result builders, in SQL order

The current syntax was not obvious, and it was not first.

Early versions used functional chaining, the way most Swift query libraries do.
That syntax still works today. When I started, result builders could not express
what SwiftQL needed: without partial block support, every combination of clauses
needed its own overload, and the method count exploded combinatorially.

`buildPartialBlock` arrived in Swift 5.7 in September 2022, and everything fell
into place. That proposal exists precisely because of this problem: its stated
purpose is to collapse the combinatorial overloads that complex result builders
would otherwise need, and it is part of what made Swift's own regex builders
possible.

The result was better than the chaining version in a way that was immediately
obvious, and familiar along two axes at once. It looks like the SQL I would have
written by hand, and it looks like SwiftUI. Swift had by then established this
shape as idiomatic - in SwiftUI, and then in RegexBuilder - so a query written
this way reads as ordinary modern Swift rather than as a library's private
convention.

Macros, result builders, and SQL turn out to fit together unusually well: macros
supply the compile-time knowledge of the schema, and result builders supply a
statement syntax that can consume it in SQL's own order.

The chaining syntax has aged less well. The extra punctuation now reads as
obtuse next to the builder form, so the plan is to move it into a separate
library for people who prefer it, and leave result builders as the single way to
use SwiftQL.

## Swift types, not SQL types

The largest single design decision was whether column values should be
SQLite's types or Swift's.

The alternative was a parallel type system: `SQL.Integer`, `SQL.Real`,
`SQL.Blob`, mirroring SQLite's storage classes and affinity rules. I chose
native Swift types instead: `Int`, `Double`, `Data`.

Four reasons:

1. **SQLite does not enforce types anyway.** Modelling its type affinity
   faithfully means faithfully modelling something the database itself treats as
   advisory. `STRICT` tables, added in SQLite 3.37, are the exception, but they
   are opt-in and they make the column's declared type authoritative - which is
   the behavior Swift's own types already give you.
2. **It would trade away Swift's actual strength.** Affinity conventions are
   resolved at runtime. Swift's value here is compile-time guarantees, and a
   type system that defers to runtime coercion gives that up.
3. **It introduces a foreign type system** that users must learn, hold in their
   heads, and convert across at every boundary.
4. **The data ends up in a typed Swift struct regardless.** The SQL-typed layer
   would be a stop on the way to the destination, adding inconvenience for
   little practical return. It is mostly a vanity goal.

The payoff is that table definitions look like ordinary Swift structs, which is
most of the learning curve gone. The cost is real and is paid in codecs: types
without a native SQLite equivalent, notably `Date` and `UUID`, need conversion
declared somewhere. How that is declared has itself been revised, discussed
below.

## Standing on GRDB

SwiftQL executes through GRDB rather than talking to SQLite directly.

GRDB provides connection pooling and observation. Both are necessary, and both
would otherwise have to be built before any of the interesting work could start.
I have written that layer before, and an early version of SwiftQL used my own.
Choosing GRDB was a decision about where to spend attention: the query syntax
was the unsolved problem, and SQLite boilerplate was not.

This is also why SwiftQL is not an alternative to GRDB. It is a typed query
layer above it, and the two compose deliberately. Schema migrations, for
instance, are GRDB's `DatabaseMigrator` and SwiftQL does not attempt to replace
them.

The intended end state is a thin SQLite wrapper optimized for SwiftQL's own
access patterns, with GRDB compatibility retained for projects that want or need
it. That is motivated by performance rather than by any dissatisfaction with
GRDB. See the studies in [`Research/`](../Research) for the drivers that were
evaluated.

## The hard part

The difficult problem was not any single feature. It was arriving at a
translation from Swift to SQL that is checked by the compiler and still produces
a *cacheable prepared statement*.

Those two requirements pull against each other. Compile-time checking wants
everything expressed in the type system, where it is static and known. Prepared
statement caching wants a stable SQL string with bound parameters, where the
values are explicitly *not* part of the statement. Satisfying both means the
type-level structure has to describe a statement shape while the values travel
separately, and it means writing code whose purpose is to generate other code.
Holding both levels in your head at once takes some getting used to, and the
solution needed several layers of indirection before it worked.

Some of the result builders were genuinely mind-bending. Recursive common table
expressions are the extreme case: expressing a CTE that refers to itself, inside
a builder, while keeping the whole thing typed. I am still not entirely sure how
I did it. That construction is written up separately in
[`Architecture/RecursiveCTEConstruction.md`](Architecture/RecursiveCTEConstruction.md).

## What it costs

**Compile time.** Large table types generate a lot of code, and that code is
recompiled whenever they change. The mitigation is structural: put database
objects in their own package, so they rebuild only when the data model changes
rather than on every build of the app. The intent is to make this a one-off
cost paid when the schema changes, in exchange for full type checking of every
query that touches it. That is the trade the whole library makes, and it is
worth being explicit that it is a trade.

**Runtime performance.** Current performance is lower than it should be, mostly
in the mechanics of decoding rows out of SQLite. Moving to the native SQLite C
interface should remove that overhead. I expect a large improvement, possibly an
order of magnitude, but that is an expectation and not a measurement - the
current numbers are in [BENCHMARKS.md](../BENCHMARKS.md) and the comparison does
not exist yet.

## What is still wrong

**Too much boilerplate, particularly around variables.** This is the most
visible remaining wart and is targeted for upcoming versions.

**Two syntaxes.** Supporting both chaining and result builders splits the
surface area and the documentation. Chaining moves to its own library.

**The builder entry points.** `sql { }` and `sqlResult { }` are result builders
because that was what the language offered. A function macro is a better fit,
and the relevant proposal is in Swift Evolution. When it lands, these go.

**Custom encoding, now fixed but instructive.** SwiftQL originally supported
custom value encoding through protocol conformance. Adding that to an existing
type such as `Date` means writing an extension, which breaks down as soon as an
application needs more than one encoding for the same type. Multiple date
encodings are common, not exotic. Installable codecs solve this properly,
because the encoding becomes a property of the column rather than of the type.

**Macros remain sharp-edged.** I have used them since their first release, when
it was easy to crash the compiler. They have matured enormously, but the `#row`
episode shows the ceiling has not gone away: the macro shipped, was reverted
after an IRGen crash on the pinned Swift 5.9.2 and 6.0 toolchains, and was
restored with its multi-column shapes gated to Swift 6.1 and later. That is
SwiftQL's first source-level API difference across compiler cells, and it exists
because of a compiler bug rather than a design choice.

## Who this is for

Any Swift project that uses SQLite.

Type-safe queries that still look like SQL are, I think, the lowest-friction way
to use SQLite from Swift.

Type safety is not the distinguishing property. Several Swift libraries offer
compile-time checked queries over SQLite without becoming ORMs. What separates
them is the shape of the source, and specifically whether it corresponds to the
statement it produces.

Chained builders do not. A query is assembled by attaching clauses to a table
type, in an order the builder accepts rather than the order SQL defines, using
method names that approximate SQL keywords without being them. The output is
SQL; the input is a Swift API that has to be learned on its own terms.

SwiftQL writes the statement in SQL's own clause order:

```swift
sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

Each clause appears once, under its SQL name, in SQL's grammatical order. There
is no rule to learn about where `WHERE` attaches or which receiver a clause
hangs off, because the answer is the one SQL already gave. The source is the
statement.

That is the bet the whole library makes, and it is what SQL as a first-class
construct actually means: not that queries are type-checked, and not that they
avoid strings, but that the language is present in the source with its own
grammar intact rather than paraphrased into an API. A query moves between SQL
and SwiftQL a clause at a time, in both directions, which is why porting is
mechanical and why what you already know about SQL keeps its value.

The other half of that goal is coverage. A first-class construct that only
handles simple statements is a demo. SwiftQL's aim is to express what SQLite
expresses: joins, grouping and `HAVING`, subqueries, compound queries, and
ordinary and recursive common table expressions today, with the remaining
surface tracked as conformance work rather than left undefined. See
[COMPATIBILITY.md](../COMPATIBILITY.md#sqlite-conformance-inventory) for the
evidence boundary.

There is also a broader point, aimed at the status quo rather than at any
library. Most SQLite code in Swift applications is still a string handed to a C
API or a driver, checked by nothing until it runs. That is the practice SwiftQL
exists to replace.

Once the PostgreSQL, MySQL, and SQL Server dialects land, the same argument
should apply to those.

One caveat worth stating plainly: the 1.x line is under active and fast-paced
development. v2 is the version to adopt.
