// swift-tools-version: 5.9

import Foundation
import PackageDescription

// The end-to-end check of declared-query discovery (#659). verify.sh copies
// this package to a scratch directory, so it adds and removes source files
// without touching the checkout. The copy cannot reach SwiftQL through a
// relative path, so verify.sh passes the checkout's path in
// SWIFTQL_SOURCE_ROOT.
let swiftQLPath = ProcessInfo.processInfo.environment["SWIFTQL_SOURCE_ROOT"] ?? "../.."

let package = Package(
    name: "SwiftQLDeclaredQueryRegistryFixture",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "SwiftQL", path: swiftQLPath),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
    ],
    targets: [
        // The declarations. The plugin generates FixtureQueriesDeclaredQueries
        // from them on every build.
        .target(
            name: "FixtureQueries",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
            ],
            plugins: [
                .plugin(name: "SwiftQLDeclaredQueryRegistryPlugin", package: "SwiftQL"),
            ]
        ),
        // The generator. It names no query.
        .executableTarget(
            name: "fixture-manifest",
            dependencies: [
                "FixtureQueries",
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(name: "SwiftQLSQLiteBuildValidationDeclaredQueries", package: "SwiftQL"),
                .product(name: "SwiftQLSQLiteBuildValidationManifest", package: "SwiftQL"),
                .product(name: "SwiftQLSQLiteBuildValidationValidator", package: "SwiftQL"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
