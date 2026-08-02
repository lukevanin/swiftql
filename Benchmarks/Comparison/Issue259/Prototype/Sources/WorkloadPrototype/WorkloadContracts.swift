import Dispatch
import Foundation

/// The three workload families this prototype validates. Each one has a
/// falsifiable semantic contract: the same schema, the same selected columns,
/// the same predicate or mutation, the same transaction boundary, and the same
/// checksum oracle across every implementation.
enum PrototypeWorkload: String, CaseIterable {
    /// One indexed row by `OrderID`, all 14 `Orders` columns, decoded.
    case pointLookup = "point_lookup"
    /// `Orders` joined to `Customers`, grouped by country, counted and totalled.
    case joinAggregate = "join_aggregate"
    /// 100 parameterised inserts inside one explicit transaction, committed.
    case transactionalWrite = "transactional_write"

    var requiresWritableDatabase: Bool {
        self == .transactionalWrite
    }
}

enum PrototypeImplementation: String, CaseIterable {
    case swiftql
    case grdb
    case sqliteSwift = "sqlite_swift"
}

enum PrototypeConstants {
    static let warmupCount = 10
    static let sampleCount = 100

    /// `Orders.OrderID` is a contiguous `INTEGER PRIMARY KEY AUTOINCREMENT`
    /// range in the committed fixture, so these identifiers all exist.
    static let firstOrderID = 10_248
    static let orderCount = 16_143
    static let lookupKeyCount = 256
    static let lookupKeyStride = 63

    /// Distinct `Customers.Country` groups reachable from `Orders`, including
    /// the group for the two customers whose `Country` is NULL.
    static let expectedCountryGroupCount = 22

    /// Rows inserted per timed transaction.
    static let writeBatchSize = 100
    static let scratchTableName = "Issue259PrototypeWrites"

    static let selectedOrderColumnCount = 14

    /// Stored, not computed. Every adapter reads this from inside the timed
    /// operation, so rebuilding the array per call would charge each sample for
    /// 256 allocations that belong to no library.
    static let lookupKeys: [Int] = (0..<lookupKeyCount).map { index in
        firstOrderID + index * lookupKeyStride
    }

    /// Every timed transaction writes this exact batch and the reset clears it,
    /// so committed state is identical before and after every iteration. That
    /// is what lets the value oracle compare a fixed expectation instead of
    /// comparing one iteration against another.
    ///
    /// Stored for the same reason as `lookupKeys`: rebuilding it per call would
    /// put 100 string interpolations inside every timed transaction.
    static let writeBatch: [(id: Int, name: String, amount: Double)] =
        (0..<writeBatchSize).map { offset in
            (id: offset, name: "row-\(offset)", amount: Double(offset) / 4.0)
        }

    static let expectedScratchChecksum: UInt64 = {
        var checksum = PrototypeChecksum()
        for row in writeBatch {
            checksum.combine(row.id)
            checksum.combine(row.name)
            checksum.combine(row.amount)
        }
        return checksum.value
    }()
}

