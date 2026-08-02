// swift-tools-version: 6.1

import PackageDescription

// Issue #259 workload prototype. This graph is separate from the #250
// full-fetch graphs and does not change them. run.py replaces the checkout
// placeholder below with the absolute path of the measured SwiftQL checkout.
let package = Package(
    name: "WorkloadPrototype",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "WorkloadPrototype",
            targets: ["WorkloadPrototype"]
        ),
    ],
    dependencies: [
        .package(name: "SwiftQL", path: __SWIFTQL_CHECKOUT__),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "6.29.3"
        ),
        .package(
            url: "https://github.com/stephencelis/SQLite.swift.git",
            exact: "0.16.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "WorkloadPrototype",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
