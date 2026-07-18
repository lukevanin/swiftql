import ComparisonBenchmarkSupport
import Foundation
import GRDB
import SwiftQL

@SQLTable(name: "Orders")
struct SwiftQLOrder: ComparisonBenchmarkOrderRow {
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

final class SwiftQLControl {
    private let database: GRDBDatabase

    init(databaseURL: URL) throws {
        var configuration = GRDB.Configuration()
        configuration.readonly = true
        database = try GRDBDatabase(
            url: databaseURL,
            configuration: configuration,
            logger: nil
        )
    }

    func run(configuration: ComparisonBenchmarkConfiguration) throws {
        let statement = sql { schema in
            let orders = schema.table(SwiftQLOrder.self)
            Select(orders)
            From(orders)
        }
        let request = database.makeRequest(with: statement)
        try ComparisonBenchmarkDriver.runRows(
            configuration: configuration,
            fetch: { try request.fetchAll() }
        )
    }
}
