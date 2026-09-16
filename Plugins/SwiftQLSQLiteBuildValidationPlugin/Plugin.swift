import Foundation
import PackagePlugin


/// A thin build-tool plugin wrapping the standalone SQLite static-query
/// validator (#293) around the #292 manifest.
///
/// This plugin owns no validation logic of its own: it declares the
/// manifest and snapshot as explicit build-command inputs, declares the
/// canonical report as an explicit output, and invokes the already-built
/// `swiftql-build-validate` executable. The build system's own incremental
/// planner decides whether to re-run the command from those declared
/// inputs/outputs — the plugin never hides discoverable inputs behind a
/// prebuild command.
///
/// ## Opting in
///
/// A SwiftPM target opts in by listing this plugin in its `plugins: [...]`
/// array and placing exactly two files directly in the target's own
/// directory:
///
/// - `swiftql-build-validation-manifest.json` — a #292
///   ``SQLiteBuildValidationManifest`` in canonical JSON form.
/// - `swiftql-build-validation-snapshot.sqlite` — the checked-in SQLite
///   snapshot the manifest's `schema_snapshot` field describes.
///
/// If a target lists the plugin but is missing either file, the build fails
/// with a clear plugin error rather than silently skipping validation.
///
/// ## Opting in from an Xcode project target
///
/// An Xcode project target, such as an application, has no package target
/// directory. It opts in by adding the plugin under its "Run Build Tool
/// Plug-ins" build phase and making the same files members of the target, in
/// one folder: the plugin looks for them by file name among the target's
/// input files (#666). The manifest's folder stands in for the target
/// directory, so the snapshot and the plan-analysis opt-in are only found
/// beside it. Everything else — the file names, the arguments, the declared
/// inputs and outputs — is the same command the SwiftPM path returns, built by
/// the same function.
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

        let fileManager = FileManager.default
        return [
            try Self.validationCommand(
                targetName: target.name,
                inputDirectory: sourceTarget.directory,
                inputLocation: .targetDirectory,
                fileExists: { fileManager.fileExists(atPath: $0.string) },
                pluginWorkDirectory: context.pluginWorkDirectory,
                validatorTool: { try context.tool(named: Self.validatorToolName).path }
            ),
        ]
    }

    /// The one build command both build systems run. The SwiftPM and Xcode
    /// entry points differ only in where `inputDirectory` comes from and how
    /// a file's presence is decided; the file names, arguments, and declared
    /// inputs and outputs are decided here, once.
    static func validationCommand(
        targetName: String,
        inputDirectory: Path,
        inputLocation: SwiftQLSQLiteBuildValidationPluginError.InputLocation,
        fileExists: (Path) -> Bool,
        pluginWorkDirectory: Path,
        validatorTool: () throws -> Path
    ) throws -> Command {
        let manifestPath = inputDirectory.appending(manifestFileName)
        let snapshotPath = inputDirectory.appending(snapshotFileName)
        let hasManifest = fileExists(manifestPath)
        let hasSnapshot = fileExists(snapshotPath)
        guard hasManifest, hasSnapshot else {
            throw SwiftQLSQLiteBuildValidationPluginError.missingInputFiles(
                target: targetName,
                missingManifest: !hasManifest,
                missingSnapshot: !hasSnapshot,
                location: inputLocation
            )
        }

        let validatorToolPath = try validatorTool()
        // Namespaced by target name: without this, every target adopting
        // the plugin would share one report path, causing write races and
        // letting the build system consider a target's command "up to date"
        // based on another target's output.
        let targetWorkDirectory = pluginWorkDirectory.appending(targetName)
        let reportPath = targetWorkDirectory.appending(reportFileName)

        var arguments = [
            "--database", snapshotPath.string,
            "--manifest", manifestPath.string,
            "--output", reportPath.string,
        ]
        var inputFiles = [manifestPath, snapshotPath]
        var outputFiles = [reportPath]

        let planAnalysisPath = inputDirectory.appending(planAnalysisFileName)
        if fileExists(planAnalysisPath) {
            let planReportPath = targetWorkDirectory.appending(planReportFileName)
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

        return .buildCommand(
            displayName: "SwiftQL SQLite build validation (\(targetName))",
            executable: validatorToolPath,
            arguments: arguments,
            inputFiles: inputFiles,
            outputFiles: outputFiles
        )
    }
}


