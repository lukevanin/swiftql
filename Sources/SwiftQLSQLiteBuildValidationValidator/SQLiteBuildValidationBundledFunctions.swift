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
        // One pragma for the whole set, not one per function. A build that
        // cannot answer it reports nothing, which reads as "the connection
        // provides none of these" and registers all of them -- the same
        // reading the runtime probe gives an unanswerable pragma.
        let rows = (try? Row.fetchAll(database, sql: "PRAGMA function_list")) ?? []
        for registration in all where !hasFunction(matching: registration.definition, in: rows) {
            database.add(function: databaseFunction(for: registration))
        }
    }

    /// The functions SwiftQL supplies at runtime: SwiftQLCore's own table,
    /// so the validator and the runtime cannot disagree (issue #683).
    static var all: [XLCustomFunctionRegistration] {
        XLCustomFunctionRegistration.bundled.values.sorted {
            $0.definition < $1.definition
        }
    }

    /// A GRDB function that evaluates `registration`, as the runtime's does.
    ///
    /// The validator only prepares statements, so the function is never
    /// called; it has to exist, with the right name and argument count, for
    /// SQLite to resolve the call.
    static func databaseFunction(for registration: XLCustomFunctionRegistration) -> DatabaseFunction {
        let evaluate = registration.makeEvaluator()
        return DatabaseFunction(
            registration.definition.name,
            argumentCount: registration.definition.numberOfArguments,
            pure: registration.isPure,
            function: { values in
                try databaseValue(evaluate(values.map(sqliteValue)))
            }
        )
    }

    private static func sqliteValue(_ value: DatabaseValue) -> XLSQLiteValue {
        switch value.storage {
        case .null:
            return .null
        case .int64(let integer):
            return .integer(integer)
        case .double(let real):
            return .real(real)
        case .string(let text):
            return .text(text)
        case .blob(let blob):
            return .blob(blob)
        }
    }

    private static func databaseValue(_ value: XLSQLiteValue) -> DatabaseValue {
        switch value {
        case .null:
            return .null
        case .integer(let integer):
            return integer.databaseValue
        case .real(let real):
            return real.databaseValue
        case .text(let text):
            return text.databaseValue
        case .blob(let blob):
            return blob.databaseValue
        }
    }

    /// Whether the connection already provides this signature.
    ///
    /// Name and arity, because SQLite keys a function on both. `-1` is what
    /// `PRAGMA function_list` reports for a variadic function, which can serve
    /// a fixed-arity call.
    ///
    /// `rows` is one `PRAGMA function_list` capture, read once by the caller
    /// and tested against every supplied function.
    private static func hasFunction(
        matching function: XLCustomFunctionDefinition,
        in rows: [Row]
    ) -> Bool {
        let folded = sqliteASCIIFolded(function.name)
        return rows.contains { row in
            guard
                let name = row["name"] as String?,
                sqliteASCIIFolded(name) == folded
            else {
                return false
            }
            guard let argumentCount = row["narg"] as Int? else {
                // A build that reports no argument count cannot distinguish
                // the overloads, so the name is the whole answer rather than
                // registering over the caller. Same rule as the runtime probe
                // in `GRDBDatabaseDriverConnection.hasFunction(matching:)`.
                return true
            }
            return argumentCount == function.numberOfArguments
                || argumentCount == -1
        }
    }
}
