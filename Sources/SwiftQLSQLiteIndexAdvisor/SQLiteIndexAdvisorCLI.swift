import Foundation
import SwiftQLSQLiteBuildValidationValidator


public enum SQLiteIndexAdvisorError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case missingValue(String)
    case duplicateOption(String)
    case requiredOption(String)
    case unknownOption(String)
    case applyRequiresOutput
    case noVerificationInSidecar
    case unreadableSidecar(path: String, reason: String)

    public var description: String {
        switch self {
        case .missingValue(let option):
            return "\(option) requires a nonempty value."
        case .duplicateOption(let option):
            return "\(option) may only be supplied once."
        case .requiredOption(let option):
            return "\(option) is required."
        case .unknownOption(let option):
            return "Unknown option \(option)."
        case .applyRequiresOutput:
            return "--apply requires --output, so this command only ever writes to a path the invocation names."
        case .noVerificationInSidecar:
            return "The plan sidecar carries no verification results, so there is nothing verified to apply. Re-run swiftql-build-validate with --verify-index-candidates."
        case .unreadableSidecar(let path, let reason):
            return "Could not read the plan sidecar at \(path): \(reason)"
        }
    }
}


/// `swiftql-index-advisor`'s parsed invocation.
///
/// Report is the default and changes nothing. Applying is a separate,
/// explicit flag, and it additionally requires an output path — so the
/// command can only ever write to somewhere the invocation named.
public struct SQLiteIndexAdvisorOptions: Equatable, @unchecked Sendable {
    public let planReportURL: URL?
    public let outputURL: URL?
    public let applies: Bool
    public let showsHelp: Bool

    public init(
        planReportURL: URL?,
        outputURL: URL? = nil,
        applies: Bool = false,
        showsHelp: Bool = false
    ) {
        self.planReportURL = planReportURL
        self.outputURL = outputURL
        self.applies = applies
        self.showsHelp = showsHelp
    }

    public static func parse(
        arguments: [String],
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) throws -> Self {
        var planReportPath: String?
        var outputPath: String?
        var applies = false
        var showsHelp = false
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex) else {
                throw SQLiteIndexAdvisorError.missingValue(option)
            }
            index = valueIndex
            let value = arguments[valueIndex]
            guard !value.isEmpty else {
                throw SQLiteIndexAdvisorError.missingValue(option)
            }
            return value
        }

        func assignOnce(_ current: inout String?, option: String) throws {
            guard current == nil else {
                throw SQLiteIndexAdvisorError.duplicateOption(option)
            }
            current = try value(after: option)
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--plan-report":
                try assignOnce(&planReportPath, option: argument)
            case "--output":
                try assignOnce(&outputPath, option: argument)
            case "--apply":
                applies = true
            case "--help", "-h":
                showsHelp = true
            default:
                throw SQLiteIndexAdvisorError.unknownOption(argument)
            }
            index += 1
        }

        if !showsHelp {
            guard planReportPath != nil else {
                throw SQLiteIndexAdvisorError.requiredOption("--plan-report")
            }
            if applies, outputPath == nil {
                throw SQLiteIndexAdvisorError.applyRequiresOutput
            }
        }

        func resolved(_ path: String) -> URL {
            path.hasPrefix("/")
                ? URL(fileURLWithPath: path).standardizedFileURL
                : currentDirectory.appendingPathComponent(path).standardizedFileURL
        }

        return Self(
            planReportURL: planReportPath.map(resolved),
            outputURL: outputPath.map(resolved),
            applies: applies,
            showsHelp: showsHelp
        )
    }

    public static let usage = """
        Usage: swiftql-index-advisor --plan-report <path> [options]

          --plan-report <path>   Plan sidecar written by swiftql-build-validate
                                 with --plan-output --verify-index-candidates
          --output <path>        Where to write the generated SQL artifact
          --apply                Write the artifact. Without this the command
                                 only reports, and changes nothing.
          --help, -h             Show this help

        Report mode is the default and never writes anything. Applying is one
        explicit invocation whose diff you review; a build never rewrites
        source on your behalf.
        """
}


public struct SQLiteIndexAdvisorRunResult: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case reported
        case written
        /// Apply ran, and the artifact already said exactly this.
        case unchanged
        /// Verification ran and accepted nothing. There is nothing to apply,
        /// which is an answer rather than a failure.
        case nothingToApply
    }

    public let outcome: Outcome
    public let standardOutput: String

    public var exitCode: Int32 { 0 }
}


