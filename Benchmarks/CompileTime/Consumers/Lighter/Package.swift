// swift-tools-version: 6.1

import PackageDescription

// Lighter consumer. Lighter has no user-written table or query declarations:
// its Enlighter build-tool plugin reads a schema file and emits the record
// types. The table axis therefore scales `schema.sql`, and the query axis is
// not applicable. See README.md's applicability matrix.
let package = Package(
    name: "LighterConsumer",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "ConsumerLibrary",
            type: .static,
            targets: ["Consumer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Lighter-swift/Lighter.git",
            exact: "1.4.12"
        ),
    ],
    targets: [
        .target(
            name: "Consumer",
            dependencies: [
                .product(name: "Lighter", package: "Lighter"),
            ],
            plugins: [
                .plugin(name: "Enlighter", package: "Lighter"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
