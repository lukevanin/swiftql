# Real Values

Render and bind SQLite `REAL` values without changing non-finite `Double`
semantics.

## Inline literals

SQLite does not define bare numeric literal tokens for NaN or positive and
negative infinity. SwiftQL therefore renders only finite `Double` values
inline. ``XLiteEncoder/makeValidatedSQL(_:)`` throws
``XLSQLValueEncodingError/nonFiniteRealLiteral(value:expressionType:)`` for
all three non-finite values before SQLite parses the statement.

The source-compatible nonthrowing ``XLiteEncoder/makeSQL(_:)`` overload never
emits `nan` or `inf`. It retains the failure in
``XLEncoding/valueEncodingError``; every SwiftQL execution and static-descriptor
boundary checks that error before preparing SQL.

Use validated rendering when constructing standalone encodings:

<!-- test: XLDocumentationTests.testDocumentationRealValues -->
```swift
do {
    _ = try XLiteEncoder(dialect: XLSQLiteDialect())
        .makeValidatedSQL(Double.infinity)
}
catch let error as XLSQLValueEncodingError {
    // The error identifies the rejected value and expression type.
    print(error.localizedDescription)
}
```

## Bound values

SQLite's C binding API preserves positive and negative infinity as `REAL`, so
SwiftQL permits both values through bound parameters. SQLite converts a bound
IEEE 754 NaN to SQL `NULL`; SwiftQL rejects that value with
``XLSQLValueEncodingError/realBindingWouldBecomeNull(value:valueType:context:)``
instead of silently changing its meaning. The error retains the parameter or
property coding context.

This policy applies to legacy mutable requests, immutable invocation packets,
intrinsic query captures, contextual codecs that produce SQLite `REAL` values,
and the GRDB driver boundary. Supplying a normalized
`XLSQLiteValue.real(_:)` directly does not bypass the NaN check.

Finite values, including the largest finite magnitude, the least nonzero
magnitude, negative values, and signed zero, remain valid inline and bound
values. Their runtime representation follows SQLite's native `REAL` behavior.
