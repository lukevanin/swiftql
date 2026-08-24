import Foundation
import SwiftQLSQLiteBuildValidationManifest


public struct SQLiteBuildValidationValidatorCLIRunResult: Equatable, Sendable {
    public let report: SQLiteBuildValidationReport

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
        let report = try validate(resolved)
        try write(report, to: resolved.outputURL)
        return SQLiteBuildValidationValidatorCLIRunResult(report: report)
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
        try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
            databaseURL: resolved.databaseURL,
            manifestURL: resolved.manifestURL,
            outputURL: resolved.outputURL
        )
        let manifest = try SQLiteBuildValidationManifest.decode(
            contentsOf: resolved.manifestURL
        )
        return try SQLiteBuildValidator.validate(
            manifest: manifest,
            againstDatabaseAt: resolved.databaseURL,
            environment: resolved.environment
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
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try report.canonicalJSONData().write(to: outputURL, options: .atomic)
    }
}
