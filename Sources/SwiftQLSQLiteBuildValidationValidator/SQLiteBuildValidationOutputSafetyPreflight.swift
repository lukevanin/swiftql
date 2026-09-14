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
///
/// `package` rather than `public` (#649): `swiftql-index-advisor` reuses
/// ``identifiesSameFile(_:_:fileManager:)`` so its output cannot alias the
/// sidecar it reads, and that need does not justify a public API promise.
package enum SQLiteBuildValidationOutputSafetyPreflight {

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
        planSuppressionsURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        try check(
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            planSuppressionsURL: planSuppressionsURL,
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
            planSuppressionsURL: planSuppressionsURL,
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
        //
        // Checked the same way the input checks above are: by path, and then
        // by device and inode, because two different paths hard-linked to one
        // file are the same file and only identity catches that.
        if identifiesSameFile(outputURL, planOutputURL, fileManager: fileManager) {
            throw SQLiteBuildValidationValidatorCLIError.planOutputConflictsWithReportOutput
        }
    }

    /// Whether `first` and `second` name one file: the same path once
    /// symlinks (including symlinked parent directories) are resolved, or two
    /// existing paths with one device and inode, which is how a hard link is
    /// caught.
    ///
    /// A path that does not exist yet can only match by path, because it has
    /// no inode to compare.
    package static func identifiesSameFile(
        _ first: URL,
        _ second: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let firstIdentityURL = identityURL(for: first, fileManager: fileManager)
        let secondIdentityURL = identityURL(for: second, fileManager: fileManager)
        if firstIdentityURL.path == secondIdentityURL.path {
            return true
        }
        guard let firstFileIdentity = existingFileIdentity(
                  at: firstIdentityURL,
                  fileManager: fileManager
              ),
              let secondFileIdentity = existingFileIdentity(
                  at: secondIdentityURL,
                  fileManager: fileManager
              ) else {
            return false
        }
        return firstFileIdentity == secondFileIdentity
    }

    private static func check(
        databaseURL: URL,
        manifestURL: URL,
        planSuppressionsURL: URL?,
        outputURL: URL,
        errors: OutputErrors,
        fileManager: FileManager
    ) throws {
        let outputIdentityURL = identityURL(
            for: outputURL,
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

        // The suppression file is a checked-in input like the other two, and
        // `--plan-output` overwriting it would replace reviewed reasons with a
        // generated sidecar (#649).
        var protectedInputs = [
            ("--database", databaseURL),
            ("--manifest", manifestURL),
        ]
        if let planSuppressionsURL {
            protectedInputs.append(("--plan-suppressions", planSuppressionsURL))
        }
        for (option, inputURL) in protectedInputs
        where identifiesSameFile(outputURL, inputURL, fileManager: fileManager) {
            throw errors.inputConflict(option)
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
