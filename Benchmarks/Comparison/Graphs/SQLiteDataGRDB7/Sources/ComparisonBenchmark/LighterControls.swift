import ComparisonBenchmarkSupport
import Foundation
import Lighter
import SQLite3

private func checksumGeneratedOrders(_ rows: [Orders]) -> UInt64 {
    var checksum = ComparisonBenchmarkChecksum()
    for row in rows {
        checksum.combine(row.id)
        checksum.combine(row.customerID)
        checksum.combine(row.employeeID)
        checksum.combine(row.orderDate.map(\.timeIntervalSinceReferenceDate))
        checksum.combine(row.requiredDate.map(\.timeIntervalSinceReferenceDate))
        checksum.combine(row.shippedDate.map(\.timeIntervalSinceReferenceDate))
        checksum.combine(row.shipVia)
        checksum.combine(row.freight.map { NSDecimalNumber(decimal: $0).doubleValue })
        checksum.combine(row.shipName)
        checksum.combine(row.shipAddress)
        checksum.combine(row.shipCity)
        checksum.combine(row.shipRegion)
        checksum.combine(row.shipPostalCode)
        checksum.combine(row.shipCountry)
    }
    return checksum.value
}

enum LighterControl {
    static func run(configuration: ComparisonBenchmarkConfiguration) throws {
        guard let database = NorthwindPerformance.module else {
            throw ComparisonBenchmarkError.missingFixture(
                "NorthwindPerformance.module"
            )
        }
        try ComparisonBenchmarkDriver.runCustom(
            configuration: configuration,
            fetch: { try database.orders.fetch() },
            checksum: checksumGeneratedOrders
        )
    }
}

final class GeneratedRawSQLiteControl {
    private var database: OpaquePointer?

    init(databasePath: String) throws {
        let result = sqlite3_open_v2(
            databasePath,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard result == SQLITE_OK else {
            let message = database.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "SQLite did not return a database handle"
            if let database {
                sqlite3_close(database)
            }
            database = nil
            throw ComparisonBenchmarkError.sqlite(message)
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func run(configuration: ComparisonBenchmarkConfiguration) throws {
        guard let database else {
            throw ComparisonBenchmarkError.sqlite("raw connection is closed")
        }
        try ComparisonBenchmarkDriver.runCustom(
            configuration: configuration,
            fetch: { Orders.fetch(from: database) ?? [] },
            checksum: checksumGeneratedOrders
        )
    }
}
