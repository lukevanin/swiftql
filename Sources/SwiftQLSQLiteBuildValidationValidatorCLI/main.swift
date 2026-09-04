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
        exit(result.exitCode)
    }
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(SQLiteBuildValidationValidatorCLIOptions.usage)
    exit(2)
}
