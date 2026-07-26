import Foundation
import SwiftQLSQLiteBuildValidationValidator


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
    exit(result.exitCode)
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(SQLiteBuildValidationValidatorCLIOptions.usage)
    exit(2)
}
