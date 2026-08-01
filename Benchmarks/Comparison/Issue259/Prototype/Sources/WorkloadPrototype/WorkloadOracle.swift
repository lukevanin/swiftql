import Foundation
import SQLite3

/// Library-neutral state oracle and reset for the write workload. It uses the
/// SQLite C API directly on its own connection so that no compared library's
/// semantics leak into the correctness check or into the between-iteration
/// reset. Everything here runs outside the timed interval.
final class PrototypeStateOracle {
    private var handle: OpaquePointer?

    init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            throw PrototypeError.sqlite("could not open oracle connection (\(status))")
        }
        self.handle = handle
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    func execute(_ sql: String) throws {
        guard let handle else {
            throw PrototypeError.sqlite("oracle connection is closed")
        }
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard status == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "status \(status)"
            throw PrototypeError.sqlite("\(sql): \(detail)")
        }
    }

    /// Reads back everything the timed transaction wrote and folds it into the
    /// value oracle, so the checksum observes committed state rather than the
    /// writer's own return value.
    func checksumScratchRows() throws -> UInt64 {
        guard let handle else {
            throw PrototypeError.sqlite("oracle connection is closed")
        }
        var statement: OpaquePointer?
        let sql = """
            SELECT id, name, amount
            FROM \(PrototypeConstants.scratchTableName)
            ORDER BY id
            """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PrototypeError.sqlite("could not prepare the oracle read-back")
        }
        defer { sqlite3_finalize(statement) }

        var checksum = PrototypeChecksum()
        var rowCount = 0
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw PrototypeError.sqlite("oracle read-back failed (\(step))")
            }
            checksum.combine(Int(sqlite3_column_int64(statement, 0)))
            checksum.combine(String(cString: sqlite3_column_text(statement, 1)))
            checksum.combine(sqlite3_column_double(statement, 2))
            rowCount += 1
        }
        guard rowCount == PrototypeConstants.writeBatchSize else {
            throw PrototypeError.unexpectedChangeCount(
                expected: PrototypeConstants.writeBatchSize,
                actual: rowCount
            )
        }
        return checksum.value
    }

    /// Independently decodes one `Orders` row through the SQLite C API and
    /// folds it into the same value oracle the measured libraries are checked
    /// against. This is what makes a per-iteration bound parameter safe: each
    /// key has its own expected checksum.
    func checksumOrder(orderID: Int) throws -> UInt64 {
        guard let handle else {
            throw PrototypeError.sqlite("oracle connection is closed")
        }
        var statement: OpaquePointer?
        let sql = """
            SELECT "OrderID", "CustomerID", "EmployeeID", "OrderDate",
                   "RequiredDate", "ShippedDate", "ShipVia", "Freight",
                   "ShipName", "ShipAddress", "ShipCity", "ShipRegion",
                   "ShipPostalCode", "ShipCountry"
            FROM "Orders"
            WHERE "OrderID" = ?
            """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PrototypeError.sqlite("could not prepare the order oracle")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(orderID))
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw PrototypeError.unexpectedRowCount(
                workload: PrototypeWorkload.pointLookup.rawValue,
                expected: 1,
                actual: 0
            )
        }

        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                  let pointer = sqlite3_column_text(statement, column)
            else {
                return nil
            }
            return String(cString: pointer)
        }
        func integer(_ column: Int32) -> Int? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
                return nil
            }
            return Int(sqlite3_column_int64(statement, column))
        }
        func double(_ column: Int32) -> Double? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
                return nil
            }
            return sqlite3_column_double(statement, column)
        }

        let order = PrototypeOrder(
            orderID: Int(sqlite3_column_int64(statement, 0)),
            customerID: text(1),
            employeeID: integer(2),
            orderDate: text(3),
            requiredDate: text(4),
            shippedDate: text(5),
            shipVia: integer(6),
            freight: double(7),
            shipName: text(8),
            shipAddress: text(9),
            shipCity: text(10),
            shipRegion: text(11),
            shipPostalCode: text(12),
            shipCountry: text(13)
        )
        var checksum = PrototypeChecksum()
        checksum.combine(order)
        return checksum.value
    }

    /// Independently computes the join/aggregate result through the SQLite C
    /// API so the measured libraries are checked against SQLite itself.
    func checksumCountryVolumes() throws -> UInt64 {
        guard let handle else {
            throw PrototypeError.sqlite("oracle connection is closed")
        }
        var statement: OpaquePointer?
        let sql = """
            SELECT "Customers"."Country",
                   COUNT("Orders"."OrderID"),
                   TOTAL("Orders"."Freight")
            FROM "Orders"
            INNER JOIN "Customers"
                ON "Customers"."CustomerID" = "Orders"."CustomerID"
            GROUP BY "Customers"."Country"
            ORDER BY "Customers"."Country" ASC
            """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PrototypeError.sqlite("could not prepare the aggregate oracle")
        }
        defer { sqlite3_finalize(statement) }

        var checksum = PrototypeChecksum()
        var groupCount = 0
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw PrototypeError.sqlite("aggregate oracle failed (\(step))")
            }
            let country: String?
            if sqlite3_column_type(statement, 0) == SQLITE_NULL {
                country = nil
            } else {
                country = String(cString: sqlite3_column_text(statement, 0))
            }
            checksum.combine(
                PrototypeCountryVolume(
                    country: country,
                    orderCount: Int(sqlite3_column_int64(statement, 1)),
                    freightTotal: sqlite3_column_double(statement, 2)
                )
            )
            groupCount += 1
        }
        guard groupCount == PrototypeConstants.expectedCountryGroupCount else {
            throw PrototypeError.unexpectedRowCount(
                workload: PrototypeWorkload.joinAggregate.rawValue,
                expected: PrototypeConstants.expectedCountryGroupCount,
                actual: groupCount
            )
        }
        return checksum.value
    }

    func scratchRowCount() throws -> Int {
        guard let handle else {
            throw PrototypeError.sqlite("oracle connection is closed")
        }
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(PrototypeConstants.scratchTableName)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PrototypeError.sqlite("could not prepare the oracle count")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw PrototypeError.sqlite("oracle count returned no row")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func clearScratchRows() throws {
        try execute("DELETE FROM \(PrototypeConstants.scratchTableName)")
    }
}
