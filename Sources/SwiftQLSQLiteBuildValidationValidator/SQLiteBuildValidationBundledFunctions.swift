//
//  SQLiteBuildValidationBundledFunctions.swift
//  SwiftQLSQLiteBuildValidationValidator
//
//  Registering the SQLite functions SwiftQL itself supplies on the validator's
//  snapshot connection.
//
//  Issue #615.
//

import Foundation
import GRDB
import SwiftQLCore


///
/// The SQLite functions SwiftQL supplies at runtime, registered on the
/// connection the validator prepares statements against.
///
/// The validator prepares each manifest query against a pinned snapshot.
/// SQLite resolves a function name at preparation, so a query using `REGEXP`
/// -- which SQLite parses as a call to `regexp(Y, X)` -- fails to prepare on a
/// bare connection, and the build reports an error for a query the application
/// can run perfectly well. Registering what the runtime registers makes the two
/// agree.
///
/// This does not weaken the capability rules in
/// ``SQLiteBuildValidatorCapabilities``. Those prove a required capability from
/// the connection rather than from a declaration, and this connection genuinely
/// has these functions after registration -- SwiftQL will register the same
/// implementations on the connection that runs the statement. A function
/// SwiftQL does *not* supply is still absent here, so an application's own
/// unregistered function is reported exactly as before.
///
enum SQLiteBuildValidationBundledFunctions {

    /// Registers every function SwiftQL supplies on `database`.
    ///
    /// Called before the runtime capture, so `PRAGMA function_list` reports
    /// them and a `function:` capability naming one is satisfied by evidence
    /// rather than by assertion.
    ///
    /// A function already on the connection is left alone, matching the
    /// runtime rule that an application's own implementation wins.
    static func register(on database: Database) {
        for function in all where !hasFunction(matching: function, in: database) {
            database.add(function: function.databaseFunction())
        }
    }

    /// The signature and implementation of each supplied function.
    static let all: [Supplied] = [
        Supplied(name: "regexp", numberOfArguments: 2) { values in
            guard values.count == 2 else {
                return nil
            }
            guard
                let pattern = String.fromDatabaseValue(values[0]),
                let subject = String.fromDatabaseValue(values[1])
            else {
                // A NULL or non-text argument yields NULL here rather than the
                // runtime's typed column-read error. The validator only needs
                // the statement to prepare; a decoding failure raised from a
                // connection that never executes the statement would be noise.
                return nil
            }
            return try XLRegexpMatcher.matches(pattern: pattern, in: subject)
        },
    ]

    /// One function SwiftQL supplies, as the validator registers it.
    struct Supplied {

        let name: String

        let numberOfArguments: Int

        let body: @Sendable ([DatabaseValue]) throws -> (any DatabaseValueConvertible)?

        init(
            name: String,
            numberOfArguments: Int,
            body: @escaping @Sendable ([DatabaseValue]) throws -> (any DatabaseValueConvertible)?
        ) {
            self.name = name
            self.numberOfArguments = numberOfArguments
            self.body = body
        }

        func databaseFunction() -> DatabaseFunction {
            DatabaseFunction(
                name,
                argumentCount: numberOfArguments,
                pure: true,
                function: body
            )
        }
    }

    /// Whether the connection already provides this signature.
    ///
    /// Name and arity, because SQLite keys a function on both. `-1` is what
    /// `PRAGMA function_list` reports for a variadic function, which can serve
    /// a fixed-arity call.
    private static func hasFunction(
        matching function: Supplied,
        in database: Database
    ) -> Bool {
        guard let rows = try? Row.fetchAll(
            database,
            sql: "PRAGMA function_list"
        ) else {
            return false
        }
        let folded = sqliteASCIIFolded(function.name)
        return rows.contains { row in
            guard
                let name = row["name"] as String?,
                sqliteASCIIFolded(name) == folded,
                let argumentCount = row["narg"] as Int?
            else {
                return false
            }
            return argumentCount == function.numberOfArguments
                || argumentCount == -1
        }
    }
}
