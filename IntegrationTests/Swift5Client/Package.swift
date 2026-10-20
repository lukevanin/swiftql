// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftQLSwift5Client",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "SwiftQL", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "SwiftQLSwift5Client",
            dependencies: [
                .product(name: "SwiftQLCore", package: "SwiftQL"),
                .product(name: "SwiftQL", package: "SwiftQL"),
                .product(name: "SwiftQLSQLiteBuildValidationManifest", package: "SwiftQL"),
                .product(name: "SwiftQLSQLiteBuildValidationValidator", package: "SwiftQL"),
            ]
        ),
        // Issue #790: a client of the SQLite product alone, with no GRDB.
        // Its models expand the dialect-less model macros, so it proves the
        // macros' expansions resolve in a file that imports only
        // SwiftQLSQLite.
        .executableTarget(
            name: "SwiftQLSwift5SQLiteClient",
            dependencies: [
                .product(name: "SwiftQLSQLite", package: "SwiftQL"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
