import Foundation
import GRDB
import SQLite

private enum OrdersWorkload {
    static let sql = """
        SELECT
            "OrderID",
            "CustomerID",
            "EmployeeID",
            "OrderDate",
            "RequiredDate",
            "ShippedDate",
            "ShipVia",
            "Freight",
            "ShipName",
            "ShipAddress",
            "ShipCity",
            "ShipRegion",
            "ShipPostalCode",
            "ShipCountry"
        FROM "Orders"
        """
}

private struct BenchmarkOrder: ComparisonBenchmarkOrderRow {
    let orderID: Int
    let customerID: String?
    let employeeID: Int?
    let orderDate: String?
    let requiredDate: String?
    let shippedDate: String?
    let shipVia: Int?
    let freight: Double?
    let shipName: String?
    let shipAddress: String?
    let shipCity: String?
    let shipRegion: String?
    let shipPostalCode: String?
    let shipCountry: String?
}

extension BenchmarkOrder: FetchableRecord {
    init(row: GRDB.Row) {
        orderID = row[0]
        customerID = row[1]
        employeeID = row[2]
        orderDate = row[3]
        requiredDate = row[4]
        shippedDate = row[5]
        shipVia = row[6]
        freight = row[7]
        shipName = row[8]
        shipAddress = row[9]
        shipCity = row[10]
        shipRegion = row[11]
        shipPostalCode = row[12]
        shipCountry = row[13]
    }
}

private struct GRDBCodableOrder: Decodable, FetchableRecord, ComparisonBenchmarkOrderRow {
    let orderID: Int
    let customerID: String?
    let employeeID: Int?
    let orderDate: String?
    let requiredDate: String?
    let shippedDate: String?
    let shipVia: Int?
    let freight: Double?
    let shipName: String?
    let shipAddress: String?
    let shipCity: String?
    let shipRegion: String?
    let shipPostalCode: String?
    let shipCountry: String?

    enum CodingKeys: String, CodingKey {
        case orderID = "OrderID"
        case customerID = "CustomerID"
        case employeeID = "EmployeeID"
        case orderDate = "OrderDate"
        case requiredDate = "RequiredDate"
        case shippedDate = "ShippedDate"
        case shipVia = "ShipVia"
        case freight = "Freight"
        case shipName = "ShipName"
        case shipAddress = "ShipAddress"
        case shipCity = "ShipCity"
        case shipRegion = "ShipRegion"
        case shipPostalCode = "ShipPostalCode"
        case shipCountry = "ShipCountry"
    }
}

private func makeReadOnlyGRDBQueue(path: String) throws -> GRDB.DatabaseQueue {
    var configuration = GRDB.Configuration()
    configuration.readonly = true
    return try GRDB.DatabaseQueue(path: path, configuration: configuration)
}

public final class GRDBCodableControl {
    private let database: GRDB.DatabaseQueue

    public init(databasePath: String) throws {
        database = try makeReadOnlyGRDBQueue(path: databasePath)
    }

    public func run(configuration: ComparisonBenchmarkConfiguration) throws {
        try ComparisonBenchmarkDriver.runRows(configuration: configuration) {
            try database.read { db in
                try GRDBCodableOrder.fetchAll(db, sql: OrdersWorkload.sql)
            }
        }
    }
}

public final class GRDBManualControl {
    private let database: GRDB.DatabaseQueue

    public init(databasePath: String) throws {
        database = try makeReadOnlyGRDBQueue(path: databasePath)
    }

    public func run(configuration: ComparisonBenchmarkConfiguration) throws {
        try ComparisonBenchmarkDriver.runRows(configuration: configuration) {
            try database.read { db in
                try BenchmarkOrder.fetchAll(db, sql: OrdersWorkload.sql)
            }
        }
    }
}

private enum SQLiteSwiftOrdersSchema {
    static let table = SQLite.Table("Orders")
    static let orderID = SQLite.Expression<Int64>("OrderID")
    static let customerID = SQLite.Expression<String?>("CustomerID")
    static let employeeID = SQLite.Expression<Int64?>("EmployeeID")
    static let orderDate = SQLite.Expression<String?>("OrderDate")
    static let requiredDate = SQLite.Expression<String?>("RequiredDate")
    static let shippedDate = SQLite.Expression<String?>("ShippedDate")
    static let shipVia = SQLite.Expression<Int64?>("ShipVia")
    // The fixture's NUMERIC affinity stores integral freight values as INTEGER.
    // SQLite.swift's typed Double decoder accepts only REAL bindings, so the
    // typed query normalizes this one selected column without changing shape.
    static let freight = SQLite.Expression<Double?>(
        literal: "CAST(\"Freight\" AS REAL)"
    )
    static let shipName = SQLite.Expression<String?>("ShipName")
    static let shipAddress = SQLite.Expression<String?>("ShipAddress")
    static let shipCity = SQLite.Expression<String?>("ShipCity")
    static let shipRegion = SQLite.Expression<String?>("ShipRegion")
    static let shipPostalCode = SQLite.Expression<String?>("ShipPostalCode")
    static let shipCountry = SQLite.Expression<String?>("ShipCountry")
    static let query = table.select(
        orderID,
        customerID,
        employeeID,
        orderDate,
        requiredDate,
        shippedDate,
        shipVia,
        freight,
        shipName,
        shipAddress,
        shipCity,
        shipRegion,
        shipPostalCode,
        shipCountry
    )
}

