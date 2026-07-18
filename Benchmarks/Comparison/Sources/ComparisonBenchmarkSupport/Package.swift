// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ComparisonBenchmarkSupport",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "ComparisonBenchmarkSupport",
            targets: ["ComparisonBenchmarkSupport"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            "6.29.3"..<"8.0.0"
        ),
        .package(
            url: "https://github.com/stephencelis/SQLite.swift.git",
            exact: "0.16.0"
        ),
    ],
    targets: [
        .target(
            name: "ComparisonBenchmarkSupport",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
