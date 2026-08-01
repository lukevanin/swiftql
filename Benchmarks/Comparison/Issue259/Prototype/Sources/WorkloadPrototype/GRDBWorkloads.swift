import Foundation
import GRDB

private struct GRDBPrototypeOrder: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "Orders"

    var orderID: Int
    var customerID: String?
    var employeeID: Int?
    var orderDate: String?
    var requiredDate: String?
    var shippedDate: String?
    var shipVia: Int?
    var freight: Double?
    var shipName: String?
    var shipAddress: String?
    var shipCity: String?
    var shipRegion: String?
    var shipPostalCode: String?
    var shipCountry: String?
}

private struct GRDBPrototypeWriteRow: Codable, PersistableRecord {
    static let databaseTableName = PrototypeConstants.scratchTableName

    var id: Int
    var name: String
    var amount: Double
}

/// GRDB adapter.
///
/// The point lookup and the write use GRDB's own typed record surface. The
/// join/aggregate uses `Row.fetchAll(_:sql:)` because GRDB's typed association
/// path needs `belongsTo` associations declared on the record types, which
/// changes the *declaration* surface rather than the query surface and so is
/// not the same tier as SwiftQL's inline typed join. The applicability matrix
/// in README.md records that difference; it is not hidden here.
final class GRDBPrototypeAdapter {
    private let queue: DatabaseQueue

    init(databaseURL: URL, writable: Bool) throws {
        var configuration = GRDB.Configuration()
        configuration.readonly = !writable
        queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    }

    func pointLookup(iteration: Int) throws -> PrototypeOrder? {
        let keys = PrototypeConstants.lookupKeys
        let key = keys[iteration % keys.count]
        return try queue.read { database in
            guard let record = try GRDBPrototypeOrder
                .filter(Column("OrderID") == key)
                .fetchOne(database)
            else {
                return nil
            }
            return PrototypeOrder(
                orderID: record.orderID,
                customerID: record.customerID,
                employeeID: record.employeeID,
                orderDate: record.orderDate,
                requiredDate: record.requiredDate,
                shippedDate: record.shippedDate,
                shipVia: record.shipVia,
                freight: record.freight,
                shipName: record.shipName,
                shipAddress: record.shipAddress,
                shipCity: record.shipCity,
                shipRegion: record.shipRegion,
                shipPostalCode: record.shipPostalCode,
                shipCountry: record.shipCountry
            )
        }
    }

    func joinAggregate() throws -> [PrototypeCountryVolume] {
        try queue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT "Customers"."Country" AS country,
                           COUNT("Orders"."OrderID") AS orderCount,
                           TOTAL("Orders"."Freight") AS freightTotal
                    FROM "Orders"
                    INNER JOIN "Customers"
                        ON "Customers"."CustomerID" = "Orders"."CustomerID"
                    GROUP BY "Customers"."Country"
                    ORDER BY "Customers"."Country" ASC
                    """
            ).map { row in
                PrototypeCountryVolume(
                    country: row["country"],
                    orderCount: row["orderCount"],
                    freightTotal: row["freightTotal"]
                )
            }
        }
    }

    func transactionalWrite() throws -> Int {
        let batch = PrototypeConstants.writeBatch
        try queue.inTransaction { database in
            for row in batch {
                try GRDBPrototypeWriteRow(
                    id: row.id,
                    name: row.name,
                    amount: row.amount
                ).insert(database)
            }
            return .commit
        }
        return batch.count
    }
}
