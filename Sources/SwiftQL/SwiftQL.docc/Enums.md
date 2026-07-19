# Enum Values

Store a closed set of values as a type-safe Swift enum.

## Overview

An enum that conforms to ``XLEnum`` can be used anywhere its raw value could be
used: as a table column, a query result, a literal, or a bound parameter. SwiftQL
provides the raw-value encoding and decoding implementations.

A conforming enum must:

- use a supported intrinsic raw type such as `Int`, `Double`, or `String`;
- conform to ``XLEnum`` and declare its ``XLExpression/T`` associated type as
  `Self`.

An explicit `sqlDefault()` value is needed only for legacy `SQLReader` result
introspection. `XLLiteral` provides a default implementation that stops with a
migration diagnostic if that legacy path reaches an enum without a placeholder.
Generated static row layouts do not call it, and it is never used to recover
from a decoding error.

A plain Swift enum, or an `XLEnum` that retains v1 expression and operator
behavior, does not need to declare `sqlDefault()` when it is encoded by an
`XLValueCodec` and selected through a generated static row layout. Supply an
intrinsic storage carrier such as `String.self` or `Int.self` to
`staticResultField`; the layout retains that codec and decodes the enum only
when SQLite returns a row. Override `sqlDefault()` only while the enum also uses
legacy result introspection.

## Define integer- and string-backed enums

These enums use SQLite `INTEGER` and `TEXT` raw values respectively:

<!-- test: XLDocumentationTests.testDocumentationEnumValues -->
```swift
import SwiftQL

enum JobPriority: Int, XLEnum {
    typealias T = Self

    case low = 0
    case high = 1

    // The examples below use the legacy result path.
    static func sqlDefault() -> JobPriority {
        .low
    }
}

enum JobState: String, XLEnum {
    typealias T = Self

    case queued
    case running

    // The examples below use the legacy result path.
    static func sqlDefault() -> JobState {
        .queued
    }
}
```

The raw-value declaration supplies `RawRepresentable`. `XLEnum` supplies
``XLLiteral/init(reader:)``, ``XLBindable/bind(context:)``, and SQL literal
encoding by delegating to the enum's raw value.

## Use enums in tables and query results

Enum columns can be required or optional. They can also appear in an
`@SQLResult` projection:

<!-- test: XLDocumentationTests.testDocumentationEnumValues -->
```swift
@SQLTable struct Job: Equatable {
    let id: String
    let priority: JobPriority
    let state: JobState
    let previousState: JobState?
}

@SQLResult struct JobSummary: Equatable {
    let id: String
    let priority: JobPriority
    let state: JobState
    let previousState: JobState?
}
```

Use enum values when inserting rows. For a reusable prepared request, keep the
enum parameter in the static layout and put its normalized raw value in an
immutable packet for each invocation:

<!-- test: XLDocumentationTests.testDocumentationEnumValues -->
```swift
try database.makeRequest(with: sqlCreate(Job.self)).execute()
try database.makeRequest(
    with: sqlInsert(
        Job(
            id: "build-docs",
            priority: .high,
            state: .running,
            previousState: nil
        )
    )
).execute()

let stateParameter = XLNamedBindingReference<JobState>(name: "state")
let runningJobs = sql { schema in
    let job = schema.table(Job.self)
    let summary = JobSummary.columns(
        id: job.id,
        priority: job.priority,
        state: job.state,
        previousState: job.previousState
    )
    Select(summary)
    From(job)
    Where(job.state == stateParameter)
}

let request = database.makeRequest(with: runningJobs)
let stateSlot = request.parameterLayout.slot(for: .named("state"))!
let runningBindings = try XLInvocationBindings<XLSQLiteValue>(
    layout: request.parameterLayout,
    bindings: [
        try XLInvocationBinding(
            slot: stateSlot,
            value: .text(JobState.running.rawValue)
        )
    ]
).validatingComplete()
let summaries = try request.fetchAll(bindings: runningBindings)
```

The `JobState` declaration is still the expression's literal type, so its
operators and column comparisons remain type checked. The invocation packet
does not carry a mutable `JobState`; it carries the SQLite `TEXT` value that the
driver binds. The layout, including the parameter's type and nullability, does
not change when `.queued` and `.running` are used in separate calls.

The mutating `set(stateParameter, .running)` form remains available for v1
source compatibility. It immediately normalizes the enum into a compatibility
packet stored in that request copy. Prefer an explicit packet for repeated
calls or when composing bindings from multiple call sites. The packet is
`Sendable`; the current request facade does not itself promise cross-task use.

For an optional enum, SQL `NULL` decodes as `nil`; a recognized non-`NULL` raw
value decodes as the matching case.

## Handle unknown stored values

SQLite may contain a raw value that the Swift enum no longer recognizes, for
example after schema drift or a write performed outside the application.
Fetching that row throws ``XLColumnReadError`` with an
``XLColumnReadError/Failure/invalidValue(actualValue:)`` failure:

<!-- test: XLDocumentationTests.testDocumentationEnumValues -->
```swift
let allJobs = sql { schema in
    let job = schema.table(Job.self)
    Select(job)
    From(job)
}

do {
    _ = try database.makeRequest(with: allJobs).fetchAll()
} catch let error as XLColumnReadError {
    print(error)
}
```

This applies equally to integer-backed, string-backed, and optional enum
columns. Optionality only permits SQL `NULL`; it does not make an unknown
non-`NULL` raw value valid. SwiftQL does not call `sqlDefault()` in any of these
failure cases.
