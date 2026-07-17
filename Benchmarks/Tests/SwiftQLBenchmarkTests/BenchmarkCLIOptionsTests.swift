import Foundation
import XCTest
@testable import SwiftQLBenchmarks

final class BenchmarkCLIOptionsTests: XCTestCase {
    func testParsesDocumentedOptions() throws {
        let root = URL(fileURLWithPath: "/tmp/swiftql")
        let options = try BenchmarkCLIOptions.parse(
            arguments: [
                "--warmups", "7",
                "--samples", "13",
                "--output", "results/report.json",
            ],
            currentDirectory: root
        )

        XCTAssertEqual(
            options.configuration,
            BenchmarkConfiguration(warmupCount: 7, sampleCount: 13)
        )
        XCTAssertEqual(options.outputURL.path, "/tmp/swiftql/results/report.json")
        XCTAssertFalse(options.showsHelp)
    }

    func testRejectsUnknownAndInvalidOptions() {
        XCTAssertThrowsError(
            try BenchmarkCLIOptions.parse(arguments: ["--unknown"])
        )
        XCTAssertThrowsError(
            try BenchmarkCLIOptions.parse(arguments: ["--samples", "0"])
        )
        XCTAssertThrowsError(
            try BenchmarkCLIOptions.parse(arguments: ["--warmups"])
        )
    }
}