enum PrototypeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case unknownWorkload(String)
    case unknownImplementation(String)
    case invalidProcessID(String)
    case missingDatabase(String)
    case unexpectedRowCount(workload: String, expected: Int, actual: Int)
    case unexpectedChangeCount(expected: Int, actual: Int)
    case zeroDuration(sample: Int)
    case checksumMismatch(expected: UInt64, observed: UInt64)
    case unexpectedLookupKey(expected: Int, actual: Int)
    case zeroChecksum
    case sqlite(String)

    var description: String {
        switch self {
        case let .invalidArguments(usage):
            return usage
        case let .unknownWorkload(value):
            let allowed = PrototypeWorkload.allCases.map(\.rawValue).joined(separator: ", ")
            return "unknown workload '\(value)'; expected one of: \(allowed)"
        case let .unknownImplementation(value):
            let allowed = PrototypeImplementation.allCases
                .map(\.rawValue)
                .joined(separator: ", ")
            return "unknown implementation '\(value)'; expected one of: \(allowed)"
        case let .invalidProcessID(value):
            return "process-id must be a positive integer, got '\(value)'"
        case let .missingDatabase(path):
            return "database is missing at \(path)"
        case let .unexpectedRowCount(workload, expected, actual):
            return "\(workload) produced \(actual) rows; expected \(expected)"
        case let .unexpectedChangeCount(expected, actual):
            return "transaction inserted \(actual) rows; expected \(expected)"
        case let .zeroDuration(sample):
            return "timed sample \(sample) did not produce a positive duration"
        case let .checksumMismatch(expected, observed):
            return """
                decoded result checksum \(observed) does not match the \
                independently computed expectation \(expected)
                """
        case let .unexpectedLookupKey(expected, actual):
            return "point lookup returned OrderID \(actual); expected \(expected)"
        case .zeroChecksum:
            return "result checksum was zero"
        case let .sqlite(message):
            return "SQLite failure: \(message)"
        }
    }
}

/// The shared 14-column `Orders` shape. Optionality follows the fixture
/// schema, not the values that happen to be present.
struct PrototypeOrder {
    var orderID: Int
    var customerID: String?
    var employeeID: Int?
    var orderDate: String?
    var requiredDate: String?
    var shippedDate: String?
    var shipVia: Int?
    var freight: Double?
    var shipName: String?
    var shipAddress: String?
    var shipCity: String?
    var shipRegion: String?
    var shipPostalCode: String?
    var shipCountry: String?
}

/// The shared join/aggregate result shape.
struct PrototypeCountryVolume {
    var country: String?
    var orderCount: Int
    var freightTotal: Double
}

/// Deterministic FNV-1a checksum. It observes every decoded field of the
/// first and final iteration, always outside the timed interval.
struct PrototypeChecksum {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    private var state = offsetBasis

    var value: UInt64 { state }

    mutating func combine(_ value: Int) {
        combine(UInt64(bitPattern: Int64(value)))
    }

    mutating func combine(_ value: Int?) {
        guard let value else {
            combineByte(0)
            return
        }
        combineByte(1)
        combine(value)
    }

    mutating func combine(_ value: Double) {
        combine(value.bitPattern)
    }

    mutating func combine(_ value: Double?) {
        guard let value else {
            combineByte(0)
            return
        }
        combineByte(1)
        combine(value.bitPattern)
    }

    mutating func combine(_ value: String?) {
        guard let value else {
            combineByte(0)
            return
        }
        combineByte(1)
        combine(UInt64(value.utf8.count))
        for byte in value.utf8 {
            combineByte(byte)
        }
    }

    mutating func combine(_ order: PrototypeOrder) {
        combine(order.orderID)
        combine(order.customerID)
        combine(order.employeeID)
        combine(order.orderDate)
        combine(order.requiredDate)
        combine(order.shippedDate)
        combine(order.shipVia)
        combine(order.freight)
        combine(order.shipName)
        combine(order.shipAddress)
        combine(order.shipCity)
        combine(order.shipRegion)
        combine(order.shipPostalCode)
        combine(order.shipCountry)
    }

    mutating func combine(_ volume: PrototypeCountryVolume) {
        combine(volume.country)
        combine(volume.orderCount)
        // TOTAL() returns a REAL that both libraries round identically, but
        // comparing raw bit patterns across implementations would make the
        // oracle sensitive to the last ulp. Round to cents first.
        combine((volume.freightTotal * 100.0).rounded())
    }

    private mutating func combine(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            for byte in bytes {
                combineByte(byte)
            }
        }
    }

    private mutating func combineByte(_ byte: UInt8) {
        state ^= UInt64(byte)
        state &*= Self.prime
    }
}

struct PrototypeConfiguration {
    let workload: PrototypeWorkload
    let implementation: PrototypeImplementation
    let processID: Int
    let databaseURL: URL

