import Foundation

//
//  Custody of the checked-in SQLite snapshot a validation run reads.
//
//  Split out of SQLiteBuildValidator.swift (#566). These are the only pieces
//  that touch the filesystem, and they are what makes a report evidence rather
//  than an assertion: the snapshot is proven immutable before the run and
//  unchanged after it.
//

extension SQLiteBuildValidator {

    /// Refuses a snapshot with an adjacent SQLite sidecar.
    ///
    /// A `-journal`, `-shm`, or `-wal` file beside the database is evidence
    /// that something has it open for writing, which an immutable checked-in
    /// artifact never is.
    static func requireSidecarFreeSnapshot(at databaseURL: URL) throws {
        for suffix in ["-journal", "-shm", "-wal"] {
            let sidecarPath = databaseURL.path + suffix
            guard !FileManager.default.fileExists(atPath: sidecarPath) else {
                throw SQLiteBuildValidationValidatorError.databaseHasSidecar(
                    sidecarPath
                )
            }
        }
    }
}


public enum SQLiteBuildValidationValidatorError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case databaseIsNotARegularFile(String)
    case databaseHasSidecar(String)
    case databaseChangedDuringValidation(
        initialByteCount: Int,
        initialSHA256: String,
        finalByteCount: Int,
        finalSHA256: String
    )

    public var description: String {
        switch self {
        case .databaseIsNotARegularFile(let path):
            return "Build-validation database is not a regular file: \(path)"
        case .databaseHasSidecar(let path):
            return "Build-validation snapshot has an adjacent SQLite sidecar and is not immutable: \(path)"
        case .databaseChangedDuringValidation(
            let initialByteCount,
            let initialSHA256,
            let finalByteCount,
            let finalSHA256
        ):
            return "Build-validation snapshot changed during validation: initial byte count \(initialByteCount), SHA-256 \(initialSHA256); final byte count \(finalByteCount), SHA-256 \(finalSHA256)."
        }
    }
}
