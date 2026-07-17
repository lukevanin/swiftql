import Dispatch
import Foundation

final class BenchmarkSampler {
    typealias Hook = () throws -> Void
    typealias Clock = () -> UInt64

    private let configuration: BenchmarkConfiguration
    private let now: Clock

    init(
        configuration: BenchmarkConfiguration,
        now: @escaping Clock = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.configuration = configuration
        self.now = now
    }

    func measure<Value>(
        notes: [String] = [],
        beforeSample: Hook = {},
        afterSample: Hook = {},
        operation: () throws -> Value,
        consume: (Value) throws -> UInt64
    ) throws -> BenchmarkMeasurement {
        var warmupChecksum: UInt64 = 0
        var recordedChecksum: UInt64 = 0

        for _ in 0 ..< configuration.warmupCount {
            try withHooks(before: beforeSample, after: afterSample) {
                warmupChecksum &+= try consume(operation())
            }
        }

        var samples: [UInt64] = []
        samples.reserveCapacity(configuration.sampleCount)
        for _ in 0 ..< configuration.sampleCount {
            try beforeSample()
            do {
                let start = now()
                let value = try operation()
                let end = now()
                samples.append(end &- start)
                recordedChecksum &+= try consume(value)
                try afterSample()
            }
            catch {
                try? afterSample()
                throw error
            }
        }

        return BenchmarkMeasurement(
            samplesNanoseconds: samples,
            summary: try BenchmarkSummary.calculate(samples: samples),
            warmupChecksum: warmupChecksum,
            recordedSamplesChecksum: recordedChecksum,
            notes: notes
        )
    }

    private func withHooks(
        before: Hook,
        after: Hook,
        operation: () throws -> Void
    ) throws {
        try before()
        do {
            try operation()
            try after()
        }
        catch {
            try? after()
            throw error
        }
    }
}