    static func parse(arguments: [String] = CommandLine.arguments) throws -> Self {
        guard arguments.count == 5 else {
            let executable = URL(fileURLWithPath: arguments.first ?? "WorkloadPrototype")
                .lastPathComponent
            throw PrototypeError.invalidArguments(
                "usage: \(executable) <workload> <implementation> <process-id> "
                    + "<database-path>"
            )
        }
        guard let workload = PrototypeWorkload(rawValue: arguments[1]) else {
            throw PrototypeError.unknownWorkload(arguments[1])
        }
        guard let implementation = PrototypeImplementation(rawValue: arguments[2]) else {
            throw PrototypeError.unknownImplementation(arguments[2])
        }
        guard let processID = Int(arguments[3]), processID >= 1 else {
            throw PrototypeError.invalidProcessID(arguments[3])
        }
        let databaseURL = URL(fileURLWithPath: arguments[4])
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw PrototypeError.missingDatabase(databaseURL.path)
        }
        return Self(
            workload: workload,
            implementation: implementation,
            processID: processID,
            databaseURL: databaseURL
        )
    }
}

/// Times one operation per iteration and prints raw samples. Preparation,
/// correctness checks, checksum computation, and any state reset happen
/// outside the measured interval.
enum PrototypeDriver {
    /// - Parameters:
    ///   - operation: the only thing inside the clock. It receives the
    ///     iteration index so a workload can vary its bound parameters.
    ///   - verify: the cheap state oracle, run after every iteration, outside
    ///     timing.
    ///   - checksum: the value oracle over the decoded result. It runs on the
    ///     first and final iteration only, so a full field hash never becomes a
    ///     workload sitting between two timed samples.
    ///   - expectedChecksum: what `checksum` must produce for that iteration,
    ///     computed independently of the measured library. Comparing against an
    ///     independent expectation rather than against the first iteration is
    ///     what lets a workload bind a different parameter on every iteration.
    ///   - reset: restores the pre-iteration state for mutating workloads,
    ///     outside timing.
    static func run<Result>(
        configuration: PrototypeConfiguration,
        operation: (Int) throws -> Result,
        verify: (Int, Result) throws -> Void,
        checksum: (Int, Result) throws -> UInt64,
        expectedChecksum: (Int) throws -> UInt64,
        reset: () throws -> Void = {}
    ) throws {
        let total = PrototypeConstants.warmupCount + PrototypeConstants.sampleCount
        var samples: [UInt64] = []
        samples.reserveCapacity(PrototypeConstants.sampleCount)
        var checkedIterations = 0

        for iteration in 0..<total {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = try operation(iteration)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start

            try verify(iteration, result)
            if iteration == 0 || iteration == total - 1 {
                let observed = try checksum(iteration, result)
                let expected = try expectedChecksum(iteration)
                guard observed != 0 else { throw PrototypeError.zeroChecksum }
                guard observed == expected else {
                    throw PrototypeError.checksumMismatch(
                        expected: expected,
                        observed: observed
                    )
                }
                checkedIterations += 1
            }
            if iteration >= PrototypeConstants.warmupCount {
                let sampleIndex = iteration - PrototypeConstants.warmupCount + 1
                guard elapsed > 0 else {
                    throw PrototypeError.zeroDuration(sample: sampleIndex)
                }
                samples.append(elapsed)
            }
            try reset()
        }

        guard checkedIterations == 2 else {
            throw PrototypeError.zeroChecksum
        }

        let output = samples.enumerated().map { index, nanoseconds in
            "SAMPLE\t\(configuration.workload.rawValue)\t"
                + "\(configuration.implementation.rawValue)\t\(configuration.processID)\t"
                + "\(index + 1)\t\(nanoseconds)"
        }.joined(separator: "\n") + "\n"
        FileHandle.standardOutput.write(Data(output.utf8))
    }
}
