// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SQLiteDataGRDB7Comparison",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "ComparisonBenchmark",
            targets: ["ComparisonBenchmark"]
        ),
    ],
    dependencies: [
        .package(path: __SUPPORT_PACKAGE__),
        .package(
            url: "https://github.com/pointfreeco/sqlite-data.git",
            exact: "1.7.0"
        ),
        .package(
            url: "https://github.com/Lighter-swift/Lighter.git",
            exact: "1.4.12"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.11.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ComparisonBenchmark",
            dependencies: [
                "ComparisonBenchmarkSupport",
                .product(name: "SQLiteData", package: "sqlite-data"),
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
