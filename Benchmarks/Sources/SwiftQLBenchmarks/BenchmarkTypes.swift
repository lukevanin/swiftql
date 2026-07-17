import Foundation

public enum BenchmarkPhase: String, Codable, CaseIterable {
    case swiftQLConstructionAndRendering = "swiftql_construction_and_rendering"
    case coldStatementPreparation = "cold_statement_preparation"
    case cachedStatementLookup = "cached_statement_lookup"
    case statementResetAndBinding = "statement_reset_and_binding"
    case execution
    case rowDecoding = "row_decoding"
}

public struct BenchmarkConfiguration: Codable, Equatable, Sendable {
    public var warmupCount: Int
    public var sampleCount: Int

    public init(warmupCount: Int, sampleCount: Int) {
        self.warmupCount = warmupCount
        self.sampleCount = sampleCount
    }

    public static let standard = BenchmarkConfiguration(
        warmupCount: 50,
        sampleCount: 500
    )

    public static let smoke = BenchmarkConfiguration(
        warmupCount: 0,
        sampleCount: 1
    )

    public func validate() throws {
        guard warmupCount >= 0 else {
            throw BenchmarkError.invalidConfiguration("warmup count must not be negative")
        }
        guard sampleCount > 0 else {
            throw BenchmarkError.invalidConfiguration("sample count must be greater than zero")
        }
    }
}

public struct BenchmarkSummary: Codable, Equatable {
    public let minimumNanoseconds: Double
    public let medianNanoseconds: Double
    public let p95Nanoseconds: Double
    public let maximumNanoseconds: Double

    public static func calculate(samples: [UInt64]) throws -> BenchmarkSummary {
        guard !samples.isEmpty else {
            throw BenchmarkError.invalidSamples("at least one sample is required")
        }

        let sorted = samples.sorted()
        let middle = sorted.count / 2
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            median = (Double(sorted[middle - 1]) + Double(sorted[middle])) / 2
        }
        else {
            median = Double(sorted[middle])
        }

        // Nearest-rank percentile: rank = ceil(0.95 * N), using a zero-based index below.
        let p95Rank = max(1, Int(ceil(Double(sorted.count) * 0.95)))
        return BenchmarkSummary(
            minimumNanoseconds: Double(sorted[0]),
            medianNanoseconds: median,
            p95Nanoseconds: Double(sorted[p95Rank - 1]),
            maximumNanoseconds: Double(sorted[sorted.count - 1])
        )
    }
}

public struct BenchmarkMeasurement: Codable, Equatable {
    public let samplesNanoseconds: [UInt64]
    public let summary: BenchmarkSummary
    public let warmupChecksum: UInt64
    public let recordedSamplesChecksum: UInt64
    public let notes: [String]
}

public enum BenchmarkPhaseApplicability: String, Codable {
    case measured
    case notApplicable = "not_applicable"
}

public struct BenchmarkPhaseReport: Codable, Equatable {
    public let phase: BenchmarkPhase
    public let applicability: BenchmarkPhaseApplicability
    public let measurement: BenchmarkMeasurement?
    public let reason: String?

    public static func measured(
        _ phase: BenchmarkPhase,
        measurement: BenchmarkMeasurement
    ) -> BenchmarkPhaseReport {
        BenchmarkPhaseReport(
            phase: phase,
            applicability: .measured,
            measurement: measurement,
            reason: nil
        )
    }

    public static func notApplicable(
        _ phase: BenchmarkPhase,
        reason: String
    ) -> BenchmarkPhaseReport {
        BenchmarkPhaseReport(
            phase: phase,
            applicability: .notApplicable,
            measurement: nil,
            reason: reason
        )
    }
}

public struct BenchmarkParameter: Codable, Equatable {
    public let name: String
    public let swiftType: String
    public let sqliteStorageClass: String
    public let valueDescription: String

    public init(
        name: String,
        swiftType: String,
        sqliteStorageClass: String,
        valueDescription: String
    ) {
        self.name = name
        self.swiftType = swiftType
        self.sqliteStorageClass = sqliteStorageClass
        self.valueDescription = valueDescription
    }
}

