import Foundation
import SwiftQLSQLiteBuildValidationValidator

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

do {
    let options = try SQLiteBuildValidationValidatorCLIOptions.parse(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
    switch try options.resolved() {
    case .help:
        print(SQLiteBuildValidationValidatorCLIOptions.usage)
        exit(EXIT_SUCCESS)
    case .run(let resolved):
        let result = try SQLiteBuildValidationValidatorCLIRunner.run(resolved)
        // The canonical report is the artifact of record; the summary is only
        // a human-readable forwarding of its own diagnostics to stderr so a
        // failing build surfaces something actionable without requiring the
        // caller to open the report file. It is empty on a pass.
        let summary = result.report.humanReadableSummary()
        if !summary.isEmpty {
            writeStandardError(summary)
        }
        // Advisory findings print alongside, and never touch the exit code:
        // it is `result.exitCode`, which reads the correctness verdict alone.
        // Attributed to the manifest, so the advisory lines take the
        // `<path>: warning: <message>` form a build log and Xcode's issue
        // navigator already parse. The manifest is the honest origin: it is
        // where the statement this advice is about is recorded.
        let advisorySummary = result.planReport?.humanReadableSummary(
            origin: resolved.manifestURL.path
        ) ?? ""
        if !advisorySummary.isEmpty {
            writeStandardError(advisorySummary)
        }
        exit(result.exitCode)
    }
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(SQLiteBuildValidationValidatorCLIOptions.usage)
    exit(2)
}
