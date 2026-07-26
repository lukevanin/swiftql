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
    if options.showsHelp {
        print(SQLiteBuildValidationValidatorCLIOptions.usage)
        exit(EXIT_SUCCESS)
    }
    let result = try SQLiteBuildValidationValidatorCLIRunner.run(options: options)
    if result.exitCode != 0 {
        // The canonical report is the artifact of record; this is only a
        // human-readable forwarding of its own diagnostics to stderr so a
        // failing build surfaces something actionable without requiring the
        // caller to open the report file.
        writeStandardError(
            "swiftql-build-validate: overall verdict \(result.report.overallVerdict.rawValue)"
        )
        for diagnostic in result.report.diagnostics {
            writeStandardError(
                "  [\(diagnostic.verdict.rawValue)] \(diagnostic.stage.rawValue).\(diagnostic.code): \(diagnostic.message)"
            )
        }
        for outcome in result.report.outcomes where outcome.verdict != .passed {
            for diagnostic in outcome.diagnostics {
                writeStandardError(
                    "  \(outcome.queryID): [\(diagnostic.verdict.rawValue)] \(diagnostic.stage.rawValue).\(diagnostic.code): \(diagnostic.message)"
                )
            }
        }
    }
    exit(result.exitCode)
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(SQLiteBuildValidationValidatorCLIOptions.usage)
    exit(2)
}