public struct BenchmarkCaseReport: Codable, Equatable {
    public let identifier: String
    public let purpose: String
    public let sql: String
    public let parameters: [BenchmarkParameter]
    public let queryPlan: [String]
    public let expectedResultRowCount: Int?
    public let expectedAffectedRowCount: Int?
    public let phases: [BenchmarkPhaseReport]
}

public struct BenchmarkEnvironment: Codable, Equatable {
    public let buildConfiguration: String
    public let swiftVersion: String
    public let xcodeVersion: String
    public let sdkVersion: String
    public let grdbVersion: String
    public let grdbRevision: String
    public let repositoryRevision: String
    public let repositoryState: String
    public let operatingSystem: String
    public let architecture: String
    public let machineModel: String
    public let processor: String
    public let processorCount: Int
    public let activeProcessorCount: Int
    public let physicalMemoryBytes: UInt64
    public let runnerImageOS: String?
    public let runnerImageVersion: String?
}

public struct BenchmarkDatabaseMetadata: Codable, Equatable {
    public let storage: String
    public let sqliteVersion: String
    public let sqliteSourceID: String
    public let compileOptions: [String]
    public let journalMode: String
    public let synchronous: Int
    public let pageSizeBytes: Int
}

public struct BenchmarkFixtureMetadata: Codable, Equatable {
    public let version: Int
    public let companyCount: Int
    public let departmentCount: Int
    public let personCount: Int
    public let decodeFixtureRowCount: Int
}

public struct BenchmarkReport: Codable, Equatable {
    public let formatVersion: Int
    public let generatedAt: String
    public let monotonicClock: String
    public let sampleUnit: String
    public let configuration: BenchmarkConfiguration
    public let environment: BenchmarkEnvironment
    public let database: BenchmarkDatabaseMetadata
    public let fixture: BenchmarkFixtureMetadata
    public let schemaSQL: [String]
    public let cases: [BenchmarkCaseReport]

    public var measurementCount: Int {
        cases.reduce(0) { partial, benchmarkCase in
            partial + benchmarkCase.phases.filter { $0.applicability == .measured }.count
        }
    }

    public func validate() throws {
        try configuration.validate()
        guard formatVersion == 1 else {
            throw BenchmarkError.invalidReport("unsupported report format version \(formatVersion)")
        }
        guard !generatedAt.isEmpty else {
            throw BenchmarkError.invalidReport("generated-at timestamp is missing")
        }
        guard monotonicClock == "DispatchTime.uptimeNanoseconds",
              sampleUnit == "nanoseconds_per_operation" else {
            throw BenchmarkError.invalidReport("clock or sample unit is unsupported")
        }
        guard ["debug", "release"].contains(environment.buildConfiguration),
              !environment.swiftVersion.isEmpty,
              !environment.grdbVersion.isEmpty,
              !environment.grdbRevision.isEmpty,
              !environment.repositoryRevision.isEmpty,
              !environment.repositoryState.isEmpty,
              !environment.operatingSystem.isEmpty,
              !environment.architecture.isEmpty else {
            throw BenchmarkError.invalidReport("required environment metadata is missing")
        }
        guard !database.sqliteVersion.isEmpty,
              !database.sqliteSourceID.isEmpty,
              !database.compileOptions.isEmpty,
              !database.journalMode.isEmpty,
              database.pageSizeBytes > 0 else {
            throw BenchmarkError.invalidReport("required SQLite metadata is missing")
        }
        guard fixture.companyCount > 0,
              fixture.departmentCount > 0,
              fixture.personCount > 0,
              fixture.decodeFixtureRowCount > 0 else {
            throw BenchmarkError.invalidReport("fixture metadata is invalid")
        }
        guard !schemaSQL.isEmpty, !cases.isEmpty else {
            throw BenchmarkError.invalidReport("schema and benchmark cases must not be empty")
        }

        let identifiers = cases.map(\.identifier)
        guard Set(identifiers).count == identifiers.count else {
            throw BenchmarkError.invalidReport("benchmark case identifiers must be unique")
        }

        var observedPhases = Set<BenchmarkPhase>()
        for benchmarkCase in cases {
            guard !benchmarkCase.sql.isEmpty else {
                throw BenchmarkError.invalidReport("case \(benchmarkCase.identifier) is incomplete")
            }
            let phases = benchmarkCase.phases.map(\.phase)
            guard benchmarkCase.phases.count == BenchmarkPhase.allCases.count,
                  Set(phases) == Set(BenchmarkPhase.allCases) else {
                throw BenchmarkError.invalidReport("case \(benchmarkCase.identifier) must define every phase exactly once")
            }
            observedPhases.formUnion(phases)

            for phaseReport in benchmarkCase.phases {
                switch phaseReport.applicability {
                case .measured:
                    guard let measurement = phaseReport.measurement,
                          phaseReport.reason == nil else {
                        throw BenchmarkError.invalidReport("measured phase has no measurement")
                    }
                    guard measurement.samplesNanoseconds.count == configuration.sampleCount else {
                        throw BenchmarkError.invalidReport("sample count differs from report configuration")
                    }
                    let calculated = try BenchmarkSummary.calculate(
                        samples: measurement.samplesNanoseconds
                    )
                    guard calculated == measurement.summary else {
                        throw BenchmarkError.invalidReport("stored summary does not match raw samples")
                    }
                case .notApplicable:
                    guard phaseReport.measurement == nil,
                          let reason = phaseReport.reason,
                          !reason.isEmpty else {
                        throw BenchmarkError.invalidReport("not-applicable phase requires a reason and no measurement")
                    }
                }
            }
        }

        guard observedPhases == Set(BenchmarkPhase.allCases) else {
            throw BenchmarkError.invalidReport("the report does not cover every benchmark phase")
        }
    }