#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftQLSQLiteBuildValidationPlugin: XcodeBuildToolPlugin {
    /// The Xcode project entry point (#666). An Xcode target has no target
    /// directory, so the folder holding the manifest among the target's input
    /// files takes that role, and a file counts as present only when it is an
    /// input file of the target in that folder. The command itself comes from
    /// `validationCommand`, exactly as it does for a SwiftPM target.
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        let inputPaths = target.inputFiles.map(\.path)
        let inputPathSet = Set(inputPaths)

        // A second copy of any opt-in file would make the choice of folder a
        // guess, so the build fails and names every copy instead.
        var inputDirectory: Path?
        for fileName in [Self.manifestFileName, Self.snapshotFileName, Self.planAnalysisFileName] {
            let matches = inputPaths.filter { $0.lastComponent == fileName }
            if matches.count > 1 {
                throw SwiftQLSQLiteBuildValidationPluginError.duplicateInputFiles(
                    target: target.displayName,
                    fileName: fileName,
                    paths: matches.map(\.string)
                )
            }
            // The manifest decides the folder. The snapshot only does when the
            // manifest is absent, so the error can still name what is missing.
            if inputDirectory == nil, fileName != Self.planAnalysisFileName, let match = matches.first {
                inputDirectory = match.removingLastComponent()
            }
        }

        guard let inputDirectory = inputDirectory else {
            throw SwiftQLSQLiteBuildValidationPluginError.missingInputFiles(
                target: target.displayName,
                missingManifest: true,
                missingSnapshot: true,
                location: .xcodeTargetInputFiles
            )
        }

        return [
            try Self.validationCommand(
                targetName: target.displayName,
                inputDirectory: inputDirectory,
                inputLocation: .xcodeTargetInputFiles,
                fileExists: { inputPathSet.contains($0) },
                pluginWorkDirectory: context.pluginWorkDirectory,
                validatorTool: { try context.tool(named: Self.validatorToolName).path }
            ),
        ]
    }
}
#endif


enum SwiftQLSQLiteBuildValidationPluginError: Error, CustomStringConvertible, LocalizedError {
    /// Where a target's opt-in files are looked for, which the missing-file
    /// message names so it says what to fix under each build system.
    enum InputLocation {
        /// A SwiftPM source module target's own directory.
        case targetDirectory
        /// An Xcode project target's input files, in the manifest's folder.
        case xcodeTargetInputFiles
    }

    case unsupportedTargetKind(String)
    case missingInputFiles(target: String, missingManifest: Bool, missingSnapshot: Bool, location: InputLocation)
    case duplicateInputFiles(target: String, fileName: String, paths: [String])

    var description: String {
        switch self {
        case .unsupportedTargetKind(let name):
            return "SwiftQLSQLiteBuildValidationPlugin only supports source module targets; '\(name)' is not one."
        case .missingInputFiles(let target, let missingManifest, let missingSnapshot, let location):
            var missing: [String] = []
            if missingManifest {
                missing.append(SwiftQLSQLiteBuildValidationPlugin.manifestFileName)
            }
            if missingSnapshot {
                missing.append(SwiftQLSQLiteBuildValidationPlugin.snapshotFileName)
            }
            let place: String
            switch location {
            case .targetDirectory:
                place = "in its target directory"
            case .xcodeTargetInputFiles:
                place = "among its input files; add both files to the target, in the same folder"
            }
            return "Target '\(target)' opts into SwiftQLSQLiteBuildValidationPlugin but is missing \(missing.joined(separator: " and ")) \(place)."
        case .duplicateInputFiles(let target, let fileName, let paths):
            return "Target '\(target)' opts into SwiftQLSQLiteBuildValidationPlugin but has more than one \(fileName) among its input files: \(paths.joined(separator: ", ")). Keep exactly one, beside the manifest."
        }
    }

    // SwiftPM surfaces plugin failures via `error.localizedDescription`, which
    // ignores `CustomStringConvertible` and falls back to a generic message
    // unless `LocalizedError.errorDescription` is also provided.
    var errorDescription: String? { description }
}