public final class SQLiteSwiftTypedControl {
    private let database: SQLite.Connection

    public init(databasePath: String) throws {
        database = try SQLite.Connection(databasePath, readonly: true)
    }

    public func run(configuration: ComparisonBenchmarkConfiguration) throws {
        try ComparisonBenchmarkDriver.runRows(configuration: configuration) {
            let iterator = try database.prepareRowIterator(SQLiteSwiftOrdersSchema.query)
            return try iterator.map { row in
                BenchmarkOrder(
                    orderID: Int(try row.get(SQLiteSwiftOrdersSchema.orderID)),
                    customerID: try row.get(SQLiteSwiftOrdersSchema.customerID),
                    employeeID: try row.get(SQLiteSwiftOrdersSchema.employeeID).map(Int.init),
                    orderDate: try row.get(SQLiteSwiftOrdersSchema.orderDate),
                    requiredDate: try row.get(SQLiteSwiftOrdersSchema.requiredDate),
                    shippedDate: try row.get(SQLiteSwiftOrdersSchema.shippedDate),
                    shipVia: try row.get(SQLiteSwiftOrdersSchema.shipVia).map(Int.init),
                    freight: try row.get(SQLiteSwiftOrdersSchema.freight),
                    shipName: try row.get(SQLiteSwiftOrdersSchema.shipName),
                    shipAddress: try row.get(SQLiteSwiftOrdersSchema.shipAddress),
                    shipCity: try row.get(SQLiteSwiftOrdersSchema.shipCity),
                    shipRegion: try row.get(SQLiteSwiftOrdersSchema.shipRegion),
                    shipPostalCode: try row.get(SQLiteSwiftOrdersSchema.shipPostalCode),
                    shipCountry: try row.get(SQLiteSwiftOrdersSchema.shipCountry)
                )
            }
        }
    }
}

public final class SQLiteSwiftManualControl {
    private let database: SQLite.Connection

    public init(databasePath: String) throws {
        database = try SQLite.Connection(databasePath, readonly: true)
    }

    public func run(configuration: ComparisonBenchmarkConfiguration) throws {
        try ComparisonBenchmarkDriver.runRows(configuration: configuration) {
            let statement = try database.prepare(OrdersWorkload.sql)
            var rows: [BenchmarkOrder] = []
            rows.reserveCapacity(ComparisonBenchmarkConstants.expectedRowCount)
            while let values = try statement.failableNext() {
                guard values.count == ComparisonBenchmarkConstants.selectedColumnCount else {
                    throw ComparisonBenchmarkError.sqlite(
                        "SQLite.swift manual row had \(values.count) columns"
                    )
                }
                rows.append(
                    BenchmarkOrder(
                        orderID: try Self.requiredInteger(values[0], column: 0),
                        customerID: try Self.string(values[1], column: 1),
                        employeeID: try Self.integer(values[2], column: 2),
                        orderDate: try Self.string(values[3], column: 3),
                        requiredDate: try Self.string(values[4], column: 4),
                        shippedDate: try Self.string(values[5], column: 5),
                        shipVia: try Self.integer(values[6], column: 6),
                        freight: try Self.double(values[7], column: 7),
                        shipName: try Self.string(values[8], column: 8),
                        shipAddress: try Self.string(values[9], column: 9),
                        shipCity: try Self.string(values[10], column: 10),
                        shipRegion: try Self.string(values[11], column: 11),
                        shipPostalCode: try Self.string(values[12], column: 12),
                        shipCountry: try Self.string(values[13], column: 13)
                    )
                )
            }
            return rows
        }
    }

    private static func requiredInteger(_ value: Binding?, column: Int) throws -> Int {
        guard let value = try integer(value, column: column) else {
            throw ComparisonBenchmarkError.unexpectedSQLiteValue(
                column: column,
                value: "NULL"
            )
        }
        return value
    }

    private static func integer(_ value: Binding?, column: Int) throws -> Int? {
        switch value {
        case nil:
            return nil
        case let value as Int64:
            return Int(value)
        case let value as Int:
            return value
        default:
            throw ComparisonBenchmarkError.unexpectedSQLiteValue(
                column: column,
                value: String(describing: value)
            )
        }
    }

    private static func double(_ value: Binding?, column: Int) throws -> Double? {
        switch value {
        case nil:
            return nil
        case let value as Double:
            return value
        case let value as Int64:
            return Double(value)
        case let value as Int:
            return Double(value)
        default:
            throw ComparisonBenchmarkError.unexpectedSQLiteValue(
                column: column,
                value: String(describing: value)
            )
        }
    }

    private static func string(_ value: Binding?, column: Int) throws -> String? {
        switch value {
        case nil:
            return nil
        case let value as String:
            return value
        default:
            throw ComparisonBenchmarkError.unexpectedSQLiteValue(
                column: column,
                value: String(describing: value)
            )
        }
    }
}
