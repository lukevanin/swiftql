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
    public static func run(
        options: SQLiteBuildValidationValidatorCLIOptions
    ) throws -> SQLiteBuildValidationValidatorCLIRunResult {
        guard let databaseURL = options.databaseURL,
              let manifestURL = options.manifestURL,
              let outputURL = options.outputURL else {
            throw SQLiteBuildValidationValidatorCLIError.requiredOption(
                "--database, --manifest, and --output"
            )
        }

        try SQLiteBuildValidationValidatorCLIOptions.preflightOutputSafety(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: outputURL
        )

        let manifest = try SQLiteBuildValidationManifest.decode(contentsOf: manifestURL)
        let report = try SQLiteBuildValidator.validate(
            manifest: manifest,
            againstDatabaseAt: databaseURL,
            environment: SQLiteBuildValidationEnvironment(
                codecIdentifiers: options.codecIdentifiers,
                extensionNames: options.extensionNames,
                capabilityIDs: options.capabilityIDs
            )
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try report.canonicalJSONData().write(to: outputURL, options: .atomic)
        return SQLiteBuildValidationValidatorCLIRunResult(report: report)
    }
}
