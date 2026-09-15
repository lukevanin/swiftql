import Foundation
import PackagePlugin


/// Generates a registry of every declared query in a target (#659).
///
/// A target opts in by listing this plugin in its `plugins: [...]` array. On
/// each build the plugin scans the target's own Swift sources for `@SQLQuery`
/// and `@SQLQueries` declarations and compiles a generated
/// `<Target>DeclaredQueries` enum into the target. Its
/// `queries(for:)` method returns every declared query of the database
/// instances passed to it, so a manifest generator that calls it lists no
/// queries itself, and a query added to the target is in the next manifest.
///
/// The registry is generated into the declaring target, not into the
/// generator, because the members it calls have the declarations' own access
/// level. A declaration that is `private` or `fileprivate`, on a generic
/// type, or outside a type cannot be reached from another file. The plugin
/// reports each one as a build warning instead of leaving it out silently.
///
/// Every Swift source of the target is a declared input, and the registry is
/// a declared output, so SwiftPM reruns the scan only when a source changes.
///
/// The plugin owns the name `<Target>DeclaredQueries` in the target: a type
/// or a source file of that name in the target collides with the generated
/// registry. Write `// swiftql-registry: ignore` directly above a
/// declaration, before its first attribute, to leave it out of the registry
/// without a warning.
///
/// Like `swiftql-build-validate`, the tool's target and product names are
/// both `swiftql-declared-query-registry`, so `context.tool(named:)` resolves
/// it under Xcode as well as SwiftPM (#492).
@main
struct SwiftQLDeclaredQueryRegistryPlugin: BuildToolPlugin {
    static let toolName = "swiftql-declared-query-registry"

    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            throw SwiftQLDeclaredQueryRegistryPluginError.unsupportedTargetKind(target.name)
        }
        let tool = try context.tool(named: Self.toolName)
        let inputs = sourceTarget.sourceFiles(withSuffix: "swift").map(\.path)
        let output = context.pluginWorkDirectory
            .appending(target.name)
            .appending("\(target.name)DeclaredQueries.swift")
        return [
            .buildCommand(
                displayName: "SwiftQL declared query registry (\(target.name))",
                executable: tool.path,
                arguments: ["--target-name", target.name, "--output", output.string]
                    + inputs.map(\.string),
                inputFiles: inputs,
                outputFiles: [output]
            ),
        ]
    }
}


enum SwiftQLDeclaredQueryRegistryPluginError: Error, CustomStringConvertible, LocalizedError {
    case unsupportedTargetKind(String)

    var description: String {
        switch self {
        case .unsupportedTargetKind(let name):
            return "SwiftQLDeclaredQueryRegistryPlugin only supports source module targets; '\(name)' is not one."
        }
    }

    var errorDescription: String? { description }
}
