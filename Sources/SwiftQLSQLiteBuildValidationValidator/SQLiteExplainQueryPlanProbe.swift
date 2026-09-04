import CSQLite
import Foundation
import GRDB


/// Stable `EXPLAIN QUERY PLAN` failures the plan capture pass maps into an
/// explicit `unsupported` plan record.
public enum SQLiteExplainQueryPlanProbeError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case embeddedNUL
    case unavailableConnection
    case sqlitePrepare(
        resultCode: Int32,
        extendedResultCode: Int32,
        message: String
    )
    case sqliteStep(
        resultCode: Int32,
        extendedResultCode: Int32,
        message: String
    )
    case sqliteFinalize(
        resultCode: Int32,
        extendedResultCode: Int32,
        message: String
    )
    case unexpectedColumnLayout(columnCount: Int)

    public var description: String {
        switch self {
        case .embeddedNUL:
            return "The statement contains an embedded NUL byte."
        case .unavailableConnection:
            return "The validator-owned SQLite connection is unavailable."
        case .sqlitePrepare(let resultCode, let extendedResultCode, let message):
            return "sqlite3_prepare_v3 of EXPLAIN QUERY PLAN failed with result code \(resultCode) (extended \(extendedResultCode)): \(message)"
        case .sqliteStep(let resultCode, let extendedResultCode, let message):
            return "sqlite3_step of EXPLAIN QUERY PLAN failed with result code \(resultCode) (extended \(extendedResultCode)): \(message)"
        case .sqliteFinalize(let resultCode, let extendedResultCode, let message):
            return "sqlite3_finalize of EXPLAIN QUERY PLAN failed with result code \(resultCode) (extended \(extendedResultCode)): \(message)"
        case .unexpectedColumnLayout(let columnCount):
            return "EXPLAIN QUERY PLAN returned \(columnCount) columns; this validator expects SQLite's four-column id/parent/notused/detail layout."
        }
    }
}


/// Runs `EXPLAIN QUERY PLAN` for one statement and returns its raw rows.
///
/// Must be called inside the `read` closure of a validator-owned
/// `DatabaseQueue`, never against an application's long-lived pool — the same
/// contract ``SQLitePrepareV3Probe`` carries, and for the same reason: raw C
/// preparation bypasses GRDB's internal statement-authorizer reset and must
/// not escape the serialized connection closure. No SQLite pointer survives
/// this call; the returned rows hold copied Swift values only.
///
/// ## Parameters are left unbound
///
/// The manifest records a statement's parameter *shape*, not the values an
/// application will bind, so there are no values to bind here and every
/// placeholder is left at its default NULL. On a snapshot without `ANALYZE`
/// statistics — which the pinned snapshot deliberately is — SQLite's plan
/// choice does not read the bound value at all, so the captured plan is the
/// plan the statement gets. On a snapshot built with `SQLITE_ENABLE_STAT4`
/// *and* analyzed, SQLite can specialize a plan to a bound value, and this
/// capture would then record the NULL-bound plan rather than a running
/// application's. ``SQLiteBuildValidationPlanProvenance`` records the
/// `ENABLE_STAT4` compile option for exactly this reason, and the plan report
/// names the caveat.
public enum SQLiteExplainQueryPlanProbe {
    static let sqlPrefix = "EXPLAIN QUERY PLAN "

    /// SQLite's EQP result layout: `id`, `parent`, `notused`, `detail`.
    /// `notused` is read past rather than recorded — SQLite documents it as
    /// carrying no meaning.
    private static let expectedColumnCount = 4
    private static let idColumn: CInt = 0
    private static let parentColumn: CInt = 1
    private static let detailColumn: CInt = 3

    public static func rows(
        forSQL sql: String,
        in database: Database
    ) throws -> [SQLiteBuildValidationPlanRow] {
        guard !sql.utf8.contains(0) else {
            throw SQLiteExplainQueryPlanProbeError.embeddedNUL
        }
        guard let connection = database.sqliteConnection else {
            throw SQLiteExplainQueryPlanProbeError.unavailableConnection
        }

        var statement: OpaquePointer?
        let prepareResultCode = (sqlPrefix + sql).withCString { cString in
            sqlite3_prepare_v3(connection, cString, -1, 0, &statement, nil)
        }
        guard prepareResultCode == SQLITE_OK, let statement else {
            // SQLite owns these pointers. Copy the diagnostic before
            // finalization or any later SQLite call can replace it.
            let extendedResultCode = sqlite3_extended_errcode(connection)
            let message = copiedString(sqlite3_errmsg(connection))
                ?? "sqlite3_prepare_v3 failed without an error message."
            if let statement {
                _ = sqlite3_finalize(statement)
            }
            throw SQLiteExplainQueryPlanProbeError.sqlitePrepare(
                resultCode: prepareResultCode,
                extendedResultCode: extendedResultCode,
                message: message
            )
        }

        let collected: Result<[SQLiteBuildValidationPlanRow], Error>
        do {
            collected = .success(try collectRows(statement, connection: connection))
        } catch {
            collected = .failure(error)
        }

        // Check finalization before the collection outcome: a failing
        // finalize is a statement-lifecycle problem in its own right and must
        // not be discarded because stepping also failed.
        let finalizeResultCode = sqlite3_finalize(statement)
        guard finalizeResultCode == SQLITE_OK else {
            throw SQLiteExplainQueryPlanProbeError.sqliteFinalize(
                resultCode: finalizeResultCode,
                extendedResultCode: sqlite3_extended_errcode(connection),
                message: copiedString(sqlite3_errmsg(connection))
                    ?? "sqlite3_finalize failed without an error message."
            )
        }
        return try collected.get()
    }

    private static func collectRows(
        _ statement: OpaquePointer,
        connection: OpaquePointer
    ) throws -> [SQLiteBuildValidationPlanRow] {
        let columnCount = Int(sqlite3_column_count(statement))
        guard columnCount == expectedColumnCount else {
            throw SQLiteExplainQueryPlanProbeError.unexpectedColumnLayout(
                columnCount: columnCount
            )
        }

        var rows: [SQLiteBuildValidationPlanRow] = []
        while true {
            let stepResultCode = sqlite3_step(statement)
            if stepResultCode == SQLITE_DONE {
                return rows
            }
            guard stepResultCode == SQLITE_ROW else {
                throw SQLiteExplainQueryPlanProbeError.sqliteStep(
                    resultCode: stepResultCode,
                    extendedResultCode: sqlite3_extended_errcode(connection),
                    message: copiedString(sqlite3_errmsg(connection))
                        ?? "sqlite3_step failed without an error message."
                )
            }
            rows.append(SQLiteBuildValidationPlanRow(
                id: sqlite3_column_int64(statement, idColumn),
                parent: sqlite3_column_int64(statement, parentColumn),
                detail: copiedString(sqlite3_column_text(statement, detailColumn)) ?? ""
            ))
        }
    }

    private static func copiedString(_ value: UnsafePointer<CChar>?) -> String? {
        value.map(String.init(cString:))
    }

    private static func copiedString(_ value: UnsafePointer<UInt8>?) -> String? {
        value.map { String(cString: $0) }
    }
}
