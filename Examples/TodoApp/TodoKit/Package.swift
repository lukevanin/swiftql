// swift-tools-version: 5.9

import PackageDescription

// TodoKit holds every line of the demo that touches SwiftQL: the schema, the
// query layer, and the database lifecycle. The Xcode app target in
// ../TodoApp.xcodeproj is a thin SwiftUI shell that links this library.
//
// The split is not decoration. SwiftQL's build-time validation plugin is a
// SwiftPM `BuildToolPlugin`, so it can only be attached to a SwiftPM target;
// keeping the SwiftQL-facing code here is what lets the demo run the
// validator on every build. It also means the demo's tests run under plain
// `swift test`.
let package = Package(
    name: "TodoKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "TodoKit",
            targets: ["TodoKit"]
        ),
    ],
    dependencies: [
        // A path dependency on the repository root, so the demo always builds
        // the working tree rather than a published tag. A library change that
        // breaks the demo breaks it here, immediately.
        .package(name: "SwiftQL", path: "../../.."),
        // Used by the manifest generator below, to write the checked-in schema
        // snapshot in rollback-journal mode, and by TodoIndices.swift, which
        // runs the index statements the v1.8 advisor verified. SwiftQL is the
        // demo's database API everywhere else; index DDL is the one thing it
        // does not yet express (#139).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TodoKit",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
                // Used by exactly one file, TodoIndices.swift, and only
                // because SwiftQL has no index DDL yet (#139). The v1.8 index
                // advisor tells the demo which indices to add and proves each
                // one changes the plan; running the statements it produces
                // needs GRDB until typed DDL lands.
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            // Generates TodoKitDeclaredQueries from the @SQLQueries and
            // @SQLQuery declarations in this target, so the manifest
            // generator below lists no queries of its own.
            plugins: [
                .plugin(
                    name: "SwiftQLDeclaredQueryRegistryPlugin",
                    package: "SwiftQL"
                ),
            ]
        ),

        // Runs SwiftQL's build-time query validation over the demo's declared
        // queries. It carries no code — see BuildValidation.swift for why the
        // plugin lives on a target of its own rather than on TodoKit.
        .target(
            name: "TodoKitBuildValidation",
            plugins: [
                .plugin(
                    name: "SwiftQLSQLiteBuildValidationPlugin",
                    package: "SwiftQL"
                ),
            ]
        ),

        // Regenerates the two files the validation plugin consumes:
        // the checked-in schema snapshot and the query manifest describing
        // it. The manifest is projected from the queries TodoKit declares, so
        // it holds no query list of its own. Run
        // ../Tools/regenerate-validation-manifest.sh after changing the
        // schema or any declared query.
        .executableTarget(
            name: "todo-validation-manifest",
            dependencies: [
                "TodoKit",
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(
                    name: "SwiftQLSQLiteBuildValidationDeclaredQueries",
                    package: "SwiftQL"
                ),
                .product(
                    name: "SwiftQLSQLiteBuildValidationManifest",
                    package: "SwiftQL"
                ),
                .product(
                    name: "SwiftQLSQLiteBuildValidationValidator",
                    package: "SwiftQL"
                ),
            ]
        ),

        // The awaitable Observation helper the live-query tests use lives in
        // this test target (ObservedStateWaiting.swift), not in a regular
        // target: a regular target gets no XCTest search paths, so importing
        // XCTest there breaks a plain `swift build`, and a test target is
        // never part of anything that ships.
        .testTarget(
            name: "TodoKitTests",
            dependencies: [
                "TodoKit",
                // Used by TodoValidationManifestTests.swift, which compares
                // the generated manifest entries with the hand-written list
                // the generator carried before issue #659.
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(
                    name: "SwiftQLSQLiteBuildValidationDeclaredQueries",
                    package: "SwiftQL"
                ),
                .product(
                    name: "SwiftQLSQLiteBuildValidationManifest",
                    package: "SwiftQL"
                ),
            ]
        ),
    ]
)
