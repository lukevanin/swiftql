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
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
