// swift-tools-version: 6.1

import PackageDescription

// GRDB consumer, pinned to the same GRDB major SwiftQL itself resolves so the
// two consumers compile against the same record and query-interface surface.
let package = Package(
    name: "GRDBConsumer",
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
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "6.29.3"
        ),
    ],
    targets: [
        .target(
            name: "Consumer",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
