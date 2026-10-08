# What the dialect type parameter costs the type checker

**Recorded 22 September 2026.** Swift 6.4 (swiftlang-6.4.0.34.1), macOS 26.6.2,
Mac16,8 (Apple M4 Pro). Branch `claude/789-dialect-type-parameter`, from
`version/2.0` at `52c3d256`.

Issue #789 makes this measurement a condition of adoption. The
[dialect surface separation](../Documentation/Architecture/DialectSurfaceSeparation.md)
note measured a gap near 17 percent at 450 clauses on a small overload set, and
asked for the measurement again against the real one.

Reproduce with `Research/DialectParameterTypeCheck/measure.sh`. The method is in
[the harness README](DialectParameterTypeCheck/README.md).

## The four surfaces

| Surface | Operand | Scope |
| --- | --- | --- |
| current | `any XLExpression<T>` | columns carry no dialect |
| existential | `any XLExpr<T, Dialect>` | columns carry the dialect |
| concrete | `XLExpr<T, Dialect>` struct | columns carry the dialect |
| wrapper | `any XLExpr<T, Dialect>` | a wrapper re-types today's macro output |

The wrapper surface answers one question only: can the scope carry the dialect
while `@SQLTable` keeps emitting what it emits today? See
[the finding that changes the plan](#one-finding-that-changes-the-plan).

## The overload set

`generate.py` reads the shipped declarations, so the harness carries the real
signature shapes. It restates all 80 free operators that take an expression.
It restates 52 of the 156 members of an unconstrained `extension XLExpression`
block, and it prints that count on every run. A member it cannot restate names
a type the harness does not define, takes an operand that is not an
expression, or is written across several lines. Members in a constrained
extension are not read at all.

**The harness therefore understates the member half of the surface.** The real
gap can be larger than the gap below. It cannot be smaller for that reason.

| Surface | Overloads |
| --- | ---: |
| current | 132 |
| each dialect surface | 276 |

The dialect surfaces are 2.09 times larger. The growth is not the dialect
parameter itself. A concrete type such as `String` cannot conform to a protocol
for every dialect, so a raw Swift value no longer lifts into an operand on its
own. Each binary operator therefore needs one more overload on each side.

## Type-check time of one query body

Median of 15 runs, from `-debug-time-function-bodies`.

| Clauses | current | existential | concrete | wrapper |
| ---: | ---: | ---: | ---: | ---: |
| 30 | 19.1 ms | 21.5 ms (+12.4 %) | 18.3 ms (−4.3 %) | 22.6 ms (+18.0 %) |
| 120 | 49.2 ms | 56.8 ms (+15.4 %) | 50.7 ms (+3.0 %) | 64.0 ms (+30.2 %) |
| 450 | 292.5 ms | 353.3 ms (+20.8 %) | 338.6 ms (+15.8 %) | 413.6 ms (+41.4 %) |

The four surfaces are interleaved inside each repetition, so drift across the
run falls on all of them alike. A second run of the same harness put the
existential gap at +12.3 percent, +15.8 percent and +23.9 percent. Read each
figure as a band and not as a point. A 30-clause body takes about 19
milliseconds, so a small absolute change moves its percentage a long way.

**The cost is not prohibitive.** The gap keeps the shape the spike predicted,
and the larger overload set did not change that shape. A 450-clause query is
far larger than any query in this repository, and it pays about 60
milliseconds more. A 30-clause query pays about 2.4 milliseconds more.

## What the parameter buys

A SQLite-only operation, `collate`, is offered on the SQLite dialect only.

| Receiver | current | existential | concrete | wrapper |
| --- | --- | --- | --- | --- |
| SQLite column | accepted | accepted | accepted | accepted |
| composed SQLite expression | accepted | accepted | accepted | accepted |
| PostgreSQL column | not expressible | refused | refused | refused |
| composed PostgreSQL expression | not expressible | refused | refused | refused |
| SQLite column against a PostgreSQL column | not expressible | refused | refused | refused |

The current surface has no dialect, so it cannot express the last three rows
at all, and the harness does not write those fixtures for it. **That is the
defect.** A SQLite-only operation is offered on every expression
unconditionally, so no query can refuse it.

All three dialect surfaces refuse the PostgreSQL cases at the call site, and
they refuse the composed expression as well as the bare column. `measure.sh`
reads a refusal only when the compiler names both dialects. Any other compile
failure is reported as a fault in the harness, so a broken fixture cannot read
as evidence.

## What the parameter does to the error text

The wrong-value-type mistake compares a `String` column with a `Bool`
variable. A numeric mismatch would resolve to a standard-library operator, and
its message would say nothing about the surface under measurement.

| Mistake | Surface | First error |
| --- | --- | --- |
| wrong value type | current | `6:11: cannot convert value of type 'XLColumnReference<String>' to expected argument type 'Bool'` |
| | existential | same, with `XLColumnReference<String, XLGateSQLite>` |
| | wrapper | same, with `XLColumnReference<String, XLGateSQLite>` |
| | concrete | `6:11: cannot convert value of type 'XLExpr<String, XLGateSQLite>' to expected argument type 'XLExpr<Optional<Bool>, XLGateSQLite>'` |
| misspelled column | current | `6:11: value of type 'XLGateScope' has no member 'nmae'` |
| | existential | same, with `XLGateScope<XLGateSQLite>` |
| | concrete | same, with `XLGateScope<XLGateSQLite>` |
| | wrapper | `6:11: value of type 'XLGateScope<XLGateSQLite>' has no dynamic member 'nmae' using key path from root type 'XLGateMeta'` |
| two columns of different types | current | `6:17: binary operator '==' cannot be applied to operands of type 'XLColumnReference<String>' and 'XLColumnReference<Int>'` |
| | existential | same, with the dialect in each type |
| | concrete | same, with `XLExpr` in place of `XLColumnReference` |
| | wrapper | same as existential |

The existential surface keeps the error kind, the wording and the column of
every one of the three. The only change is the dialect argument inside the
printed type name, which the parameter makes unavoidable. The accepted design
note shows the same change in its own evidence.

Each of the other two surfaces regresses one message.

- The concrete surface changes the wrong-value-type error. It names
  `XLExpr<Optional<Bool>, XLGateSQLite>` as the expected type, which is a
  wrapper the author never wrote and an optional the author never asked for.
  The current surface names the plain value type `Bool`.
- The wrapper surface changes the misspelled-column error, which is the exact
  mistake the issue names.

## Recommendation

Adopt the **existential** surface, `any XLExpr<T, Dialect>`. It is the shape
the accepted design note describes.

- It refuses the operations the issue asks it to refuse, on a composed
  expression as well as on a column.
- It holds the diagnostics bar. Neither other surface does.
- It costs about 12 percent at a realistic query size and about 21 percent at
  450 clauses. The concrete surface is cheaper by 5 to 16 percent, but it pays
  for that with a worse message on a wrong value type, which is a common
  mistake. That trade is not worth taking.

## One finding that changes the plan

The harness gives the scope its columns by hand. SwiftQL gets them from the
`@SQLTable` macro, which emits `XLColumnReference<T>` members on a nested
`MetaNamedResult` type, and `XLTable` names that type through an
`associatedtype`.

Swift has no generic associated types. `MetaNamedResult` therefore cannot
become `MetaNamedResult<Dialect>` while `XLTable` names it through an
`associatedtype`. The query scope can carry the dialect in one of two ways
only:

1. A wrapper around the generated metadata, which re-types each column through
   a key-path dynamic member lookup. This is the `wrapper` surface above. It
   refuses the right operations, but it is the slowest of the three and it
   breaks the misspelled-column message. **It fails this issue's diagnostics
   constraint.**
2. The macro emits the dialect into the metadata, and `XLTable` stops naming
   the metadata type through a plain `associatedtype`. That is issue #687.

Option 1 is measured and rejected. Option 2 is therefore the only way left, so
**the scope part of #789 cannot land before #687**. Issue #687 records itself
as depending on #789. For the operators and the expression nodes that
direction is right. For the scope the direction is the other way, and the two
issues have to be sequenced together.

## Re-measured on the shipped surface: one predicate of joined comparisons

**Recorded 6 October 2026** for issue #789. Swift 6.4, macOS 26.6.2, Apple M4
Pro. Base: `version/2.0` at `17743faa`.

The measurement above gives every clause its own statement, and no clause holds
more than two operators. A query's filter is usually one `Where` that joins
several comparisons with `&&`, and the type checker solves that whole predicate
as one expression. The harness above never measured that shape.

Issue #789's prototype, on the branch `claude/789-dialect-type-parameter`,
carries the dialect through the whole SwiftQL surface, and its test suite
passes. `measure-shipped.sh` type-checks the same bodies against real builds of
SwiftQL. Three builds are compared:

- **base**: `version/2.0`.
- **existential**: the surface this record recommends. Operands are
  `any XLExpression<T, D>`, generic over the dialect, and a Swift value is a
  separate dialect-free protocol that takes one extra overload on each side of
  every binary operator.
- **universal**: the same, except that a Swift value keeps its `XLExpression`
  conformance with the dialect `XLUniversalDialect`, so users' custom types and
  enums compile unchanged.

Median of 7 runs, from `-debug-time-function-bodies`.

| Body | base | existential | universal |
| --- | ---: | ---: | ---: |
| 30 separate clauses | 19.9 ms | 26.3 ms (+32 %) | 30.5 ms (+53 %) |
| 120 separate clauses | 63.7 ms | 79.5 ms (+25 %) | 100.2 ms (+57 %) |
| 450 separate clauses | 449.7 ms | 520.3 ms (+16 %) | 631.6 ms (+40 %) |
| one `Where` of 2 terms | 7.5 ms | 10.9 ms (+46 %) | 11.2 ms (+51 %) |
| one `Where` of 4 terms | 9.0 ms | 22.9 ms (+156 %) | 32.7 ms (+265 %) |
| one `Where` of 6 terms | 10.5 ms | 72.4 ms (+588 %) | 129.6 ms (+1,132 %) |
| one `Where` of 8 terms | 11.8 ms | 279.2 ms (+2,266 %) | 625.0 ms (+5,197 %) |

The separate-clause bodies reproduce the result above: the existential surface
costs +16 to +32 percent. A single predicate does not. Its cost grows
exponentially with the number of terms.

A mistake in the last term of one predicate shows the same growth, in the
wall time of one compile:

| Terms | base | existential | universal |
| ---: | ---: | ---: | ---: |
| 4, misspelled column | 1.3 s | 1.5 s | 1.8 s |
| 6, misspelled column | 1.5 s | 6.1 s | 16.7 s |
| 5, wrong value type | 1.4 s | 8.2 s | 21.5 s |
| 6, wrong value type | 1.6 s | *unable to type-check in reasonable time* | *unable to type-check in reasonable time* |

At six terms both dialect surfaces replace the error with "the compiler is
unable to type-check this expression in reasonable time". That breaks the
diagnostics bar of #789 for an ordinary mistake in an ordinary filter.

### What causes it

`measure-chains.sh` writes stand-in libraries with SwiftQL's operator counts
and times one predicate of 4 to 16 comparisons:

| Shape | 4 | 8 | 12 | 16 |
| --- | ---: | ---: | ---: | ---: |
| base, `any E<T>` | 12.1 ms | 13.7 ms | 16.2 ms | 18.6 ms |
| generic, `any E<T, D>`, no universal overloads | 14.0 ms | 79.1 ms | 1,430 ms | 28,001 ms |
| mixed, generic plus universal overloads | 18.4 ms | 262 ms | 6,855 ms | over budget |
| generic operand types `<L: E, R: E>` | 12.8 ms | 15.1 ms | 21.8 ms | 23.0 ms |
| generic operand types, returned as `any E<Bool, D>` † | 64.1 ms | 10,004 ms | 15,387 ms | 22,805 ms |
| concrete `X<T, D>` struct † | 23.5 ms | 139 ms | 611 ms | 1,582 ms |

† **Withdrawn.** These two rows timed the type checker's error path, not the
chain. The chains hold optional columns, so from four terms on their type is
`Optional<Bool>`, and these two shapes returned `Bool`. Re-measured with the
right result type, both are as fast as the base shape; see
[the adopted design](#the-adopted-design-one-expression-protocol-per-dialect).

- The cause is the dialect generic on the operators, not the treatment of
  Swift values. With no universal overloads at all, `any E<T, D>` operands take
  28 seconds for 16 terms. The overloads for a Swift value multiply the cost.
- Generic operand types solve a bare predicate in linear time. The finding
  recorded here that they do not once the result is converted to an
  existential is withdrawn (see † above). On the shipped surface they also
  needed `Optional` to lose its conditional `XLExpression` conformance, which
  otherwise made even the bare predicate exponential.
- The finding that the concrete struct surface grows is withdrawn too (†).

No shape that keeps the operators generic over the dialect, and so one copy
of them, kept a joined predicate within the budget of this record on the
shipped surface.

## The adopted design: one expression protocol per dialect

**Recorded 6 October 2026** for issue #789. Swift 6.4, macOS 26.6.2, Apple M4
Pro. Base: `version/2.0` at `17743faa`; the expression surface is unchanged
on `version/2.0` since.

The owner chose design (b): concrete, non-generic operators for each dialect.
Each dialect has its own expression protocol, `XLSQLiteExpression` for SQLite,
and its own copy of every operator and function that composes expressions,
taking `any XLSQLiteExpression<T>` and returning `some XLSQLiteExpression<R>`.
The copies are generated from one set of templates
(`scripts/dialect-surface/`).

- A column conforms where its model's dialect is that dialect:
  `extension XLColumnReference: XLSQLiteExpression where Dialect == XLSQLiteDialect`.
- A Swift value, an optional of one, and a named binding conform for every
  dialect. An enum and an `XLCustomType` conform for SQLite, so a user's
  custom type keeps compiling: `XLCustomType` and `XLEnum` include
  `XLSQLiteExpression`. For another dialect the type declares that dialect's
  protocol too, because a protocol cannot be made to refine another from
  outside.
- A node such as `XLBinaryOperatorExpression<T>` conforms for every dialect.
  The opaque result is what keeps a composed expression in one dialect: the
  result of a second dialect's `==` is `some SecondExpression<Bool>`, which is
  not known to be a SQLite expression.

The operand is the dialect's own protocol because that is what measured best.
The alternative kept the prototype's `any XLExpression<T, XLSQLiteDialect>`
operand, non-generic, and gave each operator two more disfavoured overloads
per variant so that a Swift value, whose dialect is a universal marker, can
stand on either side. In a stand-in of the same size (not kept in the
repository) it cost about three times the base on a 16-term chain, and seven
to nine times the base on the error path of a wrong value type at 6 and 8
terms. The protocol form costs what the base costs, below.

### Stand-ins: one predicate of joined comparisons

`measure-chains.sh`, with the `-ret` and `concrete` rows corrected to return
`Optional<Bool>`:

| Shape | 4 | 8 | 12 | 16 |
| --- | ---: | ---: | ---: | ---: |
| base | 16.6 ms | 26.3 ms | 22.9 ms | 27.7 ms |
| generic | 17.8 ms | 89.3 ms | 1,631 ms | 32,986 ms |
| mixed | 23.9 ms | 302 ms | 7,819 ms | 14,189 ms |
| operands | 17.3 ms | 18.3 ms | 29.1 ms | 30.0 ms |
| operands-ret | 21.7 ms | 17.1 ms | 22.0 ms | 28.7 ms |
| concrete | 14.6 ms | 15.7 ms | 20.2 ms | 18.8 ms |
| **dialect** (adopted) | 19.6 ms | 19.9 ms | 48.9 ms | 24.5 ms |
| **dialect-ret** | 13.9 ms | 16.4 ms | 21.2 ms | 24.9 ms |
| **dialect-two** (two dialects visible) | 14.9 ms | 19.4 ms | 24.9 ms | 31.0 ms |

Single runs; a row's variation between lengths is noise of a few
milliseconds. The adopted shape is linear, and stays so when a module sees a
second dialect's operators too.

### The shipped surface

`measure-shipped.sh base=<version/2.0> b=<this branch>`, median of 7 runs:

| Body | base | b |
| --- | ---: | ---: |
| 30 separate clauses | 29.8 ms | 31.0 ms (+4 %) |
| 120 separate clauses | 83.4 ms | 100.3 ms (+20 %) |
| 450 separate clauses | 685.5 ms | 657.3 ms (−4 %) |
| one `Where` of 2 terms | 9.5 ms | 10.6 ms (+12 %) |
| one `Where` of 4 terms | 12.6 ms | 15.6 ms (+23 %) |
| one `Where` of 6 terms | 12.8 ms | 14.3 ms (+12 %) |
| one `Where` of 8 terms | 14.5 ms | 19.6 ms (+35 %) |
| one `Where` of 12 terms | 19.4 ms | 25.5 ms (+31 %) |
| one `Where` of 16 terms | 21.9 ms | 23.8 ms (+9 %) |

The 450-clause body is within the budget of #799 (+16 to +24 percent). A
joined predicate costs a few milliseconds more than the base and grows with
the base, linearly; the prototype's 8-term predicate took 279 ms.

A mistake in the last term of one predicate, wall time of one compile and the
first error:

| Terms | misspelled column, base | b | wrong value type, base | b |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 1.3 s | 1.4 s | 1.9 s | 1.9 s |
| 4 | 1.4 s | 1.4 s | 1.8 s | 2.0 s |
| 6 | 1.5 s | 1.7 s | 2.2 s | 2.4 s |
| 8 | 2.3 s | 2.6 s | 3.8 s | 4.3 s |
| 12 | 5.4 s | 7.4 s | 13.9 s | 14.3 s |
| 16 | 26.1 s | 25.9 s | 12.1 s ‡ | 12.8 s ‡ |

Every row reports the real error, and the same one as the base: the
misspelled column's message is byte-identical, and the wrong value type's
differs only in the printed column type,
`XLColumnReference<Int, XLSQLiteDialect>`. ‡ At 16 terms the base already
gives up on a wrong value type with "unable to type-check this expression in
reasonable time", and b gives up the same way at the same cost.

### Library build time and size

Rebuilding the `SwiftQL` target after touching every source, median of three
interleaved runs, and the total size of its object files:

| | base | b |
| --- | ---: | ---: |
| debug build | 10.9 s | 11.7 s (+7 %) |
| release build | 16.4 s | 17.4 s (+6 %) |
| release object files | 15,595,936 bytes | 15,827,312 bytes (+1.5 %) |

The SQLite surface is the same overloads as before, one copy, so the library
grows by the new protocol's conformances and the generic metadata of the
dialect-carrying types.


## Clauses and statements (issue #822)

**Recorded 7 October 2026** for issue #822. Swift 6.4, macOS 26.6.2, Apple M4
Pro. Base: `version/2.0` at `af954b8e`.

The adopted design typed expressions by dialect, and left clauses and
statements dialect-free. Issue #822 types them too, without a generic
dialect parameter on any operator:

- Every clause carries its statement's dialect: `Where<Dialect>`,
  `From<Dialect>`, `Select<Row, Dialect>`, and so on. The initializers that
  take an expression are declared once for each dialect, generated from the
  templates like the operators, and take the dialect's expression protocol,
  `any XLSQLiteExpression<Bool>` for SQLite. A clause that takes a table is
  generic over the table and requires `T.XLModelDialect == Dialect`.
- The result builder is generic over the dialect,
  `XLDialectQueryExpressionBuilder<Dialect>`, and `XLQueryExpressionBuilder`
  names SQLite's. Its one `buildExpression` takes any clause whose dialect is
  the builder's. Each statement of the body is type-checked inside that call,
  so the builder's dialect is the context in which the clause's initializer is
  chosen: `Where(true)` in a second dialect's query takes that dialect's
  initializer, and the predicate inside a `Where` is solved against one
  dialect's protocol, as an operator's operands are.
- The statements carry the dialect, and a statement inside another one is an
  `any XLDialectQueryStatement<Row, Dialect>`.

The prototype of #789 reported that a `Where<D>` breaks the misspelled-column
message ("generic parameter 'D' could not be inferred"). That `Where` took its
dialect from its expression. Here the builder supplies it, so the dialect is
bound before the expression is solved, and the message is unchanged.

### One predicate of joined comparisons

`measure-shipped.sh base=<version/2.0> branch=<this branch>`, median of 7
runs:

| Body | base | branch |
| --- | ---: | ---: |
| 30 separate clauses | 21.6 ms | 21.5 ms (−1 %) |
| 120 separate clauses | 68.4 ms | 68.5 ms (+0 %) |
| 450 separate clauses | 462.4 ms | 463.4 ms (+0 %) |
| one `Where` of 2 terms | 8.6 ms | 10.0 ms (+16 %) |
| one `Where` of 4 terms | 10.5 ms | 11.9 ms (+14 %) |
| one `Where` of 6 terms | 12.2 ms | 13.6 ms (+12 %) |
| one `Where` of 8 terms | 13.7 ms | 15.2 ms (+11 %) |
| one `Where` of 12 terms | 17.0 ms | 18.6 ms (+9 %) |
| one `Where` of 16 terms | 20.7 ms | 22.2 ms (+7 %) |

The separate-clause bodies are expressions only, which this change does not
touch. A `Where` costs about 1.5 ms more at every length: the builder's
`buildExpression` and the clause's dialect, once per query. The growth with
the number of terms is the base's.

The same bodies in a module that also sees the compile-fail second dialect's
surface, median of 5:

| Terms | base | branch |
| ---: | ---: | ---: |
| 4 | 14.9 ms | 16.1 ms |
| 8 | 20.3 ms | 21.5 ms |
| 12 | 25.4 ms | 26.6 ms |
| 16 | 30.7 ms | 32.1 ms |

A mistake in the last term of one predicate, wall time of one compile and the
first error: at every length from 2 to 16 terms, the branch takes the same
time as the base, within 0.1 s, and reports the same error. The misspelled
column's message is byte-identical (`value of type 'GateRow.MetaNamedResult'
has no member 'txet0'`), and so is the wrong value type's. At 16 terms both
give up on a wrong value type in 8.6 s and 8.7 s.

| Terms | misspelled column, base | branch | wrong value type, base | branch |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 1.3 s | 1.3 s | 1.3 s | 1.3 s |
| 4 | 1.4 s | 1.4 s | 1.4 s | 1.4 s |
| 6 | 1.6 s | 1.6 s | 1.7 s | 1.7 s |
| 8 | 2.3 s | 2.3 s | 2.7 s | 2.7 s |
| 12 | 4.9 s | 5.0 s | 10.1 s | 10.1 s |
| 16 | 16.4 s | 16.4 s | 8.6 s ‡ | 8.7 s ‡ |

`measure-chains.sh`'s stand-ins model operators only, so they do not change;
re-run on this machine, the `dialect` shape takes 12.7, 15.4, 19.1, and
22.6 ms at 4, 8, 12, and 16 terms, and `dialect-two` 13.8, 19.2, 23.1, and
28.9 ms.

### Library build time and size

Rebuilding the `SwiftQL` target after touching every source, three
interleaved runs each, and the size of its release objects:

| | base | branch |
| --- | ---: | ---: |
| debug build | 5.5 to 5.7 s | 5.5 to 5.8 s |
| release build | 10.6 to 10.8 s | 10.5 to 10.7 s |
| release object files | 10,113,352 bytes | 10,177,000 bytes (+0.6 %) |
| release `SwiftQL.o` | 5,027,176 bytes | 5,130,176 bytes (+2.0 %) |

These builds use the toolchain's newer build system, so they are not
comparable with the table for #789 above, which used the other one.

### The static field's run-time check

A static row field's factories still take their expression erased, so the
field checks its dialect with a `Mirror` walk when it is built. In a debug
build, building a field of a column takes 1.8 µs, which the walk barely
touches, because a column records its dialect; a field of an expression that
joins eight terms takes 24 µs, of which the walk is 22 µs. A field is built
when its layout is built, not per row.


## The macros' value slots (issue #825)

**Recorded 8 October 2026** for issue #825. Swift 6.4, macOS 26.6.2, Apple M4
Pro. Base: `version/2.0` at `3ab82d40`. The machine was shared with other
builds throughout, so every time below is slower than the same body in the
#822 tables above; base and branch were interleaved inside each repetition,
so the load fell on both alike.

The macros' value slots took any expression after #822: an assignment in
`Setting { row in ... }`, the generated `MetaUpdate`, `MetaInsert`, and
`SQLReader` initializers, `columns(...)`, and `#row(...)`. Issue #825 types
them by the model's dialect, without a generic dialect parameter on any
operator:

- Each dialect's generated surface declares a generic typealias on its
  dialect type, `XLAnyExpression<T> = any XLSQLiteExpression<T>` for SQLite,
  and the macros write a slot as `SwiftQL.XLSQLiteDialect.XLAnyExpression<T>`
  from the dialect type they already know. The typealias names the
  existential itself, so it needs only generic typealiases and parameterized
  existentials, not a compiler that specializes a typealias of a protocol.
- `#row(...)` builds SQLite rows, so its declaration takes
  `any XLSQLiteExpression<C>`.
- A slot stores its expression erased, as before, so a read of a `Setting`
  slot returns it wrapped in `XLTypeAffinityExpression`, which is an
  expression of every dialect.

### Type-check time

`measure-shipped.sh base=<version/2.0> branch=<this branch>`, median of 9
runs. The `setting` bodies are one `Setting` closure of 10, 40, and 120
assignments of values, `nil`, columns, and composed expressions;
`columns-10` passes ten composed or column arguments to `columns(...)`, and
`row-6` six to `#row(...)`.

| Body | base | branch |
| --- | ---: | ---: |
| 30 separate clauses | 45.7 ms | 47.3 ms (+4 %) |
| 120 separate clauses | 137.1 ms | 140.1 ms (+2 %) |
| 450 separate clauses | 1157.7 ms | 943.4 ms (−19 %) |
| one `Where` of 2 terms | 18.5 ms | 19.4 ms (+5 %) |
| one `Where` of 4 terms | 20.0 ms | 18.6 ms (−7 %) |
| one `Where` of 6 terms | 25.7 ms | 22.2 ms (−14 %) |
| one `Where` of 8 terms | 24.9 ms | 25.4 ms (+2 %) |
| one `Where` of 12 terms | 32.5 ms | 31.6 ms (−3 %) |
| one `Where` of 16 terms | 44.0 ms | 36.5 ms (−17 %) |
| `Setting` of 10 assignments | 22.7 ms | 23.6 ms (+4 %) |
| `Setting` of 40 assignments | 35.8 ms | 33.4 ms (−7 %) |
| `Setting` of 120 assignments | 86.8 ms | 89.8 ms (+3 %) |
| `columns(...)` of 10 arguments | 22.5 ms | 23.5 ms (+4 %) |
| `#row(...)` of 6 arguments | 16.7 ms | 18.9 ms (+13 %) |

The clause and predicate bodies use no value slot, and every difference in
them is within the run-to-run spread under this load, in both directions.
A `Setting` body grows with its assignments at the base's rate: each
assignment is its own statement, and choosing among the three subscripts
does not depend on the slot's existential. A first, five-run pass made after
only the `Setting` slots were converted gave the same picture (setting-120
112.6 ms base, 97.6 ms branch).

A mistake in the last term of one predicate, user plus system CPU time of one
compile, median of 3 (7 at 6 and 8 terms), with the same first error on both:

| Terms | misspelled column, base | branch | wrong value type, base | branch |
| ---: | ---: | ---: | ---: | ---: |
| 6 | 1.9 s | 1.9 s | 2.0 s | 2.0 s |
| 8 | 2.8 s | 2.8 s | 3.4 s | 3.3 s |
| 12 | 7.3 s | 7.4 s | 12.8 s | 13.1 s |
| 16 | 22.8 s | 22.8 s | 10.9 s ‡ | 10.8 s ‡ |

‡ Both give up ("unable to type-check this expression in reasonable time").
The misspelled column's message is byte-identical (`value of type
'GateRow.MetaNamedResult' has no member 'txet0'`), and the type-safety gate's
three pinned messages are unchanged. `measure-shipped.sh` times one compile
of each by wall clock, which on this shared machine varied by up to a factor
of two between neighbouring runs of the same file, so these were re-timed by
CPU time and repeated.

### Library build time and size

Rebuilding the `SwiftQL` target after touching every source, three
interleaved runs each, and the loaded size of the release `SwiftQL.o`. The
object files' sizes on disk include the source paths, which differ in length
between the two checkouts, so the sections are compared instead.

| | base | branch |
| --- | ---: | ---: |
| debug build | 8.0 to 12.2 s | 7.3 to 13.5 s |
| release build | 14.0 to 14.6 s | 13.3 to 14.9 s |
| release `SwiftQL.o`, loaded sections | 1,808,056 bytes | 1,811,352 bytes (+0.2 %) |
| release `SwiftQL.o`, `__text` | 1,087,744 bytes | 1,090,320 bytes (+0.2 %) |

The library's own code grows only by SwiftQL's own `@SQLResult` models
(`SQLScalarResult`, `SQLRow2` to `SQLRow6`), whose generated slots now wrap a
read in `XLTypeAffinityExpression`, and by the conformance of
`XLLegacyDynamicValueExpression`, which the first version of this change
added. The review moved the read into the column slots and dropped that
conformance, which can only shrink the library; the numbers above are from
before it.
