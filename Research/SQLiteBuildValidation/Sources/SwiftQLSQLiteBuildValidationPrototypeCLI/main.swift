import Foundation
import SwiftQLSQLiteBuildValidationPrototype

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


private func writeStandardError(_ message: String) {
    guard let data = "\(message)\n".data(using: .utf8) else {
        return
    }
    FileHandle.standardError.write(data)
}


do {
    let options = try SQLiteBuildValidationCLIOptions.parse(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
    if options.showsHelp {
        print(SQLiteBuildValidationCLIOptions.usage)
        exit(EXIT_SUCCESS)
    }

    let result = try SQLiteBuildValidationCLIRunner.run(options: options)
    exit(result.exitCode)
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(SQLiteBuildValidationCLIOptions.usage)
    exit(2)
}
