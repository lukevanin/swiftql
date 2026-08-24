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
        //
        // Its manifest and snapshot are byte-identical copies of
        // ValidatedLibrary's, and have to be: the plugin resolves both inputs
        // as `sourceTarget.directory.appending(...)` and fails the build when
        // either is absent from the target's own directory, so an opted-in
        // target cannot borrow another's files. Two copies of the 588K snapshot
        // is the cost of covering the multi-target case at all.
        .target(
            name: "SecondValidatedLibrary",
            plugins: [
                .plugin(name: "SwiftQLSQLiteBuildValidationPlugin", package: "SwiftQL"),
            ]
        ),
    ]
)
