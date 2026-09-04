//
//  SQLiteVersion.swift
//  SwiftQLTestSupport
//
//  Comparing the linked SQLite's version, numerically (issue #557).
//

import Foundation
import GRDB


///
/// A SQLite version, ordered by its components rather than by its spelling.
///
/// Three test files compared versions by hand, and lexicographic comparison is
/// a real trap here: "3.9.0" sorts *after* "3.39.0" as text, so a gate written
/// that way skips on exactly the builds it was meant to run on. Components are
/// compared as numbers, and a pre-release suffix (`3.39.0rc1`) is read as the
/// component it prefixes rather than dropping it.
///
public struct SQLiteVersion: Comparable, CustomStringConvertible, Sendable {

    /// Major, minor, patch. Missing components read as zero, so `3.39` and
    /// `3.39.0` are the same version.
    public let components: [Int]

    /// The version exactly as SQLite reported or the caller wrote it.
    public let description: String

    public init(_ version: String) {
        self.description = version
        self.components = version.split(separator: ".").map { component in
            Int(component.prefix(while: \.isNumber)) ?? 0
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}


///
/// The version of the SQLite this connection is talking to.
///
/// Throws rather than falling back when the query returns nothing. An empty
/// version parses as 0.0.0, which is below every gate -- so a lookup that
/// quietly failed would skip the tests it guards instead of failing them, and
/// the coverage would disappear silently.
///
public func sqliteVersion(in database: Database) throws -> SQLiteVersion {
    guard let version = try String.fetchOne(
        database,
        sql: "SELECT sqlite_version()"
    ) else {
        throw SQLiteVersionError.unavailable
    }
    return SQLiteVersion(version)
}


public enum SQLiteVersionError: Error, CustomStringConvertible {

    case unavailable

    public var description: String {
        switch self {
        case .unavailable:
            return "SELECT sqlite_version() returned no row; the linked "
                + "SQLite's version could not be determined."
        }
    }
}


///
/// The version of the SQLite behind this pool.
///
public func sqliteVersion(in pool: DatabasePool) throws -> SQLiteVersion {
    try pool.read { database in
        try sqliteVersion(in: database)
    }
}


///
/// Whether the linked SQLite is at least `version`.
///
/// Call it from `try XCTSkipUnless(...)`: the skip itself is one line at the
/// call site and says what the test needs, while the comparison -- the part
/// that was getting written wrong -- lives here.
///
public func sqlite(in pool: DatabasePool, isAtLeast version: String) throws -> Bool {
    try sqliteVersion(in: pool) >= SQLiteVersion(version)
}
