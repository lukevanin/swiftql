// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftQL",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftQLCore",
            targets: ["SwiftQLCore"]
        ),
        .library(
            name: "SwiftQL",
            targets: ["SwiftQL"]
        ),
        .executable(
            name: "swiftql-benchmark",
            targets: ["SwiftQLBenchmarkCLI"]
        ),
        .executable(
            name: "swiftql-construction-profile",
            targets: ["SwiftQLConstructionProfile"]
        ),
    ],
    dependencies: [
        // Depend on the latest Swift 5.9 prerelease of SwiftSyntax
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.0.0"),
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", exact: "0.14.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // GRDB-free contracts shared by dialect renderers and database drivers.
        .target(
            name: "SwiftQLCore"
        ),

        // Test-only, adapter-neutral SQLite value cases shared by core contract
        // tests and concrete database-adapter integration tests.
        .target(
            name: "SwiftQLSQLiteConformanceFixtures",
            dependencies: ["SwiftQLCore"],
            path: "Tests/SwiftQLSQLiteConformanceFixtures",
            resources: [.process("SQLiteConformanceInventory.json")]
        ),

        // Test-only, immutable Northwind correctness fixture shared by the
        // semantic corpus and its fixture contract tests.
        .target(
            name: "SwiftQLNorthwindFixtures",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/SwiftQLNorthwindFixtures",
            resources: [.copy("Resources/Northwind")]
        ),

        // Test-only, constraint-aware syntax generator and real-SQLite replay
        // support. The target consumes the canonical inventory and Northwind
        // fixture without taking ownership of either artifact.
        .target(
            name: "SwiftQLSQLiteCombinatorialSupport",
            dependencies: [
                "SwiftQL",
                "SwiftQLNorthwindFixtures",
                "SwiftQLSQLiteConformanceFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/SwiftQLSQLiteCombinatorialSupport"
        ),

        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "SQLMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(
            name: "SwiftQL",
            dependencies: [
                "SwiftQLCore",
                "SQLMacros",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OpenCombine", package: "OpenCombine"),
                .product(name: "OpenCombineDispatch", package: "OpenCombine"),
                .product(name: "OpenCombineFoundation", package: "OpenCombine"),
            ]
        ),

        // Reusable benchmark implementation. Keeping this separate from the executable makes
        // statistics, serialization, and smoke behavior directly testable.
        .target(
            name: "SwiftQLBenchmarks",
            dependencies: [
                "SwiftQL",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Benchmarks/Sources/SwiftQLBenchmarks"
        ),

        .executableTarget(
            name: "SwiftQLBenchmarkCLI",
            dependencies: ["SwiftQLBenchmarks"],
            path: "Benchmarks/Sources/SwiftQLBenchmarkCLI"
        ),

        // Deterministic allocation + sub-phase timing profiler for issue #166.
        // Diagnostic evidence, not part of the #128 benchmark report or any gate.
        .executableTarget(
            name: "SwiftQLConstructionProfile",
            dependencies: ["SwiftQL"],
            path: "Benchmarks/Sources/SwiftQLConstructionProfile"
        ),

        // Package-private research engine for issue #132. This deliberately
        // remains outside the package's public products while the descriptor
        // sidecar and build lifecycle are being evaluated.
        .target(
            name: "SwiftQLSQLiteBuildValidationPrototype",
            dependencies: [
                "SwiftQLCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CSQLite", package: "GRDB.swift"),
            ],
            path: "Research/SQLiteBuildValidation/Sources/SwiftQLSQLiteBuildValidationPrototype"
        ),

        .executableTarget(
            name: "SwiftQLSQLiteBuildValidationPrototypeCLI",
            dependencies: ["SwiftQLSQLiteBuildValidationPrototype"],
            path: "Research/SQLiteBuildValidation/Sources/SwiftQLSQLiteBuildValidationPrototypeCLI"
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "SwiftQLCoreTests",
            dependencies: [
                "SwiftQLCore",
                "SwiftQLSQLiteConformanceFixtures",
            ]
        ),

        .testTarget(
            name: "SQLMacrosTests",
            dependencies: [
                "SQLMacros",
                "SwiftQL",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        
        //
        .testTarget(
            name: "SQLTests",
            dependencies: [
                "SwiftQL",
                "SwiftQLNorthwindFixtures",
                "SwiftQLSQLiteConformanceFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OpenCombine", package: "OpenCombine"),
                .product(name: "OpenCombineDispatch", package: "OpenCombine"),
                .product(name: "OpenCombineFoundation", package: "OpenCombine"),
            ]
        ),

        // Isolated from SQLTests so contextual Foundation codecs do not inherit
        // the legacy test suite's retroactive literal conformances.
        .testTarget(
            name: "SwiftQLCodecIntegrationTests",
            dependencies: [
                "SwiftQL",
                "SwiftQLSQLiteConformanceFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OpenCombine", package: "OpenCombine"),
            ]
        ),

        .testTarget(
            name: "SwiftQLNorthwindFixturesTests",
            dependencies: [
                "SwiftQLNorthwindFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .testTarget(
            name: "SwiftQLSQLiteCombinatorialSupportTests",
            dependencies: [
                "SwiftQL",
                "SwiftQLSQLiteCombinatorialSupport",
                "SwiftQLNorthwindFixtures",
                "SwiftQLSQLiteConformanceFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .testTarget(
            name: "SwiftQLBenchmarkTests",
            dependencies: ["SwiftQLBenchmarks"],
            path: "Benchmarks/Tests/SwiftQLBenchmarkTests"
        ),

        .testTarget(
            name: "SwiftQLSQLiteBuildValidationPrototypeTests",
            dependencies: [
                "SwiftQLCore",
                "SwiftQL",
                "SwiftQLSQLiteBuildValidationPrototype",
                "SwiftQLNorthwindFixtures",
                "SwiftQLSQLiteConformanceFixtures",
                "SwiftQLSQLiteCombinatorialSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Research/SQLiteBuildValidation/Tests/SwiftQLSQLiteBuildValidationPrototypeTests"
        ),
    ]
)
