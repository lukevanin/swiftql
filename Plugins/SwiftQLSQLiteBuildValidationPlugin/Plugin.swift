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
@main
struct SwiftQLSQLiteBuildValidationPlugin: BuildToolPlugin {
    static let manifestFileName = "swiftql-build-validation-manifest.json"
    static let snapshotFileName = "swiftql-build-validation-snapshot.sqlite"
    static let reportFileName = "swiftql-build-validation-report.json"
    static let validatorToolName = "SwiftQLSQLiteBuildValidationValidatorCLI"

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
        let reportPath = context.pluginWorkDirectory
            .appending(target.name)
            .appending(Self.reportFileName)

        return [
            .buildCommand(
                displayName: "SwiftQL SQLite build validation (\(target.name))",
                executable: validatorTool.path,
                arguments: [
                    "--database", snapshotPath.string,
                    "--manifest", manifestPath.string,
                    "--output", reportPath.string,
                ],
                inputFiles: [manifestPath, snapshotPath],
                outputFiles: [reportPath]
            ),
        ]
    }
}


enum SwiftQLSQLiteBuildValidationPluginError: Error, CustomStringConvertible {
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
}
