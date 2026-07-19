import Foundation


package struct SQLiteBuildValidationCLIRunResult: Equatable, Sendable {
    package let report: SQLiteBuildValidationReport

    package var exitCode: Int32 {
        report.overallVerdict == .passed ? 0 : 1
    }
}


/// Executes the operational CLI path without terminating the process.
///
/// Keeping orchestration here lets tests exercise input protection, plan
/// decoding, real SQLite validation, report writing, and the zero/nonzero
/// verdict contract. The executable entry point remains responsible only for
/// argument/help handling and mapping thrown usage errors to exit code 2.
package enum SQLiteBuildValidationCLIRunner {
    package static func run(
        options: SQLiteBuildValidationCLIOptions
    ) throws -> SQLiteBuildValidationCLIRunResult {
        guard let databaseURL = options.databaseURL,
              let planURL = options.planURL,
              let outputURL = options.outputURL else {
            throw SQLiteBuildValidationCLIError.requiredOption(
                "--database, --plan, and --output"
            )
        }

        try SQLiteBuildValidationCLIOptions.preflightOutputSafety(
            databaseURL: databaseURL,
            planURL: planURL,
            outputURL: outputURL
        )

        let plan = try SQLiteBuildValidationPlan.decode(contentsOf: planURL)
        let report = try SQLiteBuildValidator.validate(
            plan: plan,
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
        return SQLiteBuildValidationCLIRunResult(report: report)
    }
}
