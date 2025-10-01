// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftQL",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftQL",
            targets: ["SwiftQL"]
        )
    ],
    dependencies: [
        // Depend on the latest Swift 5.9 prerelease of SwiftSyntax
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "SQLMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            linkerSettings: [.unsafeFlags(["-fprofile-instr-generate"])]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(
            name: "SwiftQL",
            dependencies: [
                "SQLMacros",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "SQLMacrosTests",
            dependencies: [
                "SwiftQL",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        
        //
        .testTarget(
            name: "SQLTests",
            dependencies: [
                "SwiftQL",
            ]
        ),
    ]
)
