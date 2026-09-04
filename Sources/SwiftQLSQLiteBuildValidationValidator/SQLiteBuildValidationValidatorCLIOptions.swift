import Foundation
import SwiftQLSQLiteBuildValidationManifest


// Swift 5.9's Linux Foundation predates URL's Sendable annotation. Options are
// immutable values, and newer Foundation versions declare URL Sendable.
public struct SQLiteBuildValidationValidatorCLIOptions: Equatable, @unchecked Sendable {
    public let databaseURL: URL?
    public let manifestURL: URL?
    public let outputURL: URL?
    /// Where to write the advisory plan sidecar (#394), or `nil` when plan
    /// capture was not requested. Opt-in, so a run that does not ask for
    /// plans pays nothing for them.
    public let planOutputURL: URL?
    /// A checked-in plan-suppression file (#395), or `nil` for none.
    public let planSuppressionsURL: URL?
    /// The row count above which a full table scan is diagnosed. `nil` uses
    /// the documented default.
    public let planScanRowThreshold: Int?
    public let codecIdentifiers: [String]
    public let extensionNames: [String]
    public let capabilityIDs: [String]
    public let showsHelp: Bool

    /// Spelled out rather than left to the synthesized memberwise
    /// initializer, so `planOutputURL` can default to "no plan capture" and a
    /// caller that never asks for plans need not mention them.
    public init(
        databaseURL: URL?,
        manifestURL: URL?,
        outputURL: URL?,
        planOutputURL: URL? = nil,
        planSuppressionsURL: URL? = nil,
        planScanRowThreshold: Int? = nil,
        codecIdentifiers: [String] = [],
        extensionNames: [String] = [],
        capabilityIDs: [String] = [],
        showsHelp: Bool = false
    ) {
        self.databaseURL = databaseURL
        self.manifestURL = manifestURL
        self.outputURL = outputURL
        self.planOutputURL = planOutputURL
        self.planSuppressionsURL = planSuppressionsURL
        self.planScanRowThreshold = planScanRowThreshold
        self.codecIdentifiers = codecIdentifiers
        self.extensionNames = extensionNames
        self.capabilityIDs = capabilityIDs
        self.showsHelp = showsHelp
    }

