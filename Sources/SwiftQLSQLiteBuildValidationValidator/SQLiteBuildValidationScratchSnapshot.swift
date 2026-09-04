import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


public enum SQLiteBuildValidationScratchError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case scratchInsideSnapshotDirectory(String)
    case scratchInsideWorkingDirectory(String)
    case snapshotChangedDuringVerification(
        initialByteCount: Int,
        initialSHA256: String,
        finalByteCount: Int,
        finalSHA256: String
    )

    public var description: String {
        switch self {
        case .scratchInsideSnapshotDirectory(let path):
            return "A scratch copy must not be created beside the snapshot it copies (\(path))."
        case .scratchInsideWorkingDirectory(let path):
            return "A scratch copy must not be created inside the source tree (\(path))."
        case .snapshotChangedDuringVerification(
            let initialByteCount,
            let initialSHA256,
            let finalByteCount,
            let finalSHA256
        ):
            return "The pinned snapshot changed during verification: \(initialByteCount) bytes/\(initialSHA256) before, \(finalByteCount) bytes/\(finalSHA256) after."
        }
    }
}


/// A disposable, writable copy of the pinned snapshot, scoped to one closure.
///
/// Index verification has to create indices, and the one place it may never
/// create them is the artifact the build is validated against. This type owns
/// the whole compromise: copy the digest-verified snapshot somewhere
/// disposable, hand the copy out, remove it on every exit path, and prove the
/// original is byte-identical afterwards.
///
/// ## Where the copy lives
///
/// The system temporary directory, never beside the snapshot and never inside
/// the working directory. Both are refused explicitly rather than left to
/// convention: a stray `.sqlite` next to a checked-in snapshot is confusing at
/// best, and one inside a source tree ends up committed.
///
/// ## Removal on interruption
///
/// `defer` covers a normal return and a thrown error. It does not cover a
/// signal, so the copy's paths are also registered with a `SIGINT`/`SIGTERM`
/// handler that `unlink`s them and then re-raises the signal with the default
/// disposition. The handler touches only a preallocated C-string table and
/// calls `unlink`, both async-signal-safe; `FileManager` would not be. A
/// `SIGKILL` cannot be caught by anything, and the copy is left in the system
/// temporary directory the OS reclaims — never in the source tree.
public enum SQLiteBuildValidationScratchSnapshot {

    /// Copies the snapshot at `snapshotURL` to a fresh scratch directory,
    /// runs `body` against the copy, and removes the copy afterwards.
    ///
    /// Fails closed: the snapshot's byte count and SHA-256 are taken before
    /// and after, and a difference is an error rather than a warning.
    public static func withCopy<Result>(
        of snapshotURL: URL,
        in scratchParentDirectory: URL = FileManager.default.temporaryDirectory,
        _ body: (URL) throws -> Result
    ) throws -> Result {
        let snapshotURL = snapshotURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let scratchParentDirectory = scratchParentDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        try requireDisposableLocation(
            scratchParentDirectory,
            snapshotURL: snapshotURL
        )

        let initialData = try Data(contentsOf: snapshotURL, options: .mappedIfSafe)
        let initialSHA256 = SQLiteBuildValidationSHA256.hexDigest(of: initialData)

        let scratchDirectory = scratchParentDirectory
            .appendingPathComponent("swiftql-index-advisor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
        let copyURL = scratchDirectory.appendingPathComponent("snapshot.sqlite")
        // SQLite's own sidecars are registered up front, because they appear
        // only once a connection opens the copy and the signal handler cannot
        // go looking for them.
        let registration = SQLiteBuildValidationScratchRegistry.register(paths: [
            copyURL.path,
            copyURL.path + "-journal",
            copyURL.path + "-wal",
            copyURL.path + "-shm",
        ])
        defer {
            SQLiteBuildValidationScratchRegistry.unregister(registration)
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        try FileManager.default.copyItem(at: snapshotURL, to: copyURL)

        let result = try body(copyURL)

        let finalData = try Data(contentsOf: snapshotURL, options: .mappedIfSafe)
        let finalSHA256 = SQLiteBuildValidationSHA256.hexDigest(of: finalData)
        guard finalData.count == initialData.count, finalSHA256 == initialSHA256 else {
            throw SQLiteBuildValidationScratchError.snapshotChangedDuringVerification(
                initialByteCount: initialData.count,
                initialSHA256: initialSHA256,
                finalByteCount: finalData.count,
                finalSHA256: finalSHA256
            )
        }
        return result
    }

    private static func requireDisposableLocation(
        _ scratchParentDirectory: URL,
        snapshotURL: URL
    ) throws {
        let snapshotDirectory = snapshotURL.deletingLastPathComponent()
        guard !isDescendant(scratchParentDirectory, of: snapshotDirectory) else {
            throw SQLiteBuildValidationScratchError.scratchInsideSnapshotDirectory(
                scratchParentDirectory.path
            )
        }
        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        guard !isDescendant(scratchParentDirectory, of: workingDirectory) else {
            throw SQLiteBuildValidationScratchError.scratchInsideWorkingDirectory(
                scratchParentDirectory.path
            )
        }
    }

    /// Path-component containment, so `/a/bc` is not read as living inside
    /// `/a/b`.
    private static func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
        let candidate = url.pathComponents
        let ancestor = ancestor.pathComponents
        guard candidate.count >= ancestor.count else {
            return false
        }
        return Array(candidate.prefix(ancestor.count)) == ancestor
    }
}


/// The signal-time record of which scratch paths exist.
///
/// Deliberately a fixed table of preallocated C strings rather than a Swift
/// collection: the only code that reads it runs inside a signal handler,
/// where allocating, locking, or touching Foundation is not allowed.
///
/// `@unchecked Sendable` because every mutation is behind ``lock``, and the
/// one reader that does not take the lock is the signal handler, which must
/// not.
final class SQLiteBuildValidationScratchRegistry: @unchecked Sendable {
    /// A handful of concurrent verification runs is already more than this
    /// validator does; four paths each leaves plenty of room.
    static let capacity = 64

