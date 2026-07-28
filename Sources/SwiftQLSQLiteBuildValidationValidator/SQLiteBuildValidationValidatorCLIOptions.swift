import Foundation


// Swift 5.9's Linux Foundation predates URL's Sendable annotation. Options are
// immutable values, and newer Foundation versions declare URL Sendable.
public struct SQLiteBuildValidationValidatorCLIOptions: Equatable, @unchecked Sendable {
    public let databaseURL: URL?
    public let manifestURL: URL?
    public let outputURL: URL?
    public let codecIdentifiers: [String]
    public let extensionNames: [String]
    public let capabilityIDs: [String]
    public let showsHelp: Bool

    public static func parse(
        arguments: [String],
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) throws -> Self {
        var databasePath: String?
        var manifestPath: String?
        var outputPath: String?
        var codecIdentifiers: [String] = []
        var extensionNames: [String] = []
        var capabilityIDs: [String] = []
        var showsHelp = false
        var index = 0

        func value(after option: String) throws -> String {
            let valueIndex = index + 1
            guard arguments.indices.contains(valueIndex) else {
                throw SQLiteBuildValidationValidatorCLIError.missingValue(option)
            }
            index = valueIndex
            let value = arguments[valueIndex]
            guard !value.isEmpty else {
                throw SQLiteBuildValidationValidatorCLIError.missingValue(option)
            }
            return value
        }

        func assignOnce(
            _ current: inout String?,
            option: String
        ) throws {
            guard current == nil else {
                throw SQLiteBuildValidationValidatorCLIError.duplicateOption(option)
            }
            current = try value(after: option)
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--database":
                try assignOnce(&databasePath, option: argument)
            case "--manifest":
                try assignOnce(&manifestPath, option: argument)
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
                throw SQLiteBuildValidationValidatorCLIError.unknownOption(argument)
            }
            index += 1
        }

        if !showsHelp {
            for (option, value) in [
                ("--database", databasePath),
                ("--manifest", manifestPath),
                ("--output", outputPath),
            ] where value == nil {
                throw SQLiteBuildValidationValidatorCLIError.requiredOption(option)
            }
        }

        return Self(
            databaseURL: databasePath.map {
                resolvedURL(path: $0, currentDirectory: currentDirectory)
            },
            manifestURL: manifestPath.map {
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

    public static let usage = """
        Usage: swiftql-build-validate [options]

          --database <path>      Checked-in SQLite snapshot to open read-only
          --manifest <path>      Codable build-validation manifest (#292)
          --output <path>        Deterministic JSON report destination
          --codec <identity>     Available codec identity (repeatable)
          --extension <name>     Registered extension name (repeatable)
          --capability <id>      Explicit caller-owned capability (repeatable)
          --help, -h              Show this help
        """

    public static func preflightOutputSafety(
        databaseURL: URL,
        manifestURL: URL,
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
            throw SQLiteBuildValidationValidatorCLIError.outputConflictsWithDatabaseSidecar
        }

        for (option, inputURL) in [
            ("--database", databaseURL),
            ("--manifest", manifestURL),
        ] {
            let inputIdentityURL = identityURL(
                for: inputURL,
                fileManager: fileManager
            )
            if outputIdentityURL.path == inputIdentityURL.path {
                throw SQLiteBuildValidationValidatorCLIError.outputConflictsWithInput(option)
            }

            if let outputFileIdentity,
               let inputFileIdentity = existingFileIdentity(
                   at: inputIdentityURL,
                   fileManager: fileManager
               ),
               outputFileIdentity == inputFileIdentity {
                throw SQLiteBuildValidationValidatorCLIError.outputConflictsWithInput(option)
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


public enum SQLiteBuildValidationValidatorCLIError:
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
        case .outputConflictsWithInput(let option):
            return "--output must not identify the same file as \(option)."
        case .outputConflictsWithDatabaseSidecar:
            return "--output must not use a SQLite sidecar path adjacent to --database."
        }
    }
}
