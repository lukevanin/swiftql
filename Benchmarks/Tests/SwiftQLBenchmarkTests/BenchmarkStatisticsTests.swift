import XCTest
@testable import SwiftQLBenchmarks

final class BenchmarkStatisticsTests: XCTestCase {
    func testMedianAndNearestRankP95() throws {
        let odd = try BenchmarkSummary.calculate(samples: [9, 1, 5])
        XCTAssertEqual(odd.minimumNanoseconds, 1)
        XCTAssertEqual(odd.medianNanoseconds, 5)
        XCTAssertEqual(odd.p95Nanoseconds, 9)
        XCTAssertEqual(odd.maximumNanoseconds, 9)

        let even = try BenchmarkSummary.calculate(samples: [4, 1, 3, 2])
        XCTAssertEqual(even.medianNanoseconds, 2.5)
        XCTAssertEqual(even.p95Nanoseconds, 4)

        let singleton = try BenchmarkSummary.calculate(samples: [42])
        XCTAssertEqual(singleton.medianNanoseconds, 42)
        XCTAssertEqual(singleton.p95Nanoseconds, 42)
    }

    func testEmptySamplesAreRejected() {
        XCTAssertThrowsError(try BenchmarkSummary.calculate(samples: []))
    }
}
