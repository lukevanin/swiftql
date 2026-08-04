// swift-tools-version: 6.1

import PackageDescription

// SwiftQL consumer. run.py replaces the checkout placeholder below with the
// absolute path of the measured SwiftQL checkout, so the recorded numbers
// always belong to a known SwiftQL revision.
let package = Package(
    name: "SwiftQLConsumer",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "ConsumerLibrary",
            type: .static,
            targets: ["Consumer"]
        ),
    ],
    dependencies: [
        .package(name: "SwiftQL", path: __SWIFTQL_CHECKOUT__),
    ],
    targets: [
        .target(
            name: "Consumer",
            dependencies: [
                .product(name: "SwiftQL", package: "SwiftQL"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
