import Foundation

import SwiftQL

/// Owns the demo's SQLite file, its schema, and its seed data.
public final class TodoDatabase {

    /// The file name the app opens in Application Support. Stable, so a
    /// relaunch finds the database it wrote last time.
    public static let fileName = "SwiftQLTodoDemo.sqlite"

    public let url: URL

    public let database: GRDBDatabase

    /// `true` when this instance created the file and seeded it.
    public let didSeed: Bool

    /// Opens the database, creating and seeding it the first time only.
    ///
    /// The schema and the seed rows go in together, in one transaction, so a
    /// failure part-way through leaves no half-built database for the next
    /// launch to mistake for a finished one.
    public init(url: URL, referenceDate: Date = Date()) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let isFirstLaunch = !fileManager.fileExists(atPath: url.path)

        self.url = url
        database = try GRDBDatabase(url: url, logger: nil)
        didSeed = isFirstLaunch

        if isFirstLaunch {
            try database.withTransaction { scope in
                try Self.createSchema(in: scope)
                try Self.insert(TodoSeed(referenceDate: referenceDate), in: scope)
            }
        }
    }

    /// Opens the demo's durable database in Application Support.
    public static func applicationDatabase(referenceDate: Date = Date()) throws -> TodoDatabase {
        try TodoDatabase(url: applicationSupportURL(), referenceDate: referenceDate)
    }

    /// Opens a throwaway database under the temporary directory. Used by the
    /// tests, and by anyone who wants to poke at the demo without keeping
    /// what they did.
    public static func temporary(referenceDate: Date = Date()) throws -> TodoDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftQLTodoDemo-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(fileName)
        return try TodoDatabase(url: url, referenceDate: referenceDate)
    }

    /// The demo's file in the user's Application Support directory.
    ///
    /// The directory itself may not exist yet on a fresh install; ``init``
    /// creates it.
    public static func applicationSupportURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("SwiftQLTodoDemo", isDirectory: true)
        .appendingPathComponent(fileName)
    }

    #if DEBUG
    /// Puts the database back to its seeded state.
    ///
    /// Debug builds only. Everything happens in one transaction, so a reset
    /// either lands completely or not at all.
    public func reset(referenceDate: Date = Date()) throws {
        try database.withTransaction { scope in
            try Self.deleteEverything(in: scope)
            try Self.insert(TodoSeed(referenceDate: referenceDate), in: scope)
        }
    }
    #endif

    // MARK: - Schema and seeding

    private static func createSchema(in scope: GRDBDatabase) throws {
        try scope.makeRequest(with: sqlCreate(TodoList.self)).execute()
        try scope.makeRequest(with: sqlCreate(Todo.self)).execute()
        try scope.makeRequest(with: sqlCreate(Tag.self)).execute()
        try scope.makeRequest(with: sqlCreate(TodoTag.self)).execute()
    }

    private static func insert(_ seed: TodoSeed, in scope: GRDBDatabase) throws {
        for list in seed.lists {
            try scope.makeRequest(with: sqlInsert(list)).execute()
        }
        for tag in seed.tags {
            try scope.makeRequest(with: sqlInsert(tag)).execute()
        }
        for todo in seed.todos {
            try scope.makeRequest(with: sqlInsert(todo)).execute()
        }
        for todoTag in seed.todoTags {
            try scope.makeRequest(with: sqlInsert(todoTag)).execute()
        }
    }

    private static func deleteEverything(in scope: GRDBDatabase) throws {
        let schema = XLSchema()
        try scope.makeRequest(with: delete(schema.into(TodoTag.self))).execute()
        try scope.makeRequest(with: delete(schema.into(Todo.self))).execute()
        try scope.makeRequest(with: delete(schema.into(Tag.self))).execute()
        try scope.makeRequest(with: delete(schema.into(TodoList.self))).execute()
    }
}
