import Foundation


/// Refuses an output path that names, aliases, or would clobber one of the
/// validator's own inputs.
///
/// A build validator writes exactly one file, and the two files it reads are
/// the evidence its report is about. Writing the report over the snapshot
/// destroys the artifact the build is checking against; writing it over one of
/// SQLite's `-journal`/`-shm`/`-wal` sidecar paths corrupts the database just
/// as thoroughly and less visibly.
///
/// Path spelling alone does not settle whether two paths are the same file, so
/// the checks work from filesystem identity: symlinks are resolved, including
/// symlinked parent directories, and existing files are compared by device and
/// inode, which is the only thing that catches a hard link.
///
/// Split out of `SQLiteBuildValidationValidatorCLIOptions` (#566): this is
/// filesystem work, not argument parsing, and it is worth reading on its own.
enum SQLiteBuildValidationOutputSafetyPreflight {

    /// The errors to raise for one output path, so the same checks can guard
    /// both the correctness report and the plan sidecar while each names the
    /// option the caller actually spelled.
    struct OutputErrors {
        let sidecarConflict: SQLiteBuildValidationValidatorCLIError
        let inputConflict: (String) -> SQLiteBuildValidationValidatorCLIError
    }

    static func check(
        databaseURL: URL,
        manifestURL: URL,
        outputURL: URL,
        planOutputURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        try check(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: outputURL,
            errors: OutputErrors(
                sidecarConflict: .outputConflictsWithDatabaseSidecar,
                inputConflict: SQLiteBuildValidationValidatorCLIError.outputConflictsWithInput
            ),
            fileManager: fileManager
        )
        guard let planOutputURL else {
            return
        }
        try check(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            outputURL: planOutputURL,
            errors: OutputErrors(
                sidecarConflict: .planOutputConflictsWithDatabaseSidecar,
                inputConflict: SQLiteBuildValidationValidatorCLIError.planOutputConflictsWithInput
            ),
            fileManager: fileManager
        )
        // Two artifacts, two files. Writing both to one path leaves whichever
        // was written last, which reads as a complete run that silently lost
        // half its output.
        guard identityURL(for: outputURL, fileManager: fileManager).path
            != identityURL(for: planOutputURL, fileManager: fileManager).path else {
            throw SQLiteBuildValidationValidatorCLIError.planOutputConflictsWithReportOutput
        }
    }

    private static func check(
        databaseURL: URL,
        manifestURL: URL,
        outputURL: URL,
        errors: OutputErrors,
        fileManager: FileManager
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
            throw errors.sidecarConflict
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
                throw errors.inputConflict(option)
            }

            if let outputFileIdentity,
               let inputFileIdentity = existingFileIdentity(
                   at: inputIdentityURL,
                   fileManager: fileManager
               ),
               outputFileIdentity == inputFileIdentity {
                throw errors.inputConflict(option)
            }
        }
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
