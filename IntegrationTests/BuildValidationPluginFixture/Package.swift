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
    ]
)
