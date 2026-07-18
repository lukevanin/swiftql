import Dispatch
import Foundation

public enum ComparisonBenchmarkConstants {
    public static let warmupCount = 10
    public static let sampleCount = 100
    public static let expectedRowCount = 16_143
    public static let selectedColumnCount = 14
}

public enum ComparisonBenchmarkError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case unsupportedImplementation(String, allowed: [String])
    case invalidProcessID(String)
    case missingFixture(String)
    case unexpectedRowCount(expected: Int, actual: Int)
    case zeroDuration(sample: Int)
    case zeroChecksum
    case checksumMismatch(first: UInt64, final: UInt64)
    case sqlite(String)
    case unexpectedSQLiteValue(column: Int, value: String)

    public var description: String {
        switch self {
        case let .invalidArguments(usage):
            return usage
        case let .unsupportedImplementation(name, allowed):
            return "unknown implementation '\(name)'; expected one of: \(allowed.joined(separator: ", "))"
        case let .invalidProcessID(value):
            return "process-id must be an integer from 1 through 3, got '\(value)'"
        case let .missingFixture(path):
            return "northwind-performance.sqlite is missing at \(path)"
        case let .unexpectedRowCount(expected, actual):
            return "Orders fetch returned \(actual) rows; expected \(expected)"
        case let .zeroDuration(sample):
            return "timed sample \(sample) did not produce a positive monotonic duration"
        case .zeroChecksum:
            return "result checksum was zero"
        case let .checksumMismatch(first, final):
            return "first and final Orders checksums differed: \(first) != \(final)"
        case let .sqlite(message):
            return "SQLite failure: \(message)"
        case let .unexpectedSQLiteValue(column, value):
            return "unexpected SQLite value in zero-based column \(column): \(value)"
        }
    }
}

public struct ComparisonBenchmarkConfiguration {
    public let implementation: String
    public let processID: Int

    public static func parse(
        arguments: [String] = CommandLine.arguments,
        allowedImplementations: Set<String>
    ) throws -> Self {
        let allowed = allowedImplementations.sorted()
        guard arguments.count == 3 else {
            let executable = URL(fileURLWithPath: arguments.first ?? "ComparisonBenchmark")
                .lastPathComponent
            throw ComparisonBenchmarkError.invalidArguments(
                "usage: \(executable) <implementation> <process-id>; implementations: \(allowed.joined(separator: ", "))"
            )
        }

        let implementation = arguments[1]
        guard allowedImplementations.contains(implementation) else {
            throw ComparisonBenchmarkError.unsupportedImplementation(
                implementation,
                allowed: allowed
            )
        }
        guard let processID = Int(arguments[2]), (1...3).contains(processID) else {
            throw ComparisonBenchmarkError.invalidProcessID(arguments[2])
        }
        return Self(implementation: implementation, processID: processID)
    }
}

/// The common 14-column Northwind Orders shape used by every handwritten
/// adapter. The optionality follows the fixture schema rather than observed
/// non-null values.
public protocol ComparisonBenchmarkOrderRow {
    var orderID: Int { get }
    var customerID: String? { get }
    var employeeID: Int? { get }
    var orderDate: String? { get }
    var requiredDate: String? { get }
    var shippedDate: String? { get }
    var shipVia: Int? { get }
    var freight: Double? { get }
    var shipName: String? { get }
    var shipAddress: String? { get }
    var shipCity: String? { get }
    var shipRegion: String? { get }
    var shipPostalCode: String? { get }
    var shipCountry: String? { get }
}

extension ComparisonBenchmarkOrderRow {
    public func addToComparisonChecksum(_ checksum: inout ComparisonBenchmarkChecksum) {
        checksum.combine(orderID)
        checksum.combine(customerID)
        checksum.combine(employeeID)
        checksum.combine(orderDate)
        checksum.combine(requiredDate)
        checksum.combine(shippedDate)
        checksum.combine(shipVia)
        checksum.combine(freight)
        checksum.combine(shipName)
        checksum.combine(shipAddress)
        checksum.combine(shipCity)
        checksum.combine(shipRegion)
        checksum.combine(shipPostalCode)
        checksum.combine(shipCountry)
    }
}

/// A small deterministic FNV-1a checksum. It observes every decoded field
/// after the first and final fetch, outside the measured intervals.
public struct ComparisonBenchmarkChecksum {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    private var state = offsetBasis

