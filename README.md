# SwiftQL

SwiftQL lets you write SQL queries using familiar, type-safe Swift syntax.

## Overview
 
SwiftQL expressions look like Swift code:

<!-- test: XLDocumentationTests.testDocumentationREADME -->
```swift
import SwiftQL

@SQLTable
struct Person {
    var id: String
    var occupationId: String?
    var name: String
    var age: Int
}

let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == "Fred")
}
```

SwiftQL type-checks the APIs, table fields, and expression types used to
construct a statement. SQLite remains the authority for dialect-specific syntax
and runtime constraints.

SwiftQL lets you use your IDE's code completion and refactoring tools to assist
you in writing error-free SQL.

SwiftQL uses SQLite's dialect of SQL. If you have written SQL for SQLite, the
corresponding SwiftQL statements should feel familiar.

See the [documentation](https://lukevanin.github.io/swiftql/documentation/swiftql/)
for more.

See the [roadmap](ROADMAP.md) for planned reliability, SQLite conformance,
query-declaration, Swift 6, and multi-database work.

See [compiler compatibility](COMPATIBILITY.md) for the supported Swift
toolchains and reproducible CI matrix.

See [performance benchmarks](BENCHMARKS.md) for the reproducible query
construction, preparation, cache, binding, execution, and decoding baselines.

## Installation

### Swift Package Manager

Add the following line to the `dependencies` section in your `Package.swift`
file:

```text
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.0.0")
```

### Xcode

Refer to Apple's documentation [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#Add-a-package-dependency),
and specify the package URL `https://github.com/lukevanin/swiftql.git`. 

## License

MIT license. See [LICENSE.md](LICENSE.md).
