import Foundation
import GRDB
import SwiftQL

@SQLTable(name: "Orders")
struct SwiftQLPrototypeOrder {
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

@SQLTable(name: "Customers")
struct SwiftQLPrototypeCustomer {
    var customerID: String
    var country: String?
}

@SQLTable(name: "Issue259PrototypeWrites")
struct SwiftQLPrototypeWriteRow {
    var id: Int
    var name: String
    var amount: Double
}

@SQLResult
struct SwiftQLPrototypeCountryVolume {
    var country: String?
    var orderCount: Int
    var freightTotal: Double
}

extension GRDBDatabase {

    @SQLQuery
    func prototypeOrder(orderID: Int) -> SwiftQLPrototypeOrder? {
        sqlResult { schema in
            let orders = schema.table(SwiftQLPrototypeOrder.self)
            Select(orders)
            From(orders)
            Where(orders.orderID == orderID)
        }
    }

    @SQLQuery
    func prototypeCountryVolumes() -> [SwiftQLPrototypeCountryVolume] {
        sqlResult { schema in
            let orders = schema.table(SwiftQLPrototypeOrder.self)
            let customers = schema.table(SwiftQLPrototypeCustomer.self)
            Select(SwiftQLPrototypeCountryVolume.columns(
                country: customers.country,
                orderCount: orders.orderID.count(),
                freightTotal: orders.freight.total()
            ))
            From(orders)
            Join.Inner(customers, on: customers.customerID == orders.customerID)
            GroupBy(customers.country)
            OrderBy(customers.country.ascending())
        }
    }
}

/// SwiftQL adapter. Every workload uses SwiftQL's own typed surface: declared
/// queries for the two reads and `withTransaction` plus `sqlInsert` for the
/// write.
final class SwiftQLPrototypeAdapter {
    private let database: GRDBDatabase

    init(databaseURL: URL, writable: Bool) throws {
        var configuration = GRDB.Configuration()
        configuration.readonly = !writable
        database = try GRDBDatabase(
            url: databaseURL,
            configuration: configuration,
            logger: nil
        )
    }

    func pointLookup(iteration: Int) throws -> PrototypeOrder? {
        let keys = PrototypeConstants.lookupKeys
        let key = keys[iteration % keys.count]
        guard let row = try database.fetchPrototypeOrder(orderID: key) else {
            return nil
        }
        return PrototypeOrder(
            orderID: row.orderID,
            customerID: row.customerID,
            employeeID: row.employeeID,
            orderDate: row.orderDate,
            requiredDate: row.requiredDate,
            shippedDate: row.shippedDate,
            shipVia: row.shipVia,
            freight: row.freight,
            shipName: row.shipName,
            shipAddress: row.shipAddress,
            shipCity: row.shipCity,
            shipRegion: row.shipRegion,
            shipPostalCode: row.shipPostalCode,
            shipCountry: row.shipCountry
        )
    }

    func joinAggregate() throws -> [PrototypeCountryVolume] {
        try database.fetchPrototypeCountryVolumes().map { row in
            PrototypeCountryVolume(
                country: row.country,
                orderCount: row.orderCount,
                freightTotal: row.freightTotal
            )
        }
    }

    func transactionalWrite() throws -> Int {
        let batch = PrototypeConstants.writeBatch
        try database.withTransaction { scope in
            for row in batch {
                let record = SwiftQLPrototypeWriteRow(
                    id: row.id,
                    name: row.name,
                    amount: row.amount
                )
                try scope.makeRequest(with: sqlInsert(record)).execute()
            }
        }
        return batch.count
    }
}
