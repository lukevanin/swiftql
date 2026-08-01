// swift-tools-version: 6.1

import PackageDescription

// SQLite.swift consumer, pinned to the same revision the cross-library
// full-fetch comparison in Benchmarks/Comparison uses.
let package = Package(
    name: "SQLiteSwiftConsumer",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "ConsumerLibrary",
            type: .static,
            targets: ["Consumer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/stephencelis/SQLite.swift.git",
            exact: "0.16.0"
        ),
    ],
    targets: [
        .target(
            name: "Consumer",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