    public func encodedJSON() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func humanReadableSummary() -> String {
        var lines = [
            "SwiftQL performance baseline",
            "Build: \(environment.buildConfiguration)",
            "Swift: \(firstLine(environment.swiftVersion))",
            "Xcode: \(firstLine(environment.xcodeVersion))",
            "SDK: \(environment.sdkVersion)",
            "GRDB: \(environment.grdbVersion)",
            "SQLite: \(database.sqliteVersion)",
            "Machine: \(environment.machineModel) (\(environment.architecture))",
            "Warmups: \(configuration.warmupCount), samples: \(configuration.sampleCount), one operation per sample",
        ]

        for benchmarkCase in cases {
            lines.append("")
            lines.append("[\(benchmarkCase.identifier)]")
            for phaseReport in benchmarkCase.phases {
                if let measurement = phaseReport.measurement {
                    lines.append(
                        "  \(phaseReport.phase.rawValue): median \(formatDuration(measurement.summary.medianNanoseconds)), p95 \(formatDuration(measurement.summary.p95Nanoseconds))"
                    )
                }
                else {
                    lines.append(
                        "  \(phaseReport.phase.rawValue): not applicable (\(phaseReport.reason ?? "unspecified"))"
                    )
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum BenchmarkError: Error, CustomStringConvertible, Equatable {
    case invalidConfiguration(String)
    case invalidSamples(String)
    case invalidReport(String)
    case invalidArguments(String)
    case missingFixture(String)
    case decoding(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid benchmark configuration: \(message)"
        case .invalidSamples(let message):
            return "Invalid benchmark samples: \(message)"
        case .invalidReport(let message):
            return "Invalid benchmark report: \(message)"
        case .invalidArguments(let message):
            return "Invalid benchmark arguments: \(message)"
        case .missingFixture(let message):
            return "Missing benchmark fixture: \(message)"
        case .decoding(let message):
            return "Benchmark row decoding failed: \(message)"
        }
    }
}

private func firstLine(_ value: String) -> String {
    value.split(whereSeparator: \.isNewline).first.map(String.init) ?? value
}

private func formatDuration(_ nanoseconds: Double) -> String {
    if nanoseconds >= 1_000_000 {
        return String(format: "%.3f ms", nanoseconds / 1_000_000)
    }
    if nanoseconds >= 1_000 {
        return String(format: "%.3f us", nanoseconds / 1_000)
    }
    return String(format: "%.1f ns", nanoseconds)
}
