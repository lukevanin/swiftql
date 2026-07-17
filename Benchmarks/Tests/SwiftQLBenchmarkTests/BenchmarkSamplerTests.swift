import XCTest
@testable import SwiftQLBenchmarks

final class BenchmarkSamplerTests: XCTestCase {
    func testWarmupsRunButAreExcludedFromRawSamples() throws {
        var clockValues: [UInt64] = [100, 110, 200, 225]
        var operationCount = 0
        var beforeCount = 0
        var afterCount = 0
        let sampler = BenchmarkSampler(
            configuration: BenchmarkConfiguration(warmupCount: 2, sampleCount: 2),
            now: { clockValues.removeFirst() }
        )

        let measurement = try sampler.measure(
            beforeSample: { beforeCount += 1 },
            afterSample: { afterCount += 1 },
            operation: {
                operationCount += 1
                return UInt64(operationCount)
            },
            consume: { $0 }
        )

        XCTAssertEqual(operationCount, 4)
        XCTAssertEqual(beforeCount, 4)
        XCTAssertEqual(afterCount, 4)
        XCTAssertEqual(measurement.samplesNanoseconds, [10, 25])
        XCTAssertEqual(measurement.warmupChecksum, 3)
        XCTAssertEqual(measurement.recordedSamplesChecksum, 7)
    }

    func testCleanupRunsWhenOperationThrows() {
        enum TestError: Error { case expected }
        var cleanupCount = 0
        let sampler = BenchmarkSampler(
            configuration: BenchmarkConfiguration(warmupCount: 0, sampleCount: 1),
            now: { 0 }
        )

        XCTAssertThrowsError(
            try sampler.measure(
                afterSample: { cleanupCount += 1 },
                operation: { throw TestError.expected },
                consume: { (_: Int) in 0 }
            )
        )
        XCTAssertEqual(cleanupCount, 1)
    }
}
