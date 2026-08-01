// swift-tools-version: 6.1

import PackageDescription

// Dependency-free control consumer. It measures what N hand-written Swift
// declarations and hand-written SQLite C calls cost on their own, so the
// other consumers' costs can be read as a delta rather than an absolute.
let package = Package(
    name: "ControlRawSQLiteConsumer",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "ConsumerLibrary",
            type: .static,
            targets: ["Consumer"]
        ),
    ],
    targets: [
        .target(
            name: "Consumer",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
