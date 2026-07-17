import Foundation

enum BenchmarkEnvironmentCollector {
    static func collect(packageRoot: URL) -> BenchmarkEnvironment {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let grdb = resolvedGRDB(packageRoot: packageRoot)
        return BenchmarkEnvironment(
            swiftVersion: command(["swift", "--version"]),
            xcodeVersion: command(["xcodebuild", "-version"]),
            sdkVersion: command(["--show-sdk-version"]),
            grdbVersion: grdb.version,
            grdbRevision: grdb.revision,
            repositoryRevision: commandAtPath(
                "/usr/bin/git",
                arguments: ["rev-parse", "HEAD"],
                currentDirectory: packageRoot
            ),
            repositoryState: repositoryState(packageRoot: packageRoot),
            operatingSystem: processInfo.operatingSystemVersionString,
            architecture: commandAtPath("/usr/bin/uname", arguments: ["-m"]),
            machineModel: commandAtPath("/usr/sbin/sysctl", arguments: ["-n", "hw.model"]),
            processor: processorDescription(),
            processorCount: processInfo.processorCount,
            activeProcessorCount: processInfo.activeProcessorCount,
            physicalMemoryBytes: processInfo.physicalMemory,
            runnerImageOS: environment["ImageOS"],
            runnerImageVersion: environment["ImageVersion"]
        )
    }

    private static func command(_ arguments: [String]) -> String {
        commandAtPath("/usr/bin/xcrun", arguments: arguments)
    }

    private static func processorDescription() -> String {
        let brand = commandAtPath(
            "/usr/sbin/sysctl",
            arguments: ["-n", "machdep.cpu.brand_string"]
        )
        return brand == "unavailable" ? commandAtPath(
            "/usr/sbin/sysctl",
            arguments: ["-n", "hw.model"]
        ) : brand
    }

    private static func commandAtPath(
        _ path: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        allowEmptyOutput: Bool = false
    ) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return "unavailable"
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0, let output else {
                return "unavailable"
            }
            if output.isEmpty && !allowEmptyOutput {
                return "unavailable"
            }
            return output
        }
        catch {
            return "unavailable"
        }
    }

    private static func repositoryState(packageRoot: URL) -> String {
        let status = commandAtPath(
            "/usr/bin/git",
            arguments: ["status", "--porcelain"],
            currentDirectory: packageRoot,
            allowEmptyOutput: true
        )
        if status == "unavailable" {
            return status
        }
        return status.isEmpty ? "clean" : "dirty"
    }

    private static func resolvedGRDB(packageRoot: URL) -> (version: String, revision: String) {
        let resolvedURL = packageRoot.appendingPathComponent("Package.resolved")
        guard let data = try? Data(contentsOf: resolvedURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let pins = root["pins"] as? [[String: Any]] else {
            return ("unavailable", "unavailable")
        }

        for pin in pins {
            guard let identity = pin["identity"] as? String,
                  identity.lowercased() == "grdb.swift",
                  let state = pin["state"] as? [String: Any] else {
                continue
            }
            if let version = state["version"] as? String {
                return (version, state["revision"] as? String ?? "unavailable")
            }
            if let revision = state["revision"] as? String {
                return ("unversioned", revision)
            }
        }
        return ("unavailable", "unavailable")
    }
}
