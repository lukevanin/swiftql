import Foundation

/// What the placeholder view reports after opening the database.
public struct TodoLaunchSummary: Equatable, Sendable {

    /// `true` when this launch created the file and seeded it.
    public let didSeed: Bool

    public let listCount: Int

    public let todoCount: Int

    public let tagCount: Int
}

/// Opens the durable database and counts what it holds.
public enum TodoLaunchCheck: Sendable {

    /// SwiftQL's request methods are synchronous, so the work runs on an
    /// actor of its own rather than wherever the caller happens to be. A
    /// plain `nonisolated async` function would do the same thing today
    /// under SE-0338, but that is exactly what Swift 6.2's
    /// `NonisolatedNonsendingByDefault` reverses, and a demo should not
    /// depend on which side of that flag it is compiled on.
    ///
    /// Awaiting it stays inside the caller's task tree, so a view that
    /// disappears cancels the check — which a detached task would not.
    public static func run() async throws -> TodoLaunchSummary {
        try await sharedWorker.run()
    }

    #if DEBUG
    /// Throws the database back to its seeded state and reports the result.
    /// Debug builds only.
    public static func resetAndRun() async throws -> TodoLaunchSummary {
        try await sharedWorker.resetAndRun()
    }
    #endif
}

/// One instance, so an open and a reset cannot overlap on the same file.
private let sharedWorker = Worker()

/// Holds the launch check's database work off the caller's executor.
private actor Worker {

    func run() throws -> TodoLaunchSummary {
        try Task.checkCancellation()
        return try summarize(TodoDatabase.applicationDatabase())
    }

    #if DEBUG
    func resetAndRun() throws -> TodoLaunchSummary {
        try Task.checkCancellation()
        let database = try TodoDatabase.applicationDatabase()
        try database.reset()
        return try summarize(database, didSeed: true)
    }
    #endif

    private func summarize(
        _ database: TodoDatabase,
        didSeed: Bool? = nil
    ) throws -> TodoLaunchSummary {
        TodoLaunchSummary(
            didSeed: didSeed ?? database.didSeed,
            listCount: try database.lists().count,
            todoCount: try database.todos().count,
            tagCount: try database.tags().count
        )
    }
}
