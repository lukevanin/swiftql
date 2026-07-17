# Enum Values

Store a closed set of values as a type-safe Swift enum.

## Overview

An enum that conforms to ``XLEnum`` can be used anywhere its raw value could be
used: as a table column, a query result, a literal, or a bound parameter. SwiftQL
provides the raw-value encoding and decoding implementations.

A conforming enum must:

- use a supported intrinsic raw type such as `Int`, `Double`, or `String`;
- conform to ``XLEnum`` and declare its ``XLExpression/T`` associated type as
  `Self`; and
- implement ``XLLiteral/sqlDefault()`` by returning any valid case.

The `sqlDefault()` value is a construction and introspection placeholder.
SwiftQL uses it while determining the typed columns of a statement. It is not a
database default, is not written by that introspection, and is never used to
recover from a decoding error.

## Define integer- and string-backed enums

These enums use SQLite `INTEGER` and `TEXT` raw values respectively:

<!-- test: XLDocumentationTests.testDocumentationEnumValues -->
```swift
import SwiftQL

enum JobPriority: Int, XLEnum {
    typealias T = Self

    case low = 0
    case high = 1

    static func sqlDefault() -> JobPriority {
        .low
    }
}

enum JobState: String, XLEnum {
    typealias T = Self

    case queued
    case running

    static func sqlDefault() -> JobState {
        .queued
    }
}
```

The raw-value declaration supplies `RawRepresentable`. `XLEnum` supplies
``XLLiteral/init(reader:at:)``, ``XLBindable/bind(context:)``, and SQL literal
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

Use enum values when inserting rows and bind them to prepared requests in the
same way as intrinsic values:

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

var request = database.makeRequest(with: runningJobs)
request.set(stateParameter, .running)
let summaries = try request.fetchAll()
```

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