    static let shared = SQLiteBuildValidationScratchRegistry()

    /// Read by the signal handler, so it is a plain preallocated table with a
    /// process lifetime rather than anything that can move or be freed.
    ///
    /// Wrapped rather than stored as a bare pointer because a raw pointer is
    /// not `Sendable`, and a global one is a strict-concurrency error. The
    /// wrapper is `@unchecked` for the reason the enclosing type is: writes
    /// are behind the lock, and the signal handler must not take one.
    struct PathTable: @unchecked Sendable {
        let base: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    }

    static let paths = PathTable(
        base: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
            .allocate(capacity: capacity)
    )

    struct Registration {
        let slots: [Int]
    }

    private let lock = NSLock()
    private var isPrepared = false

    static func register(paths newPaths: [String]) -> Registration {
        shared.register(paths: newPaths)
    }

    static func unregister(_ registration: Registration) {
        shared.unregister(registration)
    }

    func register(paths newPaths: [String]) -> Registration {
        lock.lock()
        defer { lock.unlock() }
        prepareLocked()

        let table = Self.paths.base
        var slots: [Int] = []
        for path in newPaths {
            guard let slot = (0..<Self.capacity).first(where: { table[$0] == nil }) else {
                // Out of slots: the copy is still removed by `defer` on every
                // ordinary exit path. Only the signal-time cleanup is lost,
                // and dropping a path here is better than failing a run over
                // bookkeeping.
                continue
            }
            table[slot] = strdup(path)
            slots.append(slot)
        }
        return Registration(slots: slots)
    }

    func unregister(_ registration: Registration) {
        lock.lock()
        defer { lock.unlock() }
        let table = Self.paths.base
        for slot in registration.slots {
            free(table[slot])
            table[slot] = nil
        }
    }

    private func prepareLocked() {
        guard !isPrepared else {
            return
        }
        isPrepared = true
        Self.paths.base.initialize(repeating: nil, count: Self.capacity)
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, { received in
                // Async-signal-safe: reads a preallocated table and calls
                // `unlink`. No allocation, no locking, no Foundation.
                let table = SQLiteBuildValidationScratchRegistry.paths.base
                for slot in 0..<SQLiteBuildValidationScratchRegistry.capacity {
                    if let path = table[slot] {
                        unlink(path)
                    }
                }
                // Restore the default disposition and re-raise, so the process
                // still dies the way the sender asked it to.
                signal(received, SIG_DFL)
                raise(received)
            })
        }
    }
}