    public init() {}

    public var value: UInt64 { state }

    public mutating func combine(_ value: Int) {
        combine(UInt64(bitPattern: Int64(value)))
    }

    public mutating func combine(_ value: Int?) {
        guard let value else {
            combineMarker(0)
            return
        }
        combineMarker(1)
        combine(value)
    }

    public mutating func combine(_ value: Double?) {
        guard let value else {
            combineMarker(0)
            return
        }
        combineMarker(1)
        combine(value.bitPattern)
    }

    public mutating func combine(_ value: String?) {
        guard let value else {
            combineMarker(0)
            return
        }
        combineMarker(1)
        combine(UInt64(value.utf8.count))
        for byte in value.utf8 {
            combineByte(byte)
        }
    }

    private mutating func combine(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            for byte in bytes {
                combineByte(byte)
            }
        }
    }

    private mutating func combineMarker(_ marker: UInt8) {
        combineByte(marker)
    }

    private mutating func combineByte(_ byte: UInt8) {
        state ^= UInt64(byte)
        state &*= Self.prime
    }
}

public enum ComparisonBenchmarkDriver {
    public static func runRows<Rows: Collection>(
        configuration: ComparisonBenchmarkConfiguration,
        fetch: () throws -> Rows
    ) throws where Rows.Element: ComparisonBenchmarkOrderRow {
        try run(
            configuration: configuration,
            fetch: fetch,
            checksum: checksum
        )
    }

    public static func runCustom<Rows: Collection>(
        configuration: ComparisonBenchmarkConfiguration,
        fetch: () throws -> Rows,
        checksum: (Rows) throws -> UInt64
    ) throws {
        try run(
            configuration: configuration,
            fetch: fetch,
            checksum: checksum
        )
    }

    private static func checksum<Rows: Collection>(_ rows: Rows) -> UInt64
    where Rows.Element: ComparisonBenchmarkOrderRow {
        var checksum = ComparisonBenchmarkChecksum()
        for row in rows {
            row.addToComparisonChecksum(&checksum)
        }
        return checksum.value
    }

    private static func run<Rows: Collection>(
        configuration: ComparisonBenchmarkConfiguration,
        fetch: () throws -> Rows,
        checksum: (Rows) throws -> UInt64
    ) throws {
        let totalIterations = ComparisonBenchmarkConstants.warmupCount
            + ComparisonBenchmarkConstants.sampleCount
        var samples: [UInt64] = []
        samples.reserveCapacity(ComparisonBenchmarkConstants.sampleCount)
        var firstChecksum: UInt64?

        for iteration in 0..<totalIterations {
            let start = DispatchTime.now().uptimeNanoseconds
            let rows = try fetch()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start

            guard rows.count == ComparisonBenchmarkConstants.expectedRowCount else {
                throw ComparisonBenchmarkError.unexpectedRowCount(
                    expected: ComparisonBenchmarkConstants.expectedRowCount,
                    actual: rows.count
                )
            }
            if iteration == 0 || iteration == totalIterations - 1 {
                let resultChecksum = try checksum(rows)
                guard resultChecksum != 0 else {
                    throw ComparisonBenchmarkError.zeroChecksum
                }
                if let firstChecksum {
                    guard resultChecksum == firstChecksum else {
                        throw ComparisonBenchmarkError.checksumMismatch(
                            first: firstChecksum,
                            final: resultChecksum
                        )
                    }
                } else {
                    firstChecksum = resultChecksum
                }
            }

            if iteration >= ComparisonBenchmarkConstants.warmupCount {
                let sampleIndex = iteration - ComparisonBenchmarkConstants.warmupCount + 1
                guard elapsed > 0 else {
                    throw ComparisonBenchmarkError.zeroDuration(sample: sampleIndex)
                }
                samples.append(elapsed)
            }
        }

        guard firstChecksum != nil else {
            throw ComparisonBenchmarkError.zeroChecksum
        }

        let output = samples.enumerated().map { index, nanoseconds in
            "SAMPLE\t\(configuration.implementation)\t\(configuration.processID)\t\(index + 1)\t\(nanoseconds)"
        }.joined(separator: "\n") + "\n"
        FileHandle.standardOutput.write(Data(output.utf8))
    }
}
