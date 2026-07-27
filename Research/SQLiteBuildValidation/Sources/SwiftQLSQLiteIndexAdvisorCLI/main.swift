import Foundation
import SwiftQLSQLiteEQPVariancePrototype
import SwiftQLSQLitePlanShapePrototype
import SwiftQLSQLiteIndexAdvisorPrototype

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


private let usage = """
    Usage:
      SwiftQLSQLiteIndexAdvisorCLI generate --capture <path> --output <path>
      SwiftQLSQLiteIndexAdvisorCLI verify --candidates <path> --output <path>

    generate reads an EQPCaptureRun (from SwiftQLSQLiteEQPVarianceCLI capture
    or capture_eqp.py), classifies it, derives remediable index candidates,
    and writes the deduplicated candidates as canonical JSON.

    verify creates each candidate on its own scratch copy of the pinned
    Northwind snapshot, re-plans, applies the improvement rule, and writes
    the before/after/verdict evidence as canonical JSON.
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
    case "generate":
        guard let capturePath = flagValue("--capture", in: arguments),
              let outputPath = flagValue("--output", in: arguments) else {
            writeStandardError(usage)
            exit(2)
        }
        let run = try JSONDecoder().decode(
            EQPCaptureRun.self,
            from: Data(contentsOf: URL(fileURLWithPath: capturePath))
        )
        let corpus = try EQPVarianceCorpus.assemble()
        let corpusByID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })

        var remediables: [RemediableCandidate] = []
        for capture in run.statements {
            guard let statement = corpusByID[capture.statementID] else {
                continue
            }
            let plan = EQPPlanShapeClassifier.classify(rows: capture.rows, statementID: statement.id)
            remediables.append(contentsOf: IndexCandidateGenerator.remediableCandidates(for: statement, plan: plan))
        }
        let candidates = IndexCandidateGenerator.deduplicate(remediables)
        let data = try EQPVarianceCanonicalJSON.encode(candidates.map(CodableIndexCandidate.init))
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("Derived \(candidates.count) deduplicated candidate(s) from \(remediables.count) remediable statement(s)")

    case "verify":
        guard let candidatesPath = flagValue("--candidates", in: arguments),
              let outputPath = flagValue("--output", in: arguments) else {
            writeStandardError(usage)
            exit(2)
        }
        let candidates = try JSONDecoder().decode(
            [CodableIndexCandidate].self,
            from: Data(contentsOf: URL(fileURLWithPath: candidatesPath))
        )
        let corpus = try EQPVarianceCorpus.assemble()
        let corpusByID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })

        var evidence: [IndexCandidateEvidence] = []
        for candidate in candidates {
            guard let statement = corpusByID[candidate.representativeStatementID] else {
                writeStandardError("Skipping \(candidate.table)\(candidate.columns): representative statement not found")
                continue
            }
            let result = try IndexCandidateVerifier.verify(candidate: candidate.asIndexCandidate, statement: statement)
            evidence.append(result)
            print("\(candidate.table)\(candidate.columns) -> improvement: \(result.isImprovement) (\(result.improvementReason))")
        }
        let data = try EQPVarianceCanonicalJSON.encode(evidence)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

    default:
        writeStandardError(usage)
        exit(2)
    }
} catch {
    writeStandardError(String(describing: error))
    writeStandardError(usage)
    exit(2)
}


/// `IndexCandidate` is intentionally not `Codable` in the prototype library
/// (it's a plain in-memory value the generator and verifier pass directly);
/// this CLI-only wrapper adds the JSON round-trip the `generate`/`verify`
/// subcommand pipeline needs.
private struct CodableIndexCandidate: Codable {
    let table: String
    let columns: [String]
    let sourceStatementIDs: [String]
    let representativeStatementID: String
    let representativeAlias: String

    init(_ candidate: IndexCandidate) {
        table = candidate.table
        columns = candidate.columns
        sourceStatementIDs = candidate.sourceStatementIDs
        representativeStatementID = candidate.representativeStatementID
        representativeAlias = candidate.representativeAlias
    }

    private enum CodingKeys: String, CodingKey {
        case table
        case columns
        case sourceStatementIDs = "source_statement_ids"
        case representativeStatementID = "representative_statement_id"
        case representativeAlias = "representative_alias"
    }

    var asIndexCandidate: IndexCandidate {
        IndexCandidate(
            table: table,
            columns: columns,
            sourceStatementIDs: sourceStatementIDs,
            representativeStatementID: representativeStatementID,
            representativeAlias: representativeAlias
        )
    }
}
