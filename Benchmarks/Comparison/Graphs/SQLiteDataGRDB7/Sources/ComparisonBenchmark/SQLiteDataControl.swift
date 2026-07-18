import ComparisonBenchmarkSupport
import GRDB
import SQLiteData

@Table("Orders")
struct SQLiteDataOrder: ComparisonBenchmarkOrderRow {
    @Column("OrderID", primaryKey: true)
    var orderID: Int
    @Column("CustomerID")
    var customerID: String?
    @Column("EmployeeID")
    var employeeID: Int?
    @Column("OrderDate")
    var orderDate: String?
    @Column("RequiredDate")
    var requiredDate: String?
    @Column("ShippedDate")
    var shippedDate: String?
    @Column("ShipVia")
    var shipVia: Int?
    @Column("Freight")
    var freight: Double?
    @Column("ShipName")
    var shipName: String?
    @Column("ShipAddress")
    var shipAddress: String?
    @Column("ShipCity")
    var shipCity: String?
    @Column("ShipRegion")
    var shipRegion: String?
    @Column("ShipPostalCode")
    var shipPostalCode: String?
    @Column("ShipCountry")
    var shipCountry: String?
}

final class SQLiteDataControl {
    private let database: GRDB.DatabaseQueue

    init(databasePath: String) throws {
        var configuration = GRDB.Configuration()
        configuration.readonly = true
        database = try GRDB.DatabaseQueue(
            path: databasePath,
            configuration: configuration
        )
    }

    func run(configuration: ComparisonBenchmarkConfiguration) throws {
        let query = SQLiteDataOrder.all
        try ComparisonBenchmarkDriver.runRows(
            configuration: configuration,
            fetch: {
                try database.read { db in
                    try query.fetchAll(db)
                }
            }
        )
    }
}
