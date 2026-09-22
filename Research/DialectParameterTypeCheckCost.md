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

## The overload set

`generate.py` reads the shipped declarations, so the harness carries the real
count and the real signature shapes.

| Surface | Overloads |
| --- | ---: |
| current | 115 |
| existential — `any XLExpr<T, Dialect>` | 259 |
| concrete — `XLExpr<T, Dialect>` struct | 259 |

The dialect surfaces are 2.25 times larger. The growth is not the dialect
parameter itself. A concrete type such as `String` cannot conform to a protocol
for every dialect, so a raw Swift value no longer lifts into an operand on its
own. Each binary operator therefore needs one more overload on each side.

## Type-check time of one query body

Median of seven runs, from `-debug-time-function-bodies`.

| Clauses | current | existential | concrete | existential | concrete |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 17.4 ms | 19.9 ms | 17.3 ms | +13.9 % | −0.8 % |
| 120 | 48.2 ms | 55.3 ms | 52.2 ms | +14.5 % | +8.2 % |
| 450 | 286.6 ms | 370.7 ms | 353.6 ms | +29.3 % | +23.4 % |

Three earlier runs of the same harness gave +13.7 to +19.0 percent at 30
clauses and +20.2 to +29.3 percent at 450 clauses. Read the figure as a band
and not as a point.

**The cost is not prohibitive.** The gap has the shape the spike predicted, and
it did not grow with the larger overload set. A 450-clause query is far larger
than any query in this repository, and it pays 60 to 85 milliseconds more. A 30
clause query pays 2.5 milliseconds more.

## What the parameter buys

A SQLite-only operation, `collate`, is offered on the SQLite dialect only.

| Receiver | current | existential | concrete |
| --- | --- | --- | --- |
| SQLite column | accepted | accepted | accepted |
| composed SQLite expression | accepted | accepted | accepted |
| PostgreSQL column | **accepted** | refused | refused |
| composed PostgreSQL expression | **accepted** | refused | refused |
| SQLite column compared to a PostgreSQL column | **accepted** | refused | refused |

The current surface accepts every one of them. That is the defect. Both
dialect surfaces refuse the PostgreSQL cases at the call site, and they refuse
the composed expression as well as the bare column.

## What the parameter does to the error text

| Mistake | Surface | First error |
| --- | --- | --- |
| wrong value type | current | `6:17: referencing operator function '==' on 'BinaryInteger' requires that 'XLColumnReference<String>' conform to 'BinaryInteger'` |
| | existential | `6:17: referencing operator function '==' on 'BinaryInteger' requires that 'XLColumnReference<String, XLGateSQLite>' conform to 'BinaryInteger'` |
| | concrete | `6:11: cannot convert value of type 'XLExpr<String, XLGateSQLite>' to expected argument type 'XLExpr<Optional<Int>, XLGateSQLite>'` |
| misspelled column | current | `6:11: value of type 'XLGateScope' has no member 'nmae'` |
| | existential | `6:11: value of type 'XLGateScope<XLGateSQLite>' has no member 'nmae'` |
| | concrete | `6:11: value of type 'XLGateScope<XLGateSQLite>' has no member 'nmae'` |
| two columns of different types | current | `6:17: binary operator '==' cannot be applied to operands of type 'XLColumnReference<String>' and 'XLColumnReference<Int>'` |
| | existential | `6:17: binary operator '==' cannot be applied to operands of type 'XLColumnReference<String, XLGateSQLite>' and 'XLColumnReference<Int, XLGateSQLite>'` |
| | concrete | `6:17: binary operator '==' cannot be applied to operands of type 'XLExpr<String, XLGateSQLite>' and 'XLExpr<Int, XLGateSQLite>'` |

The existential surface keeps the error kind, the wording and the column of
every one of the three. The only change is the dialect argument inside the
printed type name, which the parameter makes unavoidable. The accepted design
note shows the same change in its own evidence.

The concrete surface changes the first mistake. The error kind changes, the
wording changes, and the column moves from 17 to 11. The struct operand makes
the compiler report a conversion instead of a failed requirement.

## Recommendation

Adopt the **existential** surface, `any XLExpr<T, Dialect>`, which is the shape
the accepted design note describes.

- It refuses the operations the issue asks it to refuse, on a composed
  expression as well as on a column.
- It holds the diagnostics bar. The concrete surface does not.
- It costs 14 percent at a realistic query size and 29 percent at 450 clauses.
  The concrete surface is faster at a small query and no faster at a large one,
  so its speed does not pay for its diagnostics.

## One finding that changes the plan

The harness gives the scope its columns by hand. SwiftQL gets them from the
`@SQLTable` macro, which emits `XLColumnReference<T>` members on a nested
`MetaNamedResult` type, and `XLTable` names that type through an
`associatedtype`.

Swift has no generic associated types. `MetaNamedResult` therefore cannot
become `MetaNamedResult<Dialect>` while `XLTable` still names it. The query
scope can only carry the dialect in one of two ways:

1. A wrapper type around the generated metadata, which reads the columns
   through a key-path dynamic member lookup and re-types them.
2. The macro emits the dialect into the metadata, which is issue #687.

Issue #687 is recorded as depending on #789. This finding says the dependency
runs both ways for the scope, and that the two issues have to agree on which of
the two ways the scope takes before either one lands.
