// swift-tools-version: 6.1
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
        // The dialect-neutral query surface, for a dialect author (issue
        // #790). Most apps import SwiftQLSQLite or SwiftQL instead.
        .library(
            name: "SwiftQLQuery",
            targets: ["SwiftQLQuery"]
        ),
        // The driver-neutral runtime contracts and their Combine, async, and
        // SwiftUI bridges, for a driver author (issue #790).
        .library(
            name: "SwiftQLRuntime",
            targets: ["SwiftQLRuntime"]
        ),
        // SQLite's surface, the macros, and the request runtime for any
        // SQLite driver, with no GRDB: models and queries import this
        // (issue #790).
        .library(
            name: "SwiftQLSQLite",
            targets: ["SwiftQLSQLite"]
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
        .library(
            name: "SwiftQLSQLiteBuildValidationDeclaredQueries",
            targets: ["SwiftQLSQLiteBuildValidationDeclaredQueries"]
        ),
        .executable(
            name: "swiftql-declared-query-registry",
            targets: ["swiftql-declared-query-registry"]
        ),
        .plugin(
            name: "SwiftQLDeclaredQueryRegistryPlugin",
            targets: ["SwiftQLDeclaredQueryRegistryPlugin"]
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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // `make-docs.sh` builds combined documentation, whose flag the plugin
        // has from 1.4.0 (issue #790).
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.4.0"),
        // OpenCombine is linked on Linux only (see the `condition:` on each
        // product below). Apple platforms use Combine. `Package.resolved` keeps
        // the tested 0.14.0 pin; the range lets consumers resolve a compatible
        // release when another package in their graph needs one.
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
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
        // databases, numeric SQLite version comparison, repository-root
        // lookup, and the driver-scope contract suite (issue #676).
        // Deliberately free of XCTest so it can be a regular target --
        // a library target has no XCTest search paths, and importing it here
        // would break `swift build` (issue #557).
        .target(
            name: "SwiftQLTestSupport",
            dependencies: [
                "SwiftQLCore",
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

        // Compile-only fixture (issue #684): `XLRequest` conformers that
        // implement only the live-query stream members and never import
        // Combine or OpenCombine. Building it proves a request adapter needs
        // neither; SwiftQL supplies the publish members. SQLTests drives the
        // conformers through those members and checks the import rule.
        .target(
            name: "SwiftQLStreamOnlyRequestFixture",
            dependencies: ["SwiftQL"],
            path: "Tests/SwiftQLStreamOnlyRequestFixture"
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

        // The dialect-neutral query surface: expressions, columns, schemas,
        // statements and clause builders, the renderer, static row layouts,
        // and the macro contracts (issue #790). No dialect's operations, and
        // no runtime: a target that imports only this module cannot reach a
        // SQLite-only operation, and the core boundary check keeps GRDB and
        // Combine out of it.
        .target(
            name: "SwiftQLQuery",
            dependencies: [
                "SwiftQLCore",
                "SQLMacros",
            ]
        ),

        // The driver-neutral runtime contracts -- `XLDatabase`, requests,
        // result sets, transactions, the render-once cache -- and the
        // Combine/OpenCombine, async, and SwiftUI bridges over them (issue
        // #790, decision D8). The only one of the query modules that imports
        // Combine.
        .target(
            name: "SwiftQLRuntime",
            dependencies: [
                "SwiftQLQuery",
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineDispatch", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineFoundation", package: "OpenCombine", condition: .when(platforms: [.linux])),
            ]
        ),

        // SQLite's surface (generated and hand-written), its codecs, the
        // macros, and the request runtime for any SQLite driver (issue #790).
        // It depends on no GRDB, so a model or query file that imports it
        // alone does not see the database driver.
        .target(
            name: "SwiftQLSQLite",
            dependencies: [
                "SwiftQLQuery",
                "SwiftQLRuntime",
                "SQLMacros",
            ]
        ),

        // The GRDB driver, and the umbrella that re-exports SwiftQLSQLite, so
        // `import SwiftQL` keeps working (issue #790, decision D13). It
        // depends on every module it re-exports directly, so its DocC catalog
        // can link them.
        .target(
            name: "SwiftQL",
            dependencies: [
                "SwiftQLSQLite",
                "SwiftQLRuntime",
                "SwiftQLQuery",
                "SwiftQLCore",
                "SQLMacros",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineDispatch", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineFoundation", package: "OpenCombine", condition: .when(platforms: [.linux])),
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
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
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

        // Projects the declared queries of a target into a format version 2
        // build-validation manifest (#659). `@SQLQueries` lists its
        // specifications in a generated `declaredQueries` member, and this
        // target turns that list into manifest entries pinned to a snapshot.
        // Generation only: validation stays in the validator above.
        .target(
            name: "SwiftQLSQLiteBuildValidationDeclaredQueries",
            dependencies: [
                "SwiftQL",
                "SwiftQLSQLiteBuildValidationManifest",
                "SwiftQLSQLiteBuildValidationValidator",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // Applies the registry plugin to itself, so the declarations in the
        // test sources are discovered exactly as an application's are.
        .testTarget(
            name: "SwiftQLSQLiteBuildValidationDeclaredQueriesTests",
            dependencies: [
                "SwiftQL",
                "SwiftQLCore",
                "SwiftQLSQLiteBuildValidationDeclaredQueries",
                "SwiftQLSQLiteBuildValidationManifest",
                "SwiftQLSQLiteBuildValidationValidator",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            plugins: ["SwiftQLDeclaredQueryRegistryPlugin"]
        ),

        // Finds every @SQLQuery and @SQLQueries declaration in Swift source
        // with SwiftSyntax and renders a target's declared-query registry
        // (#659). A regular target so the scan is unit-testable.
        .target(
            name: "SwiftQLDeclaredQueryDiscovery",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),

        // The registry generator the plugin below runs. Target and product
        // share a name for the same reason `swiftql-build-validate` does
        // (#492).
        .executableTarget(
            name: "swiftql-declared-query-registry",
            dependencies: ["SwiftQLDeclaredQueryDiscovery"],
            path: "Sources/SwiftQLDeclaredQueryRegistryCLI"
        ),

        // Generates `<Target>DeclaredQueries` into the target it is applied
        // to, from that target's own sources, so a manifest generator needs
        // no hand-written list of declared queries (#659).
        .plugin(
            name: "SwiftQLDeclaredQueryRegistryPlugin",
            capability: .buildTool(),
            dependencies: ["swiftql-declared-query-registry"]
        ),

        .testTarget(
            name: "SwiftQLDeclaredQueryDiscoveryTests",
            dependencies: ["SwiftQLDeclaredQueryDiscovery"]
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

        // Issue #682: a driver double with no GRDB import backs requests,
        // writes, result sets, and static queries through `XLDriverDatabase`.
        // It depends on SwiftQLSQLite alone, the syntax and runtime with no
        // GRDB driver (issue #790), and the core boundary check rejects a
        // GRDB, CSQLite, or Combine import in it.
        .testTarget(
            name: "SwiftQLDriverDatabaseTests",
            dependencies: ["SwiftQLSQLite"]
        ),

        // Issue #702: a client opens a GRDB-backed database, registers a
        // function and a collation, and runs queries without importing GRDB.
        // It depends on SwiftQL alone, and the core boundary check rejects a
        // GRDB, CSQLite, or Combine import in it, the GRDB SPI, and
        // `@testable import SwiftQL`. Member import visibility keeps GRDB's
        // extension members, which SwiftQL's module loads, out of reach too.
        .testTarget(
            name: "SwiftQLGRDBFreeClientTests",
            dependencies: ["SwiftQL"],
            // Issue #113: the GRDB driver's types are `package`. Without
            // package access, the compiler hides every `package` symbol from
            // this target, so it still sees only SwiftQL's public API.
            packageAccess: false,
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Issue #702: the proposed v2 spelling of every public `XL` name, as
        // typealiases in a module of their own, so a client that imports it
        // beside GRDB, Foundation, SwiftUI, and the other Apple frameworks an
        // app commonly imports sees the same cross-module ambiguities the
        // renamed types will (#33).
        .target(
            name: "SwiftQLV2Names",
            dependencies: ["SwiftQL"],
            path: "Tests/SwiftQLV2Names"
        ),

        // Compile-only collision fixture (issue #702). It imports SwiftQL,
        // GRDB, Foundation, and, where they exist, SwiftUI, Combine,
        // Observation, os, and SwiftData, together with the proposed v2 names,
        // and names each one unqualified. A proposed name another of those
        // modules also declares is ambiguous there, so the tests stop
        // building. It is a test target with no tests, so a collision a new
        // SDK introduces fails the test build, not `swift build`.
        .testTarget(
            name: "SwiftQLV2NameCollisionFixture",
            dependencies: [
                "SwiftQL",
                "SwiftQLV2Names",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/SwiftQLV2NameCollisionFixture"
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
                // `@testable` reaches the internals of the modules SwiftQL
                // re-exports only through a direct dependency (issue #790).
                "SwiftQLQuery",
                "SwiftQLRuntime",
                "SwiftQLSQLite",
                "SwiftQLStreamOnlyRequestFixture",
                "SwiftQLNorthwindFixtures",
                "SwiftQLSQLiteConformanceFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineDispatch", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineFoundation", package: "OpenCombine", condition: .when(platforms: [.linux])),
            ]
        ),

        // Isolated from SQLTests so contextual Foundation codecs do not inherit
        // the legacy test suite's retroactive literal conformances.
        .testTarget(
            name: "SwiftQLCodecIntegrationTests",
            dependencies: [
                "SwiftQLTestSupport",
                "SwiftQL",
                "SwiftQLSQLite",
                "SwiftQLSQLiteConformanceFixtures",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
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
                // `SQLitePrepareV3ProbeTests` imports `GRDBSQLite`. The
                // product is declared here rather than reached through the
                // validator target's own dependency.
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
            ]
        ),
    ]
)
