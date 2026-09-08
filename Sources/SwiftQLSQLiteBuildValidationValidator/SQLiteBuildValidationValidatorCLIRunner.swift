import Foundation
import SwiftQLSQLiteBuildValidationManifest


public struct SQLiteBuildValidationValidatorCLIRunResult: Equatable, Sendable {
    public let report: SQLiteBuildValidationReport
    /// The advisory plan sidecar, when `--plan-output` asked for one.
    public let planReport: SQLiteBuildValidationPlanReport?

    public init(
        report: SQLiteBuildValidationReport,
        planReport: SQLiteBuildValidationPlanReport? = nil
    ) {
        self.report = report
        self.planReport = planReport
    }

    /// Decided by the correctness verdict alone. Plan capture adds data, not
    /// judgement: a run whose every plan is unsupported still exits zero if
    /// the manifest validated.
    public var exitCode: Int32 {
        report.overallVerdict == .passed ? 0 : 1
    }
}


/// Executes the operational CLI path without terminating the process.
///
/// Keeping orchestration here lets tests exercise input protection, manifest
/// decoding, real SQLite validation, report writing, and the zero/nonzero
/// verdict contract. The executable entry point remains responsible only for
/// argument/help handling and mapping thrown usage errors to exit code 2.
public enum SQLiteBuildValidationValidatorCLIRunner {

    /// Parses, validates, and writes the report -- the whole operational path.
    public static func run(
        options: SQLiteBuildValidationValidatorCLIOptions
    ) throws -> SQLiteBuildValidationValidatorCLIRunResult {
        guard case .run(let resolved) = try options.resolved() else {
            throw SQLiteBuildValidationValidatorCLIError.requiredOption(
                "--database, --manifest, and --output"
            )
        }
        return try run(resolved)
    }

    /// The same, from options that are already settled.
    public static func run(
        _ resolved: SQLiteBuildValidationValidatorCLIOptions.Resolved
    ) throws -> SQLiteBuildValidationValidatorCLIRunResult {
        let result = try validateCapturingPlans(resolved)
        try write(result.report, to: resolved.outputURL)
        if let planReport = result.planReport, let planOutputURL = resolved.planOutputURL {
            try write(planReport, to: planOutputURL)
        }
        return SQLiteBuildValidationValidatorCLIRunResult(
            report: result.report,
            planReport: result.planReport
        )
    }

    /// Protects the inputs, decodes the manifest, and validates -- everything
    /// up to, but not including, producing a file.
    ///
    /// Separate from ``write(_:to:)`` (#566) so a caller can validate without
    /// writing anything, which is what makes the report's own content testable
    /// apart from the filesystem effects of emitting it.
    public static func validate(
        _ resolved: SQLiteBuildValidationValidatorCLIOptions.Resolved
    ) throws -> SQLiteBuildValidationReport {
        try validateCapturingPlans(resolved).report
    }

    /// The same, keeping the advisory plan sidecar when `--plan-output` asked
    /// for one.
    ///
    /// A second entry point rather than a changed return type on
    /// ``validate(_:)``, so a caller that only wants the correctness report
    /// keeps the signature it already compiles against.
    public static func validateCapturingPlans(
        _ resolved: SQLiteBuildValidationValidatorCLIOptions.Resolved
    ) throws -> SQLiteBuildValidationRunResult {
        try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
            databaseURL: resolved.databaseURL,
            manifestURL: resolved.manifestURL,
            outputURL: resolved.outputURL,
            planOutputURL: resolved.planOutputURL
        )
        let manifest = try SQLiteBuildValidationManifest.decode(
            contentsOf: resolved.manifestURL
        )
        return try SQLiteBuildValidator.run(
            manifest: manifest,
            againstDatabaseAt: resolved.databaseURL,
            environment: resolved.environment,
            capturesPlans: resolved.capturesPlans
        )
    }

    /// Writes the canonical report, creating its directory if needed.
    ///
    /// Atomic, because the plugin treats the report as a build output: a
    /// half-written one would be read as the result of a run that in fact
    /// crashed partway.
    public static func write(
        _ report: SQLiteBuildValidationReport,
        to outputURL: URL
    ) throws {
        try write(canonicalJSONData: try report.canonicalJSONData(), to: outputURL)
    }

    /// Writes the canonical plan sidecar, on the same terms.
    public static func write(
        _ planReport: SQLiteBuildValidationPlanReport,
        to outputURL: URL
    ) throws {
        try write(canonicalJSONData: try planReport.canonicalJSONData(), to: outputURL)
    }

    private static func write(canonicalJSONData: Data, to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try canonicalJSONData.write(to: outputURL, options: .atomic)
    }
}
