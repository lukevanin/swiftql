# Dialect parameter type-check harness

This harness measures what a dialect type parameter costs the Swift type
checker. It also shows what the parameter buys, and what it does to the error
messages. Issue #789 makes the measurement a condition of adoption.

Run it from the repository root:

```sh
Research/DialectParameterTypeCheck/measure.sh
```

The script writes into a new temporary directory. It writes nothing into the
repository.

## What the harness builds

The harness builds four modules. Each module holds one query surface. A module
holds one surface only, so a query file sees one overload set and never two.

| Module | Operand | Scope |
| --- | --- | --- |
| `GateCurrent` | `any XLExpression<T>` | columns carry no dialect |
| `GateExistential` | `any XLExpr<T, Dialect>` | columns carry the dialect |
| `GateConcrete` | `XLExpr<T, Dialect>` struct | columns carry the dialect |
| `GateWrapper` | `any XLExpr<T, Dialect>` | a wrapper re-types macro output |

`GateWrapper` answers one question. The `@SQLTable` macro emits metadata that
carries no dialect, and Swift has no generic associated types, so the metadata
type cannot take the dialect as a parameter. A wrapper that re-types each
column through a key-path dynamic member lookup is the only way to carry the
dialect without changing the macro. This module measures that way.

`generate.py` reads the operator and function declarations out of
`Sources/SwiftQL/Operators` and `Sources/SwiftQL/Functions`, so the signature
shapes agree with the shipped API. The bodies are removed, because the harness
measures the call site and not the body.

The harness restates every free operator that takes an expression. It restates
only part of the member surface, and it prints how much on every run. A member
it cannot restate names a type the harness does not define, or takes an operand
that is not an expression. Members in a constrained extension are not read. The
harness therefore understates the member half of the surface.

A concrete type such as `String` cannot conform to a protocol for every
dialect. A dialect surface therefore needs one more overload on each side of
every binary operator, which takes the value type directly. `generate.py`
writes those overloads. They are the cost the measurement reports.

## What the harness measures

- **Type-check time.** Each surface gets a query body of 30, 120 and 450
  clauses. The bodies are the same shape in each surface. The script reads the
  time of the function body from `-debug-time-function-bodies`, runs each
  measurement 15 times, and reports the median. The surfaces are interleaved
  inside each repetition, so drift across the run falls on all of them alike.
  A query that does not type-check stops the run with its diagnostics.
- **Refusal.** Each surface gets a SQLite-only operation, applied to a SQLite
  column, to a composed SQLite expression, to a PostgreSQL column, and to a
  composed PostgreSQL expression. The script reports which ones the compiler
  accepts. It reads a compile failure as a refusal only when the compiler names
  both dialects. Any other failure is reported as a fault in the harness.
- **Error text.** Each surface gets three ordinary mistakes: a wrong value
  type, a misspelled column, and two columns of different types. The script
  prints the first error of each one, or says the surface accepted the
  mistake.

## The recorded result

See [DialectParameterTypeCheckCost.md](../DialectParameterTypeCheckCost.md).
