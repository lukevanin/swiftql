import Foundation
import SwiftQL

/// The scaffold's stand-in schema.
///
/// It exists so the app has something real to create and read at launch, and
/// so the build-time validation plugin has a schema to validate a query
/// against. The to-do schema replaces it.
@SQLTable
public struct LaunchProbe {

    public var id: String
}

/// Every read the demo performs is a declared query.
///
/// SwiftQL allows one `@SQLQueries` extension per database type, so this is
/// the single place the demo's queries live.
@SQLQueries
extension GRDBDatabase {

    private struct Query {

        func launchProbes() -> [LaunchProbe] {
            sqlResult { schema in
                let probe = schema.table(LaunchProbe.self)
                Select(probe)
                From(probe)
            }
        }
    }
}

/// Owns the demo's SQLite connection and its schema.
public final class TodoDatabase {

    public let database: GRDBDatabase

    public init(url: URL) throws {
        database = try GRDBDatabase(url: url, logger: nil)
        try database.makeRequest(with: sqlCreate(LaunchProbe.self)).execute()
    }

    /// Opens a throwaway database in a fresh temporary directory.
    ///
    /// Not an in-memory database, deliberately: `GRDBDatabase` is backed by
    /// GRDB's `DatabasePool`, which runs in WAL mode and therefore needs a
    /// real file — GRDB offers in-memory databases only through
    /// `DatabaseQueue`, which `GRDBDatabase` has no initializer for. A file
    /// under the temporary directory is the closest equivalent: it needs no
    /// setup, and the system reclaims it.
    ///
    /// The scaffold uses this so the app launches with nothing to configure
    /// on either platform. A durable file in Application Support replaces it.
    public static func temporary() throws -> TodoDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoApp-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        return try TodoDatabase(url: url)
    }

    /// Reads back every probe row, proving the connection, the schema, and
    /// the declared-query path all work.
    public func launchProbeCount() throws -> Int {
        try database.launchProbes().count
    }

    public func insertProbe() throws {
        try database
            .makeRequest(with: sqlInsert(LaunchProbe(id: UUID().uuidString)))
            .execute()
    }
}

/// What the placeholder view shows.
public enum TodoLaunchCheck: Sendable {

    /// Opens a throwaway database, writes one row, and reads it back through
    /// the declared query.
    ///
    /// SwiftQL's request methods are synchronous, so the work runs on an
    /// actor of its own rather than wherever the caller happens to be. A
    /// plain `nonisolated async` function would do the same thing today
    /// under SE-0338, but that is exactly what Swift 6.2's
    /// `NonisolatedNonsendingByDefault` reverses, and a demo should not
    /// depend on which side of that flag it is compiled on.
    ///
    /// Awaiting it stays inside the caller's task tree, so a view that
    /// disappears cancels the check — which a detached task would not.
    public static func run() async throws -> Int {
        try await Worker().run()
    }
}

/// Holds the launch check's database work off the caller's executor.
private actor Worker {

    func run() throws -> Int {
        try Task.checkCancellation()
        let database = try TodoDatabase.temporary()
        try database.insertProbe()
        return try database.launchProbeCount()
    }
}
