//
//  SQLiteRuntimeCapability.swift
//
//
//  Milestone v1.6: asking a connection what its SQLite can do.
//
//  The supported matrix is not one SQLite. The macOS cells run the system
//  SQLite, 3.43.2 at the time of writing, and the Linux cells run a pinned
//  3.53.3 build. Several JSON features arrived between those two versions:
//  `json_valid(X, F)` and the whole JSONB family in 3.45.0, and `json_pretty`
//  in 3.46.0.
//
//  A test for one of those cannot simply run everywhere, and pinning a
//  version number in the test would be a claim this repository cannot check
//  against every runtime it supports. Ask the connection instead.
//

import Foundation
import GRDB
import XCTest


enum SQLiteRuntimeCapability {

    ///
    /// Reports whether the connected SQLite defines a function with the given
    /// name and argument count.
    ///
    /// `pragma function_list` reports one row per arity, so an overload that
    /// arrived in a later version than its siblings is visible here.
    ///
    static func hasFunction(
        _ name: String,
        argumentCount: Int,
        in pool: DatabasePool
    ) throws -> Bool {
        try pool.read { database in
            let count = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) FROM pragma_function_list
                    WHERE lower(name) = lower(?) AND narg = ?
                    """,
                arguments: [name, argumentCount]
            )
            return (count ?? 0) > 0
        }
    }

    ///
    /// Skips the calling test when the connected SQLite lacks the function.
    ///
    /// A skip states which runtime cannot run the case. A test dropped from
    /// the suite for the oldest runtime's sake would state nothing at all.
    ///
    static func requireFunction(
        _ name: String,
        argumentCount: Int,
        since version: String,
        in pool: DatabasePool
    ) throws {
        guard try hasFunction(name, argumentCount: argumentCount, in: pool) else {
            let runtime = try pool.read { database in
                try String.fetchOne(database, sql: "SELECT sqlite_version()")
            } ?? "unknown"
            throw XCTSkip(
                """
                This SQLite is \(runtime) and does not define \
                \(name)/\(argumentCount), which needs \(version) or later.
                """
            )
        }
    }
}
