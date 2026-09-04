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
        // Pre-expanded example schema and queries for the Getting Started
        // playground. A classic Xcode playground cannot expand SwiftQL's
        // macros itself, so it imports this compiled module instead.
        .library(
            name: "SwiftQLExamples",
            targets: ["SwiftQLExamples"]
        ),
        .library(
            name: "SwiftQLSQLiteBuildValidationManifest",
            targets: ["SwiftQLSQLiteBuildValidationManifest"]
        ),
        .library(
            name: "SwiftQLSQLiteBuildValidationValidator",
            targets: ["SwiftQLSQLiteBuildValidationValidator"]
        ),
        .executable(
            name: "swiftql-benchmark",
            targets: ["SwiftQLBenchmarkCLI"]
        ),
        .executable(
            name: "swiftql-construction-profile",
            targets: ["SwiftQLConstructionProfile"]
        ),
        .executable(
            name: "swiftql-build-validate",
            targets: ["swiftql-build-validate"]
        ),
        .library(
            name: "SwiftQLSQLiteIndexAdvisor",
            targets: ["SwiftQLSQLiteIndexAdvisor"]
        ),
        .executable(
            name: "swiftql-index-advisor",
            targets: ["swiftql-index-advisor"]
        ),
        .plugin(
            name: "SwiftQLSQLiteBuildValidationPlugin",
            targets: ["SwiftQLSQLiteBuildValidationPlugin"]
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

        // Test-only scaffolding shared across test targets: scoped temporary
        // databases, numeric SQLite version comparison, and repository-root
        // lookup. Deliberately free of XCTest so it can be a regular target --
        // a library target has no XCTest search paths, and importing it here
        // would break `swift build` (issue #557).
        .target(
            name: "SwiftQLTestSupport",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/SwiftQLTestSupport"
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
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                // `StringLiteralExprSyntax.representedLiteralValue`, which
                // `MacroNameArgument` reads a `name:` argument through, lives
                // in SwiftParser rather than SwiftSyntax.
                .product(name: "SwiftParser", package: "swift-syntax"),
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

        // Example schema and declared queries for the Getting Started
        // playground (#480). SwiftQL's macros are expanded here, during the
        // ordinary package build, because a classic Xcode playground has no
        // Package.swift of its own and cannot reliably load a Swift macro
        // compiler plugin. The playground imports this module and calls
        // already-expanded API.
        .target(
            name: "SwiftQLExamples",
            dependencies: ["SwiftQL"],
            path: "Examples/Sources/SwiftQLExamples"
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

        // Versioned, deterministic sidecar manifest for static SwiftQL query
        // descriptors (#292). No SQLite I/O, no macro/plugin logic. #190/#191/
        // #254 reference resolution is injected via
        // SQLiteBuildValidationReferenceRegistry rather than depending on
        // their test-only targets.
        .target(
            name: "SwiftQLSQLiteBuildValidationManifest",
            dependencies: ["SwiftQLCore"]
        ),

        // Standalone SQLite static-query build validator (#293). Consumes
        // the #292 manifest and an explicit checked-in SQLite snapshot, owns
        // one dedicated read-only/query-only connection per run, and
        // prepares each manifest entry with sqlite3_prepare_v3. No prepared
        // statement escapes this target: SQLitePrepareV3Probe returns copied
        // Swift values only.
        .target(
            name: "SwiftQLSQLiteBuildValidationValidator",
            dependencies: [
                "SwiftQLCore",
                "SwiftQLSQLiteBuildValidationManifest",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CSQLite", package: "GRDB.swift"),
            ]
        ),

        // The target name has to match the `swiftql-build-validate` product
        // name above, because this executable is a build-tool plugin's tool
        // (#492). `context.tool(named:)` resolves to
        // `$BUILD_DIR/$CONFIGURATION/<target name>`, while Xcode's build
        // system names a package executable after its *product*. When the two
        // names differ, Xcode drops the executable from the plugin-adopting
        // target's dependency graph entirely and the build fails with "Build
        // input file cannot be found" before validation ever runs. `swift
        // build` tolerates the mismatch; Xcode does not. The source directory
        // keeps its descriptive name via `path:`.
        .executableTarget(
            name: "swiftql-build-validate",
            dependencies: ["SwiftQLSQLiteBuildValidationValidator"],
            path: "Sources/SwiftQLSQLiteBuildValidationValidatorCLI"
        ),

        // The swiftql-index-advisor codemod (#399). Reads the verified
        // recommendations the validator wrote and either reports them or
        // renders them as a generated, checked-in SQL artifact. Consumes the
        // artifact only: no plan analysis, candidate generation, or
        // verification logic lives here.
        .target(
            name: "SwiftQLSQLiteIndexAdvisor",
            dependencies: ["SwiftQLSQLiteBuildValidationValidator"]
        ),

        // Target and product share a name for the same reason
        // `swiftql-build-validate` does (#492), so a build-tool plugin could
        // resolve this executable through `context.tool(named:)` under both
        // build systems if one ever needed to. This command is deliberately
        // not wired into any plugin: a build never rewrites source.
        .executableTarget(
            name: "swiftql-index-advisor",
            dependencies: ["SwiftQLSQLiteIndexAdvisor"],
            path: "Sources/SwiftQLSQLiteIndexAdvisorCLI"
        ),

        // Thin SwiftPM build-tool plugin wrapper around the standalone
        // validator (#294). Declares the manifest/snapshot as explicit
        // command inputs and the report as an explicit output; owns no
        // validation logic, schema inference, or second report format.
        .plugin(
            name: "SwiftQLSQLiteBuildValidationPlugin",
            capability: .buildTool(),
            dependencies: ["swiftql-build-validate"]
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "SwiftQLCoreTests",
            dependencies: [
                "SwiftQLTestSupport",
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
            ],
            resources: [.process("MacroRegressionCorpus.json")]
        ),
        
        //
        .testTarget(
            name: "SQLTests",
            dependencies: [
                "SwiftQLTestSupport",
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
                "SwiftQLTestSupport",
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
                "SwiftQLTestSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .testTarget(
            name: "SwiftQLBenchmarkTests",
            dependencies: ["SwiftQLBenchmarks"],
            path: "Benchmarks/Tests/SwiftQLBenchmarkTests"
        ),

        .testTarget(
            name: "SwiftQLSQLiteBuildValidationManifestTests",
            dependencies: [
                "SwiftQLCore",
                "SwiftQL",
                "SwiftQLSQLiteBuildValidationManifest",
                "SwiftQLSQLiteConformanceFixtures",
                "SwiftQLSQLiteCombinatorialSupport",
                "SwiftQLNorthwindFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .testTarget(
            name: "SwiftQLSQLiteIndexAdvisorTests",
            dependencies: [
                "SwiftQLSQLiteBuildValidationManifest",
                "SwiftQLSQLiteBuildValidationValidator",
                "SwiftQLSQLiteIndexAdvisor",
                "SwiftQLCore",
                "SwiftQLNorthwindFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .testTarget(
            name: "SwiftQLSQLiteBuildValidationValidatorTests",
            dependencies: [
                "SwiftQLCore",
                "SwiftQL",
                "SwiftQLSQLiteBuildValidationManifest",
                "SwiftQLSQLiteBuildValidationValidator",
                "SwiftQLNorthwindFixtures",
                "SwiftQLSQLiteConformanceFixtures",
                "SwiftQLSQLiteCombinatorialSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
