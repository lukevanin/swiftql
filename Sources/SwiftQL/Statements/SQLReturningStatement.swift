//
//  SQLReturningStatement.swift
//
//  Shared surface for the v1.4.4 `RETURNING` clause on data-changing
//  statements (INSERT / UPDATE / DELETE).
//

import Foundation


// MARK: - Returning clause


///
/// A `RETURNING` clause appended to a data-changing statement.
///
/// `RETURNING` turns an `INSERT`, `UPDATE`, or `DELETE` into a statement that
/// yields the affected rows, projected through the supplied result metadata.
/// SQLite rejects table-qualified column names in a `RETURNING` list — a
/// statement such as `INSERT INTO Test AS t0 ... RETURNING t0.id` fails to
/// prepare with `no such column: t0.id` — so the clause renders the projection's
/// columns *unqualified* (`RETURNING id, value`) while decoding rows through the
/// projection's own reader.
///
/// Requires SQLite 3.35.0 (2021-03-12) or later.
///
public struct Returning<Row>: XLEncodable, XLRowReadable {

    private let columns: [XLName]

    private let decode: (XLRowReader) throws -> Row

    ///
    /// Creates a `RETURNING` clause projecting the columns described by the
    /// given result metadata, for example a table reference obtained from
    /// ``XLSchema/table(_:)``.
    ///
    public init<T>(_ result: T) where T: XLRowReadable, T.Row == Row {
        let definition = XLColumnsDefinitionRowReader()
        // Replay the projection to capture its output column names. The
        // definition reader returns SQL defaults, so no database row is decoded
        // here — matching `Select(_ meta:)`. A projection that cannot enumerate
        // its columns against the definition reader (for example one that decodes
        // through `staticColumn`) is unsupported here and traps diagnostically
        // rather than surfacing an opaque `try!` crash.
        do {
            _ = try result.readRow(reader: definition)
        }
        catch {
            preconditionFailure(
                "RETURNING projection \(String(reflecting: T.self)) could not "
                + "enumerate its columns: \(error). Use a table or @SQLResult "
                + "projection whose columns render as bare names."
            )
        }
        self.columns = definition.columnNames
        self.decode = result.readRow
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("RETURNING") { context in
            context.list(separator: .list) { list in
                for column in columns {
                    list.listItem { item in
                        item.name(column)
                    }
                }
            }
        }
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try decode(reader)
    }
}


// MARK: - Returning statement


///
/// A data-changing statement carrying a trailing `RETURNING` clause.
///
/// Unlike a plain `INSERT`/`UPDATE`/`DELETE` — which are write-only and executed
/// through ``XLWriteRequest`` — a returning statement is both renderable and
/// row-readable, so ``XLDatabase/makeRequest(with:)-(XLReturningStatement)``
/// builds a reader-backed ``XLRequest`` whose rows are the values named by the
/// `RETURNING` clause.
///
public protocol XLReturningStatement<Row>: XLEncodable, XLRowReadable {
}


///
/// Errors specific to executing a `RETURNING` statement request.
///
public enum XLReturningRequestError: Error, Equatable {

    ///
    /// A `RETURNING` statement was published as a live query. Data-changing
    /// statements execute once and are not observable — re-running the write on
    /// every database change is never the intended behavior. Use `fetchAll()`
    /// or `fetchOne()` to execute the statement and read the returned rows.
    ///
    case observationUnsupported
}


///
/// An `INSERT ... RETURNING` statement.
///
public struct XLInsertReturningStatement<Row>: XLReturningStatement {

    let statement: any XLEncodable

    let returning: Returning<Row>

    public func makeSQL(context: inout XLBuilder) {
        statement.makeSQL(context: &context)
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try returning.readRow(reader: reader)
    }
}


extension XLInsertStatement {

    ///
    /// Appends a `RETURNING` clause projecting the given result metadata, turning
    /// the insert into a fetchable statement that yields the inserted rows.
    ///
    /// ```swift
    /// let inserted: [TestTable] = try database.makeRequest(
    ///     with: insert(t).values(row).returning(t)
    /// ).fetchAll()
    /// ```
    ///
    /// Requires SQLite 3.35.0 or later.
    ///
    public func returning<T>(_ result: T) -> XLInsertReturningStatement<T.Row> where T: XLRowReadable {
        let clause = Returning<T.Row>(result)
        return XLInsertReturningStatement(
            statement: components.appending(clause),
            returning: clause
        )
    }
}
