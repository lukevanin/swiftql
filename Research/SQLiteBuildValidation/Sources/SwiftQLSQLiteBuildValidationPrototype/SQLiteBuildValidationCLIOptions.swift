import Foundation


package struct SQLiteBuildValidationCLIOptions: Equatable, Sendable {
    package let databaseURL: URL?
    package let planURL: URL?
    package let outputURL: URL?
    package let codecIdentifiers: [String]
    package let extensionNames: [String]
    package let capabilityIDs: [String]
    package let showsHelp: Bool

    package static func parse(
        arguments: [String],
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) throws -> Self {
        var databasePath: String?
        var planPath: String?
        var outputPath: String?
        var codecIdentifiers: [String] = []
        var extensionNames: [String] = []
        var capabilityIDs: [String] = []
        var showsHelp = false
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex) else {
                throw SQLiteBuildValidationCLIError.missingValue(option)
            }
            index = valueIndex
            let value = arguments[valueIndex]
            guard !value.isEmpty else {
                throw SQLiteBuildValidationCLIError.missingValue(option)
            }
            return value
        }

        func assignOnce(
            _ current: inout String?,
            option: String
        ) throws {
            guard current == nil else {
                throw SQLiteBuildValidationCLIError.duplicateOption(option)
            }
            current = try value(after: option)
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--database":
                try assignOnce(&databasePath, option: argument)
            case "--plan":
                try assignOnce(&planPath, option: argument)
            case "--output":
                try assignOnce(&outputPath, option: argument)
            case "--codec":
                codecIdentifiers.append(try value(after: argument))
            case "--extension":
                extensionNames.append(try value(after: argument))
            case "--capability":
                capabilityIDs.append(try value(after: argument))
            case "--help", "-h":
                showsHelp = true
            default:
                throw SQLiteBuildValidationCLIError.unknownOption(argument)
            }
            index += 1
        }

        if !showsHelp {
            for (option, value) in [
                ("--database", databasePath),
                ("--plan", planPath),
                ("--output", outputPath),
            ] where value == nil {
                throw SQLiteBuildValidationCLIError.requiredOption(option)
            }
        }

        return Self(
            databaseURL: databasePath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            planURL: planPath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            outputURL: outputPath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            codecIdentifiers: sortedUnique(codecIdentifiers),
            extensionNames: sortedUnique(extensionNames),
            capabilityIDs: sortedUnique(capabilityIDs),
            showsHelp: showsHelp
        )
    }

    package static let usage = """
        Usage: SwiftQLSQLiteBuildValidationPrototypeCLI [options]

          --database <path>      Checked-in SQLite snapshot to open read-only
          --plan <path>          Codable build-validation sidecar plan
          --output <path>        Deterministic JSON report destination
          --codec <identity>     Available codec identity (repeatable)
          --extension <name>     Registered extension name (repeatable)
          --capability <id>      Explicit caller-owned capability (repeatable)
          --help                 Show this help
        """

    package static func preflightOutputSafety(
        databaseURL: URL,
        planURL: URL,
        outputURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let outputIdentityURL = identityURL(
            for: outputURL,
            fileManager: fileManager
        )
        let outputFileIdentity = existingFileIdentity(
            at: outputIdentityURL,
            fileManager: fileManager
        )
        let databasePaths = [
            databaseURL.path,
            identityURL(for: databaseURL, fileManager: fileManager).path,
        ]
        let protectedDatabaseSidecarPaths = Set(databasePaths.flatMap { path in
            ["-journal", "-shm", "-wal"].map { suffix in
                ((path + suffix) as NSString).standardizingPath
            }
        })
        let outputPaths = Set([
            (outputURL.path as NSString).standardizingPath,
            outputIdentityURL.path,
        ])
        if !protectedDatabaseSidecarPaths.isDisjoint(with: outputPaths) {
            throw SQLiteBuildValidationCLIError.outputConflictsWithDatabaseSidecar
        }

        for (option, inputURL) in [
            ("--database", databaseURL),
            ("--plan", planURL),
        ] {
            let inputIdentityURL = identityURL(
                for: inputURL,
                fileManager: fileManager
            )
            if outputIdentityURL.path == inputIdentityURL.path {
                throw SQLiteBuildValidationCLIError.outputConflictsWithInput(option)
            }

            if let outputFileIdentity,
               let inputFileIdentity = existingFileIdentity(
                   at: inputIdentityURL,
                   fileManager: fileManager
               ),
               outputFileIdentity == inputFileIdentity {
                throw SQLiteBuildValidationCLIError.outputConflictsWithInput(option)
            }
        }
    }

    private static func resolvedURL(path: String, currentDirectory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return currentDirectory.appendingPathComponent(path).standardizedFileURL
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private static func identityURL(
        for url: URL,
        fileManager: FileManager
    ) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while existingAncestor.path != "/",
              !fileManager.fileExists(atPath: existingAncestor.path) {
            missingComponents.insert(
                existingAncestor.lastPathComponent,
                at: 0
            )
            existingAncestor.deleteLastPathComponent()
        }
        let resolvedAncestor = existingAncestor.resolvingSymlinksInPath()
        return missingComponents.reduce(resolvedAncestor) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }.standardizedFileURL
    }

    private static func existingFileIdentity(
        at url: URL,
        fileManager: FileManager
    ) -> ExistingFileIdentity? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let device = unsignedInteger(attributes[.systemNumber]),
              let inode = unsignedInteger(attributes[.systemFileNumber]) else {
            return nil
        }
        return ExistingFileIdentity(device: device, inode: inode)
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }

    private struct ExistingFileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }
}


package enum SQLiteBuildValidationCLIError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case missingValue(String)
    case duplicateOption(String)
    case requiredOption(String)
    case unknownOption(String)
    case outputConflictsWithInput(String)
    case outputConflictsWithDatabaseSidecar

    package var description: String {
        switch self {
        case .missingValue(let option):
            return "\(option) requires a nonempty value."
        case .duplicateOption(let option):
            return "\(option) may only be supplied once."
        case .requiredOption(let option):
            return "\(option) is required."
        case .unknownOption(let option):
            return "Unknown option \(option)."
        case .outputConflictsWithInput(let option):
            return "--output must not identify the same file as \(option)."
        case .outputConflictsWithDatabaseSidecar:
            return "--output must not use a SQLite sidecar path adjacent to --database."
        }
    }
}
