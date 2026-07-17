import Darwin
import Foundation
import SwiftQLBenchmarks

do {
    let options = try BenchmarkCLIOptions.parse(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
    if options.showsHelp {
        print(BenchmarkCLIOptions.usage)
        exit(EXIT_SUCCESS)
    }

    let packageRoot = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    let report = try SwiftQLBenchmarkRunner().run(
        configuration: options.configuration,
        packageRoot: packageRoot
    )
    let data = try report.encodedJSON()
    try FileManager.default.createDirectory(
        at: options.outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: options.outputURL, options: .atomic)

    print(report.humanReadableSummary())
    print("")
    print(
        "SWIFTQL_BENCHMARK_REPORT cases=\(report.cases.count) phases=\(report.cases.reduce(0) { $0 + $1.phases.count }) measured=\(report.measurementCount) samples=\(report.configuration.sampleCount) output=\(options.outputURL.path)"
    )
}
catch {
    let message = "error: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