/// Reads a plan sidecar and either reports its verified recommendations or
/// writes them as a generated SQL artifact.
///
/// Consumes the artifact only. No plan analysis, candidate generation, or
/// verification happens here — this command cannot decide that an index is a
/// good idea, only relay a decision the validator already recorded with its
/// evidence.
public enum SQLiteIndexAdvisorRunner {

    public static func run(options: SQLiteIndexAdvisorOptions) throws -> SQLiteIndexAdvisorRunResult {
        guard let planReportURL = options.planReportURL else {
            throw SQLiteIndexAdvisorError.requiredOption("--plan-report")
        }
        let planReport: SQLiteBuildValidationPlanReport
        do {
            planReport = try SQLiteBuildValidationPlanReport.decode(
                contentsOf: planReportURL
            )
        } catch let error as CustomStringConvertible & Error {
            throw SQLiteIndexAdvisorError.unreadableSidecar(
                path: planReportURL.path,
                reason: error.description
            )
        } catch {
            throw SQLiteIndexAdvisorError.unreadableSidecar(
                path: planReportURL.path,
                reason: "an error of type \(type(of: error))"
            )
        }

        // Absent verification and empty verification are different answers.
        // Only a sidecar that never ran verification is a refusal: nothing in
        // it has been tried, so nothing in it may be applied.
        guard let recommendations = planReport.indexRecommendations else {
            throw SQLiteIndexAdvisorError.noVerificationInSidecar
        }

        guard options.applies else {
            return SQLiteIndexAdvisorRunResult(
                outcome: .reported,
                standardOutput: report(recommendations)
            )
        }
        guard let outputURL = options.outputURL else {
            throw SQLiteIndexAdvisorError.applyRequiresOutput
        }
        guard !recommendations.recommendations.isEmpty else {
            return SQLiteIndexAdvisorRunResult(
                outcome: .nothingToApply,
                standardOutput: "swiftql-index-advisor: verification accepted no candidates, so there is nothing to apply. \(outputURL.path) was not written.\n"
            )
        }

        let sql = SQLiteIndexAdvisorArtifact.sql(
            for: recommendations,
            sourceDescription: planReportURL.lastPathComponent
        )
        let data = Data(sql.utf8)
        // Idempotence is checked by comparing bytes rather than by trusting
        // the renderer: re-running on unchanged advice must not touch the
        // file's mtime either, or every rebuild downstream of it churns.
        if let existing = try? Data(contentsOf: outputURL), existing == data {
            return SQLiteIndexAdvisorRunResult(
                outcome: .unchanged,
                standardOutput: "swiftql-index-advisor: \(outputURL.path) is already up to date.\n"
            )
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        return SQLiteIndexAdvisorRunResult(
            outcome: .written,
            standardOutput: "swiftql-index-advisor: wrote \(recommendations.recommendations.count) verified index statement(s) to \(outputURL.path).\n"
        )
    }

    /// Report mode's output: every recommendation with its evidence, and every
    /// candidate verification rejected, with the reason.
    static func report(
        _ recommendations: SQLiteBuildValidationIndexRecommendationSet
    ) -> String {
        var lines = [
            "swiftql-index-advisor: \(recommendations.recommendations.count) verified recommendation(s), \(recommendations.unverified.count) unverified candidate(s).",
            "Improvement rule: \(recommendations.improvementRuleVersion)",
        ]
        for (offset, recommendation) in recommendations.recommendations.enumerated() {
            let candidate = recommendation.candidate
            lines.append("")
            lines.append("[\(offset + 1)] \(candidate.table) (\(candidate.columns.map(\.name).joined(separator: ", ")))")
            lines.append("    DDL:       \(candidate.ddl(ifNotExists: true));")
            lines.append("    Motivated: \(candidate.sourceQueryIDs.joined(separator: ", "))")
            lines.append("    Before:    \(SQLiteIndexAdvisorArtifact.planSummary(recommendation.beforePlan))")
            lines.append("    After:     \(SQLiteIndexAdvisorArtifact.planSummary(recommendation.afterPlan))")
            lines.append("    Why:       \(recommendation.improvementReason)")
            lines.append("    Cost:      \(recommendation.writeCostNote)")
        }
        for unverified in recommendations.unverified {
            let candidate = unverified.candidate
            lines.append("")
            lines.append("[unverified] \(candidate.table) (\(candidate.columns.map(\.name).joined(separator: ", ")))")
            lines.append("    Statement: \(unverified.statementID)")
            lines.append("    Reason:    \(unverified.reason)")
        }
        lines.append("")
        lines.append("Report mode changed nothing. Re-run with --apply --output <path> to write the verified statements.")
        return lines.joined(separator: "\n") + "\n"
    }
}
