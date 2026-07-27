import Foundation
import GRDB
import SwiftQLSQLiteEQPVariancePrototype

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


private let usage = """
    Usage:
      SwiftQLSQLiteEQPVarianceCLI export-corpus --output <path>
      SwiftQLSQLiteEQPVarianceCLI capture --database <path> --label <label> --output <path>
      SwiftQLSQLiteEQPVarianceCLI compare --baseline <path> --comparison <path> --output <path>

    export-corpus writes the #390 statement corpus (combinatorial cases plus
    Northwind semantic anchors) as canonical JSON.

    capture opens <database> read-only/query-only, runs EXPLAIN QUERY PLAN for
    every corpus statement, and writes an EQPCaptureRun as canonical JSON
    tagged with <label> and this process's SQLite runtime provenance.

    compare classifies the per-statement difference between two capture runs
    (from `capture` or the Python capture script) and writes the classified
    comparisons as canonical JSON.
    """


private func writeStandardError(_ message: String) {
    guard let data = "\(message)\n".data(using: .utf8) else {
        return
    }
    FileHandle.standardError.write(data)
}


private func flagValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}


do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let subcommand = arguments.first else {
        writeStandardError(usage)
        exit(2)
    }

    switch subcommand {
    case "export-corpus":
        guard let outputPath = flagValue("--output", in: arguments) else {
            writeStandardError(usage)
            exit(2)
        }
        let corpus = try EQPVarianceCorpus.assemble()
        let data = try EQPVarianceCanonicalJSON.encode(corpus)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("Wrote \(corpus.count) statements to \(outputPath)")

    case "capture":
        guard let databasePath = flagValue("--database", in: arguments),
              let label = flagValue("--label", in: arguments),
              let outputPath = flagValue("--output", in: arguments) else {
            writeStandardError(usage)
            exit(2)
        }
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA query_only = ON")
        }
        let queue = try DatabaseQueue(path: databasePath, configuration: configuration)
        let corpus = try EQPVarianceCorpus.assemble()
        let run = try queue.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: corpus, label: label)
        }
        let data = try EQPVarianceCanonicalJSON.encode(run)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("Captured \(run.statements.count) statements (label: \(label)) to \(outputPath)")

    case "compare":
        guard let baselinePath = flagValue("--baseline", in: arguments),
              let comparisonPath = flagValue("--comparison", in: arguments),
              let outputPath = flagValue("--output", in: arguments) else {
            writeStandardError(usage)
            exit(2)
        }
        let decoder = JSONDecoder()
        let baseline = try decoder.decode(
            EQPCaptureRun.self,
            from: Data(contentsOf: URL(fileURLWithPath: baselinePath))
        )
        let comparison = try decoder.decode(
            EQPCaptureRun.self,
            from: Data(contentsOf: URL(fileURLWithPath: comparisonPath))
        )
        let comparisons = try EQPVarianceClassifier.compare(baseline: baseline, comparison: comparison)
        let data = try EQPVarianceCanonicalJSON.encode(comparisons)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

        var counts: [String: Int] = [:]
        for entry in comparisons {
            counts[entry.classification.rawValue, default: 0] += 1
        }
        for (classification, count) in counts.sorted(by: { $0.key < $1.key }) {
            print("\(classification): \(count)")
        }

    default:
        writeStandardError(usage)
        exit(2)
    }
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(usage)
    exit(2)
}
