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

The harness builds three modules. Each module holds one query surface. A
module holds one surface only, so a query file sees one overload set and never
two.

| Module | Operand | Result |
| --- | --- | --- |
| `GateCurrent` | `any XLExpression<T>` | `some XLExpression<U>` |
| `GateExistential` | `any XLExpr<T, Dialect>` | `some XLExpr<U, Dialect>` |
| `GateConcrete` | `XLExpr<T, Dialect>` struct | `XLExpr<U, Dialect>` struct |

`generate.py` reads the operator and function declarations out of
`Sources/SwiftQL/Operators` and `Sources/SwiftQL/Functions`. The overload count
and the signature shapes therefore agree with the shipped API. The bodies are
removed, because the harness measures the call site and not the body.

A concrete type such as `String` cannot conform to a protocol for every
dialect. A dialect surface therefore needs one more overload on each side of
every binary operator, which takes the value type directly. `generate.py`
writes those overloads. They are the cost the measurement reports.

## What the harness measures

- **Type-check time.** Each surface gets a query body of 30, 120 and 450
  clauses. The bodies are the same shape in each surface. The script reads the
  time of the function body from `-debug-time-function-bodies`, runs each
  measurement seven times, and reports the median.
- **Refusal.** Each surface gets a SQLite-only operation, applied to a SQLite
  column, to a composed SQLite expression, to a PostgreSQL column, and to a
  composed PostgreSQL expression. The script reports which ones the compiler
  accepts.
- **Error text.** Each surface gets three ordinary mistakes: a wrong value
  type, a misspelled column, and two columns of different types. The script
  prints the first error of each one.

## The recorded result

See [DialectParameterTypeCheckCost.md](../DialectParameterTypeCheckCost.md).
