import Foundation
import PackagePlugin


/// A thin SwiftPM build-tool plugin wrapping the standalone SQLite
/// static-query validator (#293) around the #292 manifest.
///
/// This plugin owns no validation logic of its own: it declares the
/// manifest and snapshot as explicit build-command inputs, declares the
/// canonical report as an explicit output, and invokes the already-built
/// `swiftql-build-validate` executable. SwiftPM's own incremental build
/// planner decides whether to re-run the command from those declared
/// inputs/outputs — the plugin never hides discoverable inputs behind a
/// prebuild command.
///
/// ## Opting in
///
/// A target opts in by listing this plugin in its `plugins: [...]` array and
/// placing exactly two files directly in the target's own directory:
///
/// - `swiftql-build-validation-manifest.json` — a #292
///   ``SQLiteBuildValidationManifest`` in canonical JSON form.
/// - `swiftql-build-validation-snapshot.sqlite` — the checked-in SQLite
///   snapshot the manifest's `schema_snapshot` field describes.
///
/// If a target lists the plugin but is missing either file, the build fails
/// with a clear plugin error rather than silently skipping validation.
///
/// ## Opting into plan analysis
///
/// Advisory query-plan analysis (#394-#397) is a **separate** opt-in, off by
/// default. A target enables it by adding a third file to its own directory:
///
/// - `swiftql-plan-analysis.json` — a plan-suppression document
///   (`{"format_version": 1, "suppressions": []}` to opt in with no
///   suppressions).
///
/// With that file present, the plugin additionally passes `--plan-output`,
/// `--plan-suppressions`, and `--verify-index-candidates`, and declares the
/// plan sidecar as a second command output. Without it, nothing about the
/// invocation changes and the build pays nothing for plan analysis.
///
/// ## Warnings, not fixits
///
/// Advisory findings reach the build log because the validator prints them in
/// the `<path>: warning: <message>` form every Swift build system already
/// parses, with the verified `CREATE INDEX` DDL in the message. They are not
/// fixits, and cannot be: a SwiftPM build-tool plugin emits diagnostics rather
/// than fixits, and a Swift fixit would require a macro, which cannot open a
/// database without breaking hermetic, incremental builds. Applying the advice
/// is therefore the `swiftql-index-advisor` command's job (#399), not this
/// plugin's.
///
/// ## Build host versus device
///
/// A plan captured on the build host is not a promise about the SQLite an
/// application will run against. #390 measured a materialization strategy
/// changing between two ordinary SQLite point releases. The advice is a guide
/// to look at, not a guarantee.
///
/// This plugin owns none of that reasoning. It passes flags and declares
/// files; every judgement lives in the validator.
///
/// ## Build systems
///
/// Both `swift build` and Xcode's build system run the plugin, and they
/// agree on the outcome: a valid manifest builds, and an invalid one fails
/// with the validator's own diagnostic. Xcode names a package executable
/// after its product while `context.tool(named:)` resolves the tool by
/// target name, so the validator's target and product names are deliberately
/// both `swiftql-build-validate`. Splitting them breaks Xcode builds of every
/// adopting target with "Build input file cannot be found" (#492).
@main
struct SwiftQLSQLiteBuildValidationPlugin: BuildToolPlugin {
    static let manifestFileName = "swiftql-build-validation-manifest.json"
    static let snapshotFileName = "swiftql-build-validation-snapshot.sqlite"
    static let reportFileName = "swiftql-build-validation-report.json"
    /// The plan-analysis opt-in. Its presence is the whole switch.
    static let planAnalysisFileName = "swiftql-plan-analysis.json"
    static let planReportFileName = "swiftql-plan-analysis-report.json"
    // Both the validator executable's target name and its product name; the
    // two must stay identical. See the "Build systems" note above, #492, and
    // the comment on the target in Package.swift.
    static let validatorToolName = "swiftql-build-validate"

    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            throw SwiftQLSQLiteBuildValidationPluginError.unsupportedTargetKind(target.name)
        }

        let manifestPath = sourceTarget.directory.appending(Self.manifestFileName)
        let snapshotPath = sourceTarget.directory.appending(Self.snapshotFileName)
        let fileManager = FileManager.default
        let hasManifest = fileManager.fileExists(atPath: manifestPath.string)
        let hasSnapshot = fileManager.fileExists(atPath: snapshotPath.string)
        guard hasManifest, hasSnapshot else {
            throw SwiftQLSQLiteBuildValidationPluginError.missingInputFiles(
                target: target.name,
                missingManifest: !hasManifest,
                missingSnapshot: !hasSnapshot
            )
        }

        let validatorTool = try context.tool(named: Self.validatorToolName)
        // Namespaced by target name: without this, every target adopting
        // the plugin would share one report path, causing write races and
        // letting SwiftPM consider a target's command "up to date" based on
        // another target's output.
        let targetWorkDirectory = context.pluginWorkDirectory.appending(target.name)
        let reportPath = targetWorkDirectory.appending(Self.reportFileName)

        var arguments = [
            "--database", snapshotPath.string,
            "--manifest", manifestPath.string,
            "--output", reportPath.string,
        ]
        var inputFiles = [manifestPath, snapshotPath]
        var outputFiles = [reportPath]

        let planAnalysisPath = sourceTarget.directory.appending(Self.planAnalysisFileName)
        if fileManager.fileExists(atPath: planAnalysisPath.string) {
            let planReportPath = targetWorkDirectory.appending(Self.planReportFileName)
            arguments += [
                "--plan-output", planReportPath.string,
                "--plan-suppressions", planAnalysisPath.string,
                "--verify-index-candidates",
            ]
            // Declared as an input and an output, not hidden behind a prebuild
            // command: the opt-in file changing must invalidate the command,
            // and the sidecar must participate in incremental build planning
            // like any other product of it.
            inputFiles.append(planAnalysisPath)
            outputFiles.append(planReportPath)
        }

        return [
            .buildCommand(
                displayName: "SwiftQL SQLite build validation (\(target.name))",
                executable: validatorTool.path,
                arguments: arguments,
                inputFiles: inputFiles,
                outputFiles: outputFiles
            ),
        ]
    }
}


enum SwiftQLSQLiteBuildValidationPluginError: Error, CustomStringConvertible, LocalizedError {
    case unsupportedTargetKind(String)
    case missingInputFiles(target: String, missingManifest: Bool, missingSnapshot: Bool)

    var description: String {
        switch self {
        case .unsupportedTargetKind(let name):
            return "SwiftQLSQLiteBuildValidationPlugin only supports source module targets; '\(name)' is not one."
        case .missingInputFiles(let target, let missingManifest, let missingSnapshot):
            var missing: [String] = []
            if missingManifest {
                missing.append(SwiftQLSQLiteBuildValidationPlugin.manifestFileName)
            }
            if missingSnapshot {
                missing.append(SwiftQLSQLiteBuildValidationPlugin.snapshotFileName)
            }
            return "Target '\(target)' opts into SwiftQLSQLiteBuildValidationPlugin but is missing \(missing.joined(separator: " and ")) in its target directory."
        }
    }

    // SwiftPM surfaces plugin failures via `error.localizedDescription`, which
    // ignores `CustomStringConvertible` and falls back to a generic message
    // unless `LocalizedError.errorDescription` is also provided.
    var errorDescription: String? { description }
}
