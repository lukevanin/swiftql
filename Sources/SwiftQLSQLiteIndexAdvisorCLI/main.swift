import Foundation
import SwiftQLSQLiteIndexAdvisor

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

do {
    let options = try SQLiteIndexAdvisorOptions.parse(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
    if options.showsHelp {
        print(SQLiteIndexAdvisorOptions.usage)
        exit(EXIT_SUCCESS)
    }
    let result = try SQLiteIndexAdvisorRunner.run(options: options)
    FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
    exit(result.exitCode)
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(SQLiteIndexAdvisorOptions.usage)
    exit(2)
}
