import CSQLite
import Foundation
import GRDB


/// One entry in SQLite's one-based physical parameter table.
///
/// `name` preserves SQLite's leading sigil (`:`, `@`, `$`, or `?`). A `nil`
/// name is intentionally ambiguous at this layer: SQLite does not distinguish
/// an unused `?NNN` gap from an anonymous `?` through its statement metadata
/// API. The validator reconciles this table with SwiftQL's logical layout.
package struct SQLitePreparedParameter: Codable, Equatable, Sendable {
    package let physicalIndex: Int
    package let name: String?

    package init(physicalIndex: Int, name: String?) {
        self.physicalIndex = physicalIndex
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case physicalIndex = "physical_index"
        case name
    }
}


/// Metadata SQLite exposes for one zero-based result column at prepare time.
///
/// A missing `declaredType` is expected for expressions, aggregates, literals,
/// and other results that do not map directly to a declared schema column. It
/// is evidence only and must not be treated as a storage, codec, or nullability
/// proof.
package struct SQLitePreparedColumn: Codable, Equatable, Sendable {
    package let index: Int
    package let name: String
    package let declaredType: String?

    package init(index: Int, name: String, declaredType: String?) {
        self.index = index
        self.name = name
        self.declaredType = declaredType
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case name
        case declaredType = "declared_type"
    }
}


/// The connection-bound shape SQLite reports for one prepared statement.
package struct SQLitePreparedStatementShape: Codable, Equatable, Sendable {
    /// SQLite's largest physical parameter index, including any `?NNN` gaps.
    package let physicalParameterCount: Int

    /// One entry for every index in `1...physicalParameterCount`.
    package let parameters: [SQLitePreparedParameter]

    package let columns: [SQLitePreparedColumn]

    /// Raw `sqlite3_stmt_readonly` evidence. This does not classify SwiftQL's
    /// semantic command/query role.
    package let isReadOnly: Bool

    package init(
        physicalParameterCount: Int,
        parameters: [SQLitePreparedParameter],
        columns: [SQLitePreparedColumn],
        isReadOnly: Bool
    ) {
        self.physicalParameterCount = physicalParameterCount
        self.parameters = parameters
        self.columns = columns
        self.isReadOnly = isReadOnly
    }

    private enum CodingKeys: String, CodingKey {
        case physicalParameterCount = "physical_parameter_count"
        case parameters
        case columns
        case isReadOnly = "is_read_only"
    }
}


/// Stable preparation failures that the higher-level validator maps into its
/// deterministic report model.
package enum SQLitePrepareV3ProbeError: Error, Equatable, Sendable {
    case emptyStatement
    case embeddedNUL
    case multipleStatements
    case sqlitePrepare(
        resultCode: Int32,
        extendedResultCode: Int32,
        message: String
    )
}


