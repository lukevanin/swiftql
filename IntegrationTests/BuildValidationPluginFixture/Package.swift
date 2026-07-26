// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftQLBuildValidationPluginFixture",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "SwiftQL", path: "../.."),
    ],
    targets: [
        .target(
            name: "ValidatedLibrary",
            plugins: [
                .plugin(name: "SwiftQLSQLiteBuildValidationPlugin", package: "SwiftQL"),
            ]
        ),
        // A second target adopting the plugin, proving report paths are
        // namespaced per target rather than colliding on one shared path.
        .target(
            name: "SecondValidatedLibrary",
            plugins: [
                .plugin(name: "SwiftQLSQLiteBuildValidationPlugin", package: "SwiftQL"),
            ]
        ),
    ]
)
