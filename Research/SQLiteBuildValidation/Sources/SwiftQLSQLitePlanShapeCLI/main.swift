import Foundation
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


private let usage = """
    Usage:
      SwiftQLSQLitePlanShapeCLI classify --capture <path> --output <path>

    Reads an EQPCaptureRun (from SwiftQLSQLiteEQPVarianceCLI capture or
    capture_eqp.py) and writes the normalised, classified plan tree for every
    statement as canonical JSON, plus a shape-count summary on stdout.
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


private func countShapes(_ node: EQPPlanNode, into counts: inout [EQPPlanShapeKind: Int]) {
    counts[node.shape, default: 0] += 1
    for child in node.children {
        countShapes(child, into: &counts)
    }
}


do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.first == "classify",
          let capturePath = flagValue("--capture", in: arguments),
          let outputPath = flagValue("--output", in: arguments) else {
        writeStandardError(usage)
        exit(2)
    }

    let run = try JSONDecoder().decode(
        EQPCaptureRun.self,
        from: Data(contentsOf: URL(fileURLWithPath: capturePath))
    )

    let plans = run.statements.map { statement in
        EQPPlanShapeClassifier.classify(rows: statement.rows, statementID: statement.statementID)
    }

    let data = try EQPVarianceCanonicalJSON.encode(plans)
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

    var counts: [EQPPlanShapeKind: Int] = [:]
    for plan in plans {
        for root in plan.roots {
            countShapes(root, into: &counts)
        }
    }
    for (shape, count) in counts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        print("\(shape.rawValue): \(count)")
    }
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(usage)
    exit(2)
}