    public static func parse(
        arguments: [String],
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) throws -> Self {
        var databasePath: String?
        var manifestPath: String?
        var outputPath: String?
        var planOutputPath: String?
        var planSuppressionsPath: String?
        var planScanRowThresholdText: String?
        var codecIdentifiers: [String] = []
        var extensionNames: [String] = []
        var capabilityIDs: [String] = []
        var showsHelp = false
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex) else {
                throw SQLiteBuildValidationValidatorCLIError.missingValue(option)
            }
            index = valueIndex
            let value = arguments[valueIndex]
            guard !value.isEmpty else {
                throw SQLiteBuildValidationValidatorCLIError.missingValue(option)
            }
            return value
        }

        func assignOnce(
            _ current: inout String?,
            option: String
        ) throws {
            guard current == nil else {
                throw SQLiteBuildValidationValidatorCLIError.duplicateOption(option)
            }
            current = try value(after: option)
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--database":
                try assignOnce(&databasePath, option: argument)
            case "--manifest":
                try assignOnce(&manifestPath, option: argument)
            case "--output":
                try assignOnce(&outputPath, option: argument)
            case "--plan-output":
                try assignOnce(&planOutputPath, option: argument)
            case "--plan-suppressions":
                try assignOnce(&planSuppressionsPath, option: argument)
            case "--plan-scan-row-threshold":
                try assignOnce(&planScanRowThresholdText, option: argument)
            case "--codec":
                codecIdentifiers.append(try value(after: argument))
            case "--extension":
                extensionNames.append(try value(after: argument))
            case "--capability":
                capabilityIDs.append(try value(after: argument))
            case "--help", "-h":
                showsHelp = true
            default:
                throw SQLiteBuildValidationValidatorCLIError.unknownOption(argument)
            }
            index += 1
        }

        if !showsHelp {
            for (option, value) in [
                ("--database", databasePath),
                ("--manifest", manifestPath),
                ("--output", outputPath),
            ] where value == nil {
                throw SQLiteBuildValidationValidatorCLIError.requiredOption(option)
            }
        }

        return Self(
            databaseURL: databasePath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            manifestURL: manifestPath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            outputURL: outputPath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            planOutputURL: planOutputPath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            planSuppressionsURL: planSuppressionsPath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            planScanRowThreshold: try planScanRowThresholdText.map {
                guard let value = Int($0), value >= 0 else {
                    throw SQLiteBuildValidationValidatorCLIError
                        .invalidValue("--plan-scan-row-threshold", $0)
                }
                return value
            },
            codecIdentifiers: sqliteBuildValidationSortedUnique(codecIdentifiers),
            extensionNames: sqliteBuildValidationSortedUnique(extensionNames),
            capabilityIDs: sqliteBuildValidationSortedUnique(capabilityIDs),
            showsHelp: showsHelp
        )
    }

    /// What the parsed arguments actually ask the CLI to do.
    ///
    /// The two are not variations of one shape: `--help` needs none of the
    /// operational paths, and a run needs all three. Modelling that as one
    /// options value with three optionals meant every consumer re-checked the
    /// same three optionals, and the runner's check for them was unreachable
    /// because parsing had already enforced it (#566).
    // `@unchecked` for the same reason the enclosing type is: these hold
    // `URL`, and Swift 5.9's Linux Foundation predates `URL: Sendable`. They
    // are immutable values.
    public enum Invocation: Equatable, @unchecked Sendable {
        case help
        case run(Resolved)
    }

    /// A run's settled inputs. Every path is present, because a run without one
    /// is not something ``resolved()`` returns.
    public struct Resolved: Equatable, @unchecked Sendable {
        public let databaseURL: URL
        public let manifestURL: URL
        public let outputURL: URL
        /// Present exactly when the run captures plans.
        public let planOutputURL: URL?
        public let planSuppressionsURL: URL?
        public let planScanRowThreshold: Int?
        public let environment: SQLiteBuildValidationEnvironment

        public init(
            databaseURL: URL,
            manifestURL: URL,
            outputURL: URL,
            planOutputURL: URL? = nil,
            planSuppressionsURL: URL? = nil,
            planScanRowThreshold: Int? = nil,
            environment: SQLiteBuildValidationEnvironment
        ) {
            self.databaseURL = databaseURL
            self.manifestURL = manifestURL
            self.outputURL = outputURL
            self.planOutputURL = planOutputURL
            self.planSuppressionsURL = planSuppressionsURL
            self.planScanRowThreshold = planScanRowThreshold
            self.environment = environment
        }

        /// The plan-diagnostic settings this run diagnoses under, reading the
        /// checked-in suppression file when one was named.
        public func planDiagnosticSettings() throws -> SQLiteBuildValidationPlanDiagnosticSettings {
            let suppressions = try planSuppressionsURL.map {
                try SQLiteBuildValidationPlanSuppressions.decode(contentsOf: $0)
            }
            return SQLiteBuildValidationPlanDiagnosticSettings(
                fullTableScanRowThreshold: planScanRowThreshold
                    ?? SQLiteBuildValidationPlanDiagnosticSettings
                        .defaultFullTableScanRowThreshold,
                suppressions: suppressions?.suppressions ?? []
            )
        }

        public var capturesPlans: Bool { planOutputURL != nil }
    }

    /// Settles these options into help or a run.
    ///
    /// ``parse(arguments:currentDirectory:)`` already refuses a run missing any
    /// required path, so for options that came from it this cannot throw. It
    /// can for options a caller built by hand, which is where the check now
    /// lives instead of in the runner.
    public func resolved() throws -> Invocation {
        if showsHelp {
            return .help
        }
        guard let databaseURL else {
            throw SQLiteBuildValidationValidatorCLIError.requiredOption("--database")
        }
        guard let manifestURL else {
            throw SQLiteBuildValidationValidatorCLIError.requiredOption("--manifest")
        }
        guard let outputURL else {
            throw SQLiteBuildValidationValidatorCLIError.requiredOption("--output")
        }
        return .run(Resolved(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: outputURL,
            planOutputURL: planOutputURL,
            planSuppressionsURL: planSuppressionsURL,
            planScanRowThreshold: planScanRowThreshold,
            environment: SQLiteBuildValidationEnvironment(
                codecIdentifiers: codecIdentifiers,
                extensionNames: extensionNames,
                capabilityIDs: capabilityIDs
            )
        ))
    }

    public static let usage = """
        Usage: swiftql-build-validate [options]

          --database <path>      Checked-in SQLite snapshot to open read-only
          --manifest <path>      Codable build-validation manifest (#292)
          --output <path>        Deterministic JSON report destination
          --plan-output <path>   Advisory query-plan sidecar destination
                                 (omit to skip plan capture entirely)
          --plan-suppressions <path>
                                 Checked-in advisory suppression rules
          --plan-scan-row-threshold <rows>
                                 Diagnose a full table scan only above this
                                 many rows (default 500)
          --codec <identity>     Available codec identity (repeatable)
          --extension <name>     Registered extension name (repeatable)
          --capability <id>      Explicit caller-owned capability (repeatable)
          --help, -h              Show this help
        """

    /// Refuses an output path that would clobber one of the inputs.
    ///
    /// Kept here as the CLI's entry point; the check itself is
    /// `SQLiteBuildValidationOutputSafetyPreflight` (#566), which is
    /// filesystem work rather than argument parsing. Plain backticks, not a
    /// DocC symbol link: that type is internal, and a link from a public
    /// symbol to one DocC cannot see fails the documentation build.
    public static func preflightOutputSafety(
        databaseURL: URL,
        manifestURL: URL,
        outputURL: URL,
        planOutputURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        try SQLiteBuildValidationOutputSafetyPreflight.check(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: outputURL,
            planOutputURL: planOutputURL,
            fileManager: fileManager
        )
    }

    private static func resolvedURL(path: String, currentDirectory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return currentDirectory.appendingPathComponent(path).standardizedFileURL
    }

}


