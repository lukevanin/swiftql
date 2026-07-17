import Foundation

public struct BenchmarkCLIOptions: Equatable {
    public let configuration: BenchmarkConfiguration
    public let outputURL: URL
    public let showsHelp: Bool

    public static func parse(
        arguments: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> BenchmarkCLIOptions {
        var warmups = BenchmarkConfiguration.standard.warmupCount
        var samples = BenchmarkConfiguration.standard.sampleCount
        var outputPath = ".build/benchmarks/swiftql-benchmark.json"
        var showsHelp = false
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex) else {
                throw BenchmarkError.invalidArguments("\(option) requires a value")
            }
            index = valueIndex
            return arguments[valueIndex]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--warmups":
                warmups = try integer(value(after: argument), option: argument)
            case "--samples":
                samples = try integer(value(after: argument), option: argument)
            case "--output":
                outputPath = try value(after: argument)
            case "--help", "-h":
                showsHelp = true
            default:
                throw BenchmarkError.invalidArguments("unknown option \(argument)")
            }
            index += 1
        }

        let configuration = BenchmarkConfiguration(
            warmupCount: warmups,
            sampleCount: samples
        )
        try configuration.validate()

        let outputURL: URL
        if outputPath.hasPrefix("/") {
            outputURL = URL(fileURLWithPath: outputPath)
        }
        else {
            outputURL = currentDirectory.appendingPathComponent(outputPath)
        }

        return BenchmarkCLIOptions(
            configuration: configuration,
            outputURL: outputURL.standardizedFileURL,
            showsHelp: showsHelp
        )
    }

    public static let usage = """
        Usage: swiftql-benchmark [options]

          --warmups <count>    Untimed warmup operations (default: 50)
          --samples <count>    Recorded operations (default: 500)
          --output <path>      JSON report path (default: .build/benchmarks/swiftql-benchmark.json)
          --help               Show this help
        """

    private static func integer(_ value: String, option: String) throws -> Int {
        guard let result = Int(value) else {
            throw BenchmarkError.invalidArguments("\(option) expects an integer")
        }
        return result
    }
}
