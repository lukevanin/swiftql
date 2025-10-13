# SwiftQL

SwiftQL lets you you write SQL queries using familiar Swift type-safe syntax.

## Overview
 
Using SwiftQL SQL expressions look like Swift code:

```swift
let query = sql { schema in
    let person = schema.table(Person.self)
    Select(person)
    From(person)
    Where(person.name == 'Fred')
}
```

SQL written with SwiftQL is type checked at compile time, highlghting any syntax
errors, typos, or missing fields.

SwiftQL lets you use your IDE's code completion and refactoring tools to assist 
you in writing error free SQL.

Currently SwiftQL supports SQLite's dialect of SQL.

See the [Getting Started Guide](Documentation.docc/GettingStarted.md) for more.

## Installation

### Swift Package Manager

Add the following line to the `dependencies` section in your `Package.swift`
file:

```swift
.package(url: "https://github.com/lukevanin/swiftql.git", from: "1.0.0")
```

### Xcode

Refer to Apple's documentation [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#Add-a-package-dependency),
and specify the package URL `https://github.com/lukevanin/swiftql.git`. 

## License

MIT license. See the [license](license.md). 
