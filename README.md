<p align="center">
  <img src=".github/assets/swiftql-logo.png" alt="SwiftQL logo" width="420">
</p>

<h1 align="center">SwiftQL</h1>

<p align="center">
  Write SQL queries using familiar, type-safe Swift syntax.
</p>

<p align="center">
  <a href="https://github.com/lukevanin/swiftql/actions/workflows/swift.yml?query=branch%3Amain"><img alt="Build and CI status" src="https://img.shields.io/github/actions/workflow/status/lukevanin/swiftql/swift.yml?branch=main&amp;label=build%20%26%20CI"></a>
  <a href="https://github.com/lukevanin/swiftql/actions/workflows/documentation.yml?query=branch%3Amain"><img alt="Documentation status" src="https://img.shields.io/github/actions/workflow/status/lukevanin/swiftql/documentation.yml?branch=main&amp;label=documentation"></a>
  <a href="COMPATIBILITY.md"><img alt="Supported Swift versions: 5.9 and 6.0" src="https://img.shields.io/badge/Swift-5.9%20%7C%206.0-F05138?logo=swift&amp;logoColor=white"></a>
  <a href="Package.swift"><img alt="Supported platforms: iOS 16 or later and macOS 13 or later" src="https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey"></a>
  <a href="https://swiftpackageindex.com/lukevanin/swiftql"><img alt="Swift Package Index" src="https://img.shields.io/badge/Swift%20Package%20Index-SwiftQL-5A2D81?logo=swift&amp;logoColor=white"></a>
  <a href="https://github.com/lukevanin/swiftql/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/lukevanin/swiftql?sort=semver"></a>
  <a href="LICENSE.md"><img alt="MIT license" src="https://img.shields.io/github/license/lukevanin/swiftql"></a>
</p>

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

Documentation pull requests build an isolated Pages artifact without deploying
it. Commits on `main` publish that exact artifact and include a
[deployment provenance record](https://lukevanin.github.io/swiftql/swiftql-pages-provenance.json).
For a failed build or upload, choose **Re-run all jobs** on that current
`main` run. If only deployment or site verification failed, choose
**Re-run failed jobs** to redeploy the same artifact. Do not rerun a superseded
`main` run; manually dispatch the Documentation workflow on current `main`
instead.

See the [roadmap](ROADMAP.md) for planned reliability, SQLite conformance,
query-declaration, Swift 6, and multi-database work.

See [compiler compatibility](COMPATIBILITY.md) for the supported Swift
toolchains and reproducible CI matrix.

See [performance benchmarks](BENCHMARKS.md) for the reproducible query
construction, preparation, cache, binding, execution, and decoding baselines.

See [first-party source coverage](Coverage/README.md) for the pinned Swift 6
capture, filtering contract, retained raw evidence, and checked-in baseline.

See [releasing SwiftQL](RELEASING.md) for the exact-tag validation, safe dry-run,
artifact provenance, publication, verification, and recovery procedure.

## Installation

### Swift Package Manager

Add the following line to the `dependencies` section in your `Package.swift`
file:

```text
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.1.0")
```

### Xcode

Refer to Apple's documentation [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#Add-a-package-dependency),
and specify the package URL `https://github.com/lukevanin/swiftql.git`. 

## License

MIT license. See [LICENSE.md](LICENSE.md).
