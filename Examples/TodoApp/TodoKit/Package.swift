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
        // Used only by the manifest generator below, to write the checked-in
        // schema snapshot in rollback-journal mode. TodoKit itself never
        // imports GRDB — SwiftQL is the demo's only database API.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
    ],
    targets: [
        .target(
            name: "TodoKit",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
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
        // it. Run ../Tools/regenerate-validation-manifest.sh after changing
        // the schema or any declared query.
        .executableTarget(
            name: "todo-validation-manifest",
            dependencies: [
                "TodoKit",
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(name: "GRDB", package: "GRDB.swift"),
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

        .testTarget(
            name: "TodoKitTests",
            dependencies: ["TodoKit"]
        ),
    ]
)
