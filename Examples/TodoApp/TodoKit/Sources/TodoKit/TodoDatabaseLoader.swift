import Foundation

/// Opens the demo's database off the main actor.
///
/// SwiftQL's request methods are synchronous, and opening the database
/// creates the schema and may seed it, so this runs on an actor of its own
/// rather than wherever the caller happens to be.
public enum TodoDatabaseLoader {

    public static func applicationDatabase() async throws -> TodoDatabase {
        try await loader.open()
    }
}

private let loader = Loader()

private actor Loader {

    func open() throws -> TodoDatabase {
        try Task.checkCancellation()
        return try TodoDatabase.applicationDatabase()
    }
}