public enum SQLiteBuildValidationValidatorCLIError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case missingValue(String)
    case duplicateOption(String)
    case requiredOption(String)
    case unknownOption(String)
    case invalidValue(String, String)
    case outputConflictsWithInput(String)
    case outputConflictsWithDatabaseSidecar
    case planOutputConflictsWithInput(String)
    case planOutputConflictsWithDatabaseSidecar
    case planOutputConflictsWithReportOutput

    public var description: String {
        switch self {
        case .missingValue(let option):
            return "\(option) requires a nonempty value."
        case .duplicateOption(let option):
            return "\(option) may only be supplied once."
        case .requiredOption(let option):
            return "\(option) is required."
        case .unknownOption(let option):
            return "Unknown option \(option)."
        case .invalidValue(let option, let value):
            return "\(option) requires a nonnegative integer; got \(value)."
        case .outputConflictsWithInput(let option):
            return "--output must not identify the same file as \(option)."
        case .outputConflictsWithDatabaseSidecar:
            return "--output must not use a SQLite sidecar path adjacent to --database."
        case .planOutputConflictsWithInput(let option):
            return "--plan-output must not identify the same file as \(option)."
        case .planOutputConflictsWithDatabaseSidecar:
            return "--plan-output must not use a SQLite sidecar path adjacent to --database."
        case .planOutputConflictsWithReportOutput:
            return "--plan-output must not identify the same file as --output."
        }
    }
}
