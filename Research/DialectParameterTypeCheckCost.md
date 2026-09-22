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
count and the real signature shapes.

| Surface | Overloads |
| --- | ---: |
| current | 115 |
| each dialect surface | 259 |

The dialect surfaces are 2.25 times larger. The growth is not the dialect
parameter itself. A concrete type such as `String` cannot conform to a protocol
for every dialect, so a raw Swift value no longer lifts into an operand on its
own. Each binary operator therefore needs one more overload on each side.

## Type-check time of one query body

Median of 15 runs, from `-debug-time-function-bodies`.

| Clauses | current | existential | concrete | wrapper |
| ---: | ---: | ---: | ---: | ---: |
| 30 | 17.9 ms | 20.5 ms (+14.4 %) | 17.7 ms (−1.4 %) | 21.4 ms (+19.2 %) |
| 120 | 46.6 ms | 56.0 ms (+19.9 %) | 50.3 ms (+7.8 %) | 61.4 ms (+31.5 %) |
| 450 | 280.7 ms | 371.3 ms (+32.2 %) | 330.6 ms (+17.8 %) | 405.1 ms (+44.3 %) |

Five separate runs of the harness put the existential gap between 10 and 31
percent at 30 clauses, and between 22 and 32 percent at 450 clauses. Read the
figure as a band and not as a point.

**The cost is not prohibitive.** The gap keeps the shape the spike predicted,
and the larger overload set did not change that shape. A 450-clause query is
far larger than any query in this repository, and it pays 50 to 90
milliseconds more. A 30-clause query pays about 2.6 milliseconds more.

## What the parameter buys

A SQLite-only operation, `collate`, is offered on the SQLite dialect only.

| Receiver | current | existential | concrete | wrapper |
| --- | --- | --- | --- | --- |
| SQLite column | accepted | accepted | accepted | accepted |
| composed SQLite expression | accepted | accepted | accepted | accepted |
| PostgreSQL column | **accepted** | refused | refused | refused |
| composed PostgreSQL expression | **accepted** | refused | refused | refused |
| SQLite column against a PostgreSQL column | **accepted** | refused | refused | refused |

The current surface accepts every one of them. That is the defect. All three
dialect surfaces refuse the PostgreSQL cases at the call site, and they refuse
the composed expression as well as the bare column.

## What the parameter does to the error text

| Mistake | Surface | First error |
| --- | --- | --- |
| wrong value type | current | `6:17: referencing operator function '==' on 'BinaryInteger' requires that 'XLColumnReference<String>' conform to 'BinaryInteger'` |
| | existential | same, with `XLColumnReference<String, XLGateSQLite>` |
| | wrapper | same, with `XLColumnReference<String, XLGateSQLite>` |
| | concrete | `6:11: cannot convert value of type 'XLExpr<String, XLGateSQLite>' to expected argument type 'XLExpr<Optional<Int>, XLGateSQLite>'` |
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

- The concrete surface changes the wrong-value-type error. The kind changes,
  the wording changes, and the column moves from 17 to 11. A struct operand
  makes the compiler report a conversion instead of a failed requirement.
- The wrapper surface changes the misspelled-column error, which is the exact
  mistake the issue names.

## Recommendation

Adopt the **existential** surface, `any XLExpr<T, Dialect>`. It is the shape
the accepted design note describes.

- It refuses the operations the issue asks it to refuse, on a composed
  expression as well as on a column.
- It holds the diagnostics bar. Neither other surface does.
- It costs about 14 percent at a realistic query size and about 32 percent at
  450 clauses. The concrete surface is cheaper but pays for that with a worse
  message on the most common mistake of all, so its speed does not pay for its
  diagnostics.

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
