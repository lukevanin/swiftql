//
//  TemporaryDatabase.swift
//  SwiftQLTestSupport
//
//  A scoped temporary SQLite database (issue #557).
//
//  Fifteen test files carried their own near-identical fixture struct for this
//  -- a temporary directory, a `DatabasePool`, and a `tearDown()` closing and
//  removing both -- reached through `defer { fixture.tearDown() }`. That
//  pattern leaks whenever the fixture's own construction throws after the
//  directory exists but before the pool does: the `defer` has not been
//  installed yet, so the directory outlives the process.
//

import Foundation
import GRDB


///
/// Runs `body` with a `DatabasePool` backed by a file in a temporary directory
/// of its own, and closes the pool and removes the directory before returning.
///
/// The directory is registered for cleanup the moment it exists, so a failure
/// opening the pool cleans up the directory it had already created. Cleanup is
/// best-effort and never masks the error a test is reporting: a test that has
/// already failed should say why it failed, not that its temporary directory
/// could not be deleted.
///
/// - Parameters:
///   - name: A short label for the directory, so a leaked one -- if the process
///     dies outright -- names the suite that made it.
///   - configuration: The GRDB configuration to open the pool with.
///   - body: Receives the open pool. Its return value is this function's.
///
public func withTemporaryDatabasePool<Result>(
    named name: String,
    configuration: Configuration = Configuration(),
    _ body: (DatabasePool) throws -> Result
) throws -> Result {
    let directoryURL = try makeTemporaryDirectory(named: name)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let pool = try DatabasePool(
        path: directoryURL.appendingPathComponent("database.sqlite").path,
        configuration: configuration
    )
    defer { try? pool.close() }

    return try body(pool)
}


///
/// The same, for a caller that needs the directory as well as the pool -- to
/// place a second database beside the first, or to assert on a sidecar file.
///
public func withTemporaryDatabasePool<Result>(
    named name: String,
    configuration: Configuration = Configuration(),
    _ body: (DatabasePool, URL) throws -> Result
) throws -> Result {
    let directoryURL = try makeTemporaryDirectory(named: name)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let pool = try DatabasePool(
        path: directoryURL.appendingPathComponent("database.sqlite").path,
        configuration: configuration
    )
    defer { try? pool.close() }

    return try body(pool, directoryURL)
}


///
/// Creates an empty directory under the system temporary directory, named for
/// `name` and a fresh UUID.
///
/// The UUID is what makes concurrent tests safe: XCTest runs a suite's methods
/// in sequence but several suites can be in flight, and two tests sharing a
/// database file is a failure that reproduces only under load.
///
public func makeTemporaryDirectory(named name: String) throws -> URL {
    // `name` becomes part of a path. Every caller passes a literal label, and
    // this keeps it that way: a name carrying `/` or `..` would place the
    // directory -- and the `removeItem` that later tears it down -- somewhere
    // other than the temporary directory.
    precondition(
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" },
        "Temporary directory labels must be plain identifiers; got '\(name)'."
    )
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftql-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    return directoryURL
}


///
/// A temporary database held for as long as the caller needs it, rather than
/// for the duration of a closure.
///
/// ``withTemporaryDatabasePool(named:configuration:_:)`` is the better shape
/// for new code -- the scope is the lifetime, and there is nothing to forget.
/// This exists for tests written against the fifteen hand-rolled fixtures it
/// replaces (issue #557), whose call sites pair it with
/// `defer { fixture.tearDown() }`.
///
/// It still fixes what those got wrong: ``make(named:configuration:)`` removes
/// the directory it created if opening the pool fails, where a fixture built in
/// two steps left the directory behind whenever the second step threw -- the
/// caller's `defer` not yet installed.
///
public struct TemporaryDatabaseFixture {

    /// The directory holding the database, removed by ``tearDown()``.
    public let directoryURL: URL

    /// The open pool.
    public let pool: DatabasePool

    /// The database file itself, for a test that needs to inspect or copy it.
    public var databaseURL: URL {
        directoryURL.appendingPathComponent("database.sqlite")
    }

    public static func make(
        named name: String,
        configuration: Configuration = Configuration()
    ) throws -> Self {
        let directoryURL = try makeTemporaryDirectory(named: name)
        do {
            return Self(
                directoryURL: directoryURL,
                pool: try DatabasePool(
                    path: directoryURL.appendingPathComponent("database.sqlite").path,
                    configuration: configuration
                )
            )
        }
        catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    /// Closes the pool and removes the directory. Best-effort, so a failing
    /// test reports why it failed rather than that its temporary directory
    /// could not be deleted.
    public func tearDown() {
        try? pool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
