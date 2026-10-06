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
| generic operand types, returned as `any E<Bool, D>` | 64.1 ms | 10,004 ms | 15,387 ms | 22,805 ms |
| concrete `X<T, D>` struct | 23.5 ms | 139 ms | 611 ms | 1,582 ms |

- The cause is the dialect generic on the operators, not the treatment of
  Swift values. With no universal overloads at all, `any E<T, D>` operands take
  28 seconds for 16 terms. The overloads for a Swift value multiply the cost.
- Generic operand types solve a bare predicate in linear time, but not one
  whose result is converted to an existential, as a helper that returns
  `any XLExpression<Bool, D>` does: 10 seconds for 8 terms. On the shipped
  surface they also need `Optional` to lose its conditional `XLExpression`
  conformance, which otherwise makes even the bare predicate exponential.
- The concrete struct surface grows too, more slowly.

No shape measured keeps a joined predicate within the budget of this record.
