// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftQLGRDB6Comparison",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "ComparisonBenchmark",
            targets: ["ComparisonBenchmark"]
        ),
    ],
    dependencies: [
        .package(name: "SwiftQL", path: __SWIFTQL_CHECKOUT__),
        .package(path: __SUPPORT_PACKAGE__),
        .package(
            url: "https://github.com/Lighter-swift/Lighter.git",
            exact: "1.4.12"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "6.29.3"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ComparisonBenchmark",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
                "ComparisonBenchmarkSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Lighter", package: "Lighter"),
            ],
            resources: [.copy("northwind-performance.sqlite")],
            plugins: [
                .plugin(name: "Enlighter", package: "Lighter"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