/// Extracts SQLite statement metadata without executing the statement.
///
/// This API is package-visible so it can only be reached through the research
/// validator. It must be called inside the `read` closure of a validator-owned
/// `DatabaseQueue`, never against an application's long-lived pool. Raw C
/// preparation bypasses GRDB's internal statement-authorizer reset and must not
/// escape the serialized connection closure. Returned values contain copied
/// Swift strings only; no SQLite pointer survives this call.
package enum SQLitePrepareV3Probe {
    package static func prepare(
        sql: String,
        in database: Database
    ) throws -> SQLitePreparedStatementShape {
        guard !sql.utf8.contains(0) else {
            throw SQLitePrepareV3ProbeError.embeddedNUL
        }
        guard let connection = database.sqliteConnection else {
            throw syntheticPrepareFailure(
                resultCode: SQLITE_MISUSE,
                message: "The validator-owned SQLite connection is unavailable."
            )
        }

        return try sql.utf8CString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw SQLitePrepareV3ProbeError.emptyStatement
            }

            // `utf8CString` includes one trailing NUL byte. Supplying an exact
            // byte count keeps tail offsets deterministic and avoids allowing
            // embedded NUL to silently truncate the validated statement.
            let sqlByteCount = buffer.count - 1
            guard sqlByteCount <= Int(CInt.max) else {
                throw syntheticPrepareFailure(
                    resultCode: SQLITE_TOOBIG,
                    message: "SQL UTF-8 byte count \(sqlByteCount) exceeds Int32.max."
                )
            }

            let endAddress = baseAddress.advanced(by: sqlByteCount)
            var cursor = baseAddress
            var preparedShape: SQLitePreparedStatementShape?

            while cursor < endAddress {
                var statement: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                let remainingByteCount = cursor.distance(to: endAddress)
                let resultCode = sqlite3_prepare_v3(
                    connection,
                    cursor,
                    CInt(remainingByteCount),
                    0,
                    &statement,
                    &tail
                )

                guard resultCode == SQLITE_OK else {
                    // SQLite owns these pointers. Copy the diagnostic before
                    // finalization or any subsequent SQLite call can replace it.
                    let extendedResultCode = sqlite3_extended_errcode(connection)
                    let message = copiedString(sqlite3_errmsg(connection))
                        ?? "sqlite3_prepare_v3 failed without an error message."
                    if let statement {
                        _ = sqlite3_finalize(statement)
                    }
                    throw SQLitePrepareV3ProbeError.sqlitePrepare(
                        resultCode: resultCode,
                        extendedResultCode: extendedResultCode,
                        message: message
                    )
                }

                guard let tail,
                      tail > cursor,
                      tail <= endAddress else {
                    if let statement {
                        _ = sqlite3_finalize(statement)
                    }
                    throw syntheticPrepareFailure(
                        resultCode: SQLITE_MISUSE,
                        message: "sqlite3_prepare_v3 returned an invalid or non-advancing tail pointer."
                    )
                }

                if let statement {
                    let shape = try inspectAndFinalize(
                        statement,
                        connection: connection
                    )
                    guard preparedShape == nil else {
                        throw SQLitePrepareV3ProbeError.multipleStatements
                    }
                    preparedShape = shape
                }

                cursor = tail
            }

            guard let preparedShape else {
                throw SQLitePrepareV3ProbeError.emptyStatement
            }
            return preparedShape
        }
    }

    /// Copies every SQLite-owned string and finalizes `statement` exactly once,
    /// whether inspection succeeds or fails.
    private static func inspectAndFinalize(
        _ statement: OpaquePointer,
        connection: OpaquePointer
    ) throws -> SQLitePreparedStatementShape {
        let inspection: Result<SQLitePreparedStatementShape, SQLitePrepareV3ProbeError>
        do {
            inspection = .success(try inspect(statement, connection: connection))
        } catch let error as SQLitePrepareV3ProbeError {
            inspection = .failure(error)
        } catch {
            inspection = .failure(syntheticPrepareFailure(
                resultCode: SQLITE_ERROR,
                message: "Unexpected statement metadata inspection failure."
            ))
        }

        let finalizeResultCode = sqlite3_finalize(statement)
        switch inspection {
        case .failure(let error):
            throw error
        case .success(let shape):
            guard finalizeResultCode == SQLITE_OK else {
                let extendedResultCode = sqlite3_extended_errcode(connection)
                let message = copiedString(sqlite3_errmsg(connection))
                    ?? "sqlite3_finalize failed without an error message."
                throw SQLitePrepareV3ProbeError.sqlitePrepare(
                    resultCode: finalizeResultCode,
                    extendedResultCode: extendedResultCode,
                    message: message
                )
            }
            return shape
        }
    }

    private static func inspect(
        _ statement: OpaquePointer,
        connection: OpaquePointer
    ) throws -> SQLitePreparedStatementShape {
        let physicalParameterCount = Int(
            sqlite3_bind_parameter_count(statement)
        )
        var parameters: [SQLitePreparedParameter] = []
        parameters.reserveCapacity(physicalParameterCount)
        if physicalParameterCount > 0 {
            for physicalIndex in 1...physicalParameterCount {
                parameters.append(SQLitePreparedParameter(
                    physicalIndex: physicalIndex,
                    name: copiedString(sqlite3_bind_parameter_name(
                        statement,
                        CInt(physicalIndex)
                    ))
                ))
            }
        }

        let columnCount = Int(sqlite3_column_count(statement))
        var columns: [SQLitePreparedColumn] = []
        columns.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            let sqliteIndex = CInt(index)
            guard let name = copiedString(
                sqlite3_column_name(statement, sqliteIndex)
            ) else {
                throw syntheticPrepareFailure(
                    resultCode: SQLITE_NOMEM,
                    message: "SQLite returned no name for result column \(index)."
                )
            }
            columns.append(SQLitePreparedColumn(
                index: index,
                name: name,
                declaredType: copiedString(
                    sqlite3_column_decltype(statement, sqliteIndex)
                )
            ))
        }

        return SQLitePreparedStatementShape(
            physicalParameterCount: physicalParameterCount,
            parameters: parameters,
            columns: columns,
            isReadOnly: sqlite3_stmt_readonly(statement) != 0
        )
    }

    private static func copiedString(
        _ value: UnsafePointer<CChar>?
    ) -> String? {
        value.map(String.init(cString:))
    }

    private static func syntheticPrepareFailure(
        resultCode: Int32,
        message: String
    ) -> SQLitePrepareV3ProbeError {
        .sqlitePrepare(
            resultCode: resultCode,
            extendedResultCode: resultCode,
            message: message
        )
    }
}
