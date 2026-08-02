import Foundation
import SQLite

private enum OrdersTable {
    static let table = Table("Orders")
    static let orderID = SQLite.Expression<Int>("OrderID")
    static let customerID = SQLite.Expression<String?>("CustomerID")
    static let employeeID = SQLite.Expression<Int?>("EmployeeID")
    static let orderDate = SQLite.Expression<String?>("OrderDate")
    static let requiredDate = SQLite.Expression<String?>("RequiredDate")
    static let shippedDate = SQLite.Expression<String?>("ShippedDate")
    static let shipVia = SQLite.Expression<Int?>("ShipVia")
    /// `Orders.Freight` is a NUMERIC column whose values are stored as a mix of
    /// INTEGER and REAL. SQLite.swift's typed decoder rejects an INTEGER for a
    /// `Double?` expression, so the typed query casts the column, exactly as
    /// the #250 full-fetch harness does.
    static let freight = SQLite.Expression<Double?>(literal: "CAST(\"Freight\" AS REAL)")
    static let shipName = SQLite.Expression<String?>("ShipName")
    static let shipAddress = SQLite.Expression<String?>("ShipAddress")
    static let shipCity = SQLite.Expression<String?>("ShipCity")
    static let shipRegion = SQLite.Expression<String?>("ShipRegion")
    static let shipPostalCode = SQLite.Expression<String?>("ShipPostalCode")
    static let shipCountry = SQLite.Expression<String?>("ShipCountry")

    /// The aggregate reads the raw column: `TOTAL()` always returns a REAL, so
    /// no cast is needed and none is applied.
    static let rawFreight = SQLite.Expression<Double?>("Freight")
}

private enum CustomersTable {
    static let table = Table("Customers")
    static let customerID = SQLite.Expression<String>("CustomerID")
    static let country = SQLite.Expression<String?>("Country")
}

private enum ScratchTable {
    static let table = Table(PrototypeConstants.scratchTableName)
    static let id = SQLite.Expression<Int>("id")
    static let name = SQLite.Expression<String>("name")
    static let amount = SQLite.Expression<Double>("amount")
}

/// SQLite.swift adapter. All three workloads use its typed query builder.
final class SQLiteSwiftPrototypeAdapter {
    private let connection: Connection
    /// Captured once at initialisation, before the first warmup, so no timed
    /// operation pays for reading them.
    private let lookupKeys = PrototypeConstants.lookupKeys
    private let writeBatch = PrototypeConstants.writeBatch

    init(databaseURL: URL, writable: Bool) throws {
        connection = try Connection(databaseURL.path, readonly: !writable)
    }

    func pointLookup(iteration: Int) throws -> PrototypeOrder? {
        let key = lookupKeys[iteration % lookupKeys.count]
        let query = OrdersTable.table
            .select(
                OrdersTable.orderID,
                OrdersTable.customerID,
                OrdersTable.employeeID,
                OrdersTable.orderDate,
                OrdersTable.requiredDate,
                OrdersTable.shippedDate,
                OrdersTable.shipVia,
                OrdersTable.freight,
                OrdersTable.shipName,
                OrdersTable.shipAddress,
                OrdersTable.shipCity,
                OrdersTable.shipRegion,
                OrdersTable.shipPostalCode,
                OrdersTable.shipCountry
            )
            .filter(OrdersTable.orderID == key)
        guard let row = try connection.pluck(query) else {
            return nil
        }
        return PrototypeOrder(
            orderID: row[OrdersTable.orderID],
            customerID: row[OrdersTable.customerID],
            employeeID: row[OrdersTable.employeeID],
            orderDate: row[OrdersTable.orderDate],
            requiredDate: row[OrdersTable.requiredDate],
            shippedDate: row[OrdersTable.shippedDate],
            shipVia: row[OrdersTable.shipVia],
            freight: row[OrdersTable.freight],
            shipName: row[OrdersTable.shipName],
            shipAddress: row[OrdersTable.shipAddress],
            shipCity: row[OrdersTable.shipCity],
            shipRegion: row[OrdersTable.shipRegion],
            shipPostalCode: row[OrdersTable.shipPostalCode],
            shipCountry: row[OrdersTable.shipCountry]
        )
    }

    func joinAggregate() throws -> [PrototypeCountryVolume] {
        let country = CustomersTable.table[CustomersTable.country]
        let orderCount = OrdersTable.table[OrdersTable.orderID].count
        let freightTotal = OrdersTable.table[OrdersTable.rawFreight].total
        let query = OrdersTable.table
            .join(
                CustomersTable.table,
                on: CustomersTable.table[CustomersTable.customerID]
                    == OrdersTable.table[OrdersTable.customerID]
            )
            .select(country, orderCount, freightTotal)
            .group(country)
            .order(country.asc)
        return try connection.prepare(query).map { row in
            PrototypeCountryVolume(
                country: row[country],
                orderCount: row[orderCount],
                freightTotal: row[freightTotal]
            )
        }
    }

    func transactionalWrite() throws -> Int {
        let batch = writeBatch
        try connection.transaction {
            for row in batch {
                try connection.run(
                    ScratchTable.table.insert(
                        ScratchTable.id <- row.id,
                        ScratchTable.name <- row.name,
                        ScratchTable.amount <- row.amount
                    )
                )
            }
        }
        return batch.count
    }
}
