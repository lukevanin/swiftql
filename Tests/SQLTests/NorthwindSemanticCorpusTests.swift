import Foundation
import GRDB
import SwiftQL
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteConformanceFixtures
import XCTest


@SQLTable(name: "Customers")
struct NorthwindCorpusCustomer: Equatable {
    let customerID: String
    let companyName: String
    let contactName: String?
    let city: String?
    let region: String?
    let country: String?
}


@SQLTable(name: "Orders")
struct NorthwindCorpusOrder: Equatable {
    let orderID: Int
    let customerID: String
    let employeeID: Int
    let shippedDate: String?
    let shipRegion: String?
}


@SQLTable(name: "Employees")
struct NorthwindCorpusEmployee: Equatable {
    let employeeID: Int
    let lastName: String
    let firstName: String
    let photo: Data
    let reportsTo: Int?
}


@SQLTable(name: "Products")
struct NorthwindCorpusProduct: Equatable {
    let productID: Int
    let productName: String
    let unitPrice: Double
}


@SQLTable(name: "Order Details")
struct NorthwindCorpusOrderDetail: Equatable {
    let orderID: Int
    let productID: Int
    let unitPrice: Double
    let quantity: Int
    let discount: Double
}


@SQLTable(name: "Suppliers")
struct NorthwindCorpusSupplier: Equatable {
    let supplierID: Int
    let companyName: String
    let contactName: String?
    let city: String?
}


@SQLTable(name: "Order Subtotals")
struct NorthwindCorpusOrderSubtotalView: Equatable {
    let orderID: Int
    let subtotal: Double
}


@SQLResult
struct NorthwindCorpusShippingRow: Equatable {
    let orderID: Int
    let shippedDate: String?
    let shipRegion: String?
}


@SQLResult
struct NorthwindCorpusCustomerTextRow: Equatable {
    let customerID: String
    let companyName: String
    let city: String?
}


@SQLResult
struct NorthwindCorpusEmployeePhotoRow: Equatable {
    let employeeID: Int
    let photo: Data
}


@SQLResult
struct NorthwindCorpusOrderLine: Equatable {
    let orderID: Int
    let customerID: String
    let companyName: String
    let employeeID: Int
    let employeeLastName: String
    let productID: Int
    let productName: String
    let unitPrice: Double
    let quantity: Int
    let discount: Double
}


@SQLResult
struct NorthwindCorpusEmployeeManagerRow: Equatable {
    let employeeID: Int
    let employeeLastName: String
    let managerID: Int?
    let managerLastName: String?
}


@SQLResult
struct NorthwindCorpusCustomerOrderVolume: Equatable {
    let customerID: String
    let orderCount: Int
}


@SQLResult
struct NorthwindCorpusNullableAggregate: Equatable {
    let total: Double?
}


@SQLResult
struct NorthwindCorpusProductRow: Equatable {
    let productID: Int
    let productName: String
    let unitPrice: Double
}


@SQLResult
struct NorthwindCorpusContactLocation: Equatable {
    let city: String?
    let companyName: String
    let contactName: String?
    let relationship: String
}


@SQLResult
struct NorthwindCorpusOrderSubtotal: Equatable {
    let orderID: Int
    let subtotal: Double
}


final class NorthwindSemanticCorpusTests: XCTestCase {

    private enum RollbackSignal: Error, Equatable {
        case requested
    }

    private struct SemanticOperationFailure: Error, LocalizedError {
        let context: String
        let underlyingError: Error

        var errorDescription: String? {
            "\(context); underlying-error=\(String(describing: underlyingError))"
        }
    }

    private var fixtureEvidence = [
        "fixture-revision=\(NorthwindFixture.metadata.upstreamCommit)",
        "fixture-sha256=\(NorthwindFixture.metadata.databaseSHA256)",
        "sqlite-source-id=unavailable-before-validation",
    ].joined(separator: "; ")

    override func setUpWithError() throws {
        try super.setUpWithError()
        let validation = try withEvidence(
            .pinnedCorpus,
            "canonical fixture validation"
        ) {
            try NorthwindFixture.validateCanonical()
        }
        fixtureEvidence = [
            "fixture-revision=\(NorthwindFixture.metadata.upstreamCommit)",
            "fixture-sha256=\(NorthwindFixture.metadata.databaseSHA256)",
            "sqlite-source-id=\(validation.sqliteSourceID)",
        ].joined(separator: "; ")
    }

    func testPinnedCorpusSelectionsQuotedIdentifiersAndValues() throws {
        let pinned = SQLiteNorthwindConformanceCaseID.pinnedCorpus
        let validation = try withEvidence(pinned, "canonical fixture validation") {
            try NorthwindFixture.validateCanonical()
        }
        XCTAssertEqual(
            validation.applicationTables.count,
            13,
            oracle(pinned, "pinned fixture schema")
        )
        XCTAssertEqual(validation.views.count, 17, oracle(pinned, "pinned fixture schema"))
        XCTAssertEqual(
            validation.rowCounts["Customers"],
            SQLiteNorthwindConformanceFixtures.customerCount,
            oracle(pinned, "pinned fixture metadata")
        )
        XCTAssertEqual(
            validation.rowCounts["Orders"],
            SQLiteNorthwindConformanceFixtures.orderCount,
            oracle(pinned, "pinned fixture metadata")
        )
        XCTAssertEqual(
            validation.rowCounts["Order Details"],
            SQLiteNorthwindConformanceFixtures.orderDetailCount,
            oracle(pinned, "pinned fixture metadata")
        )
        XCTAssertEqual(
            validation.rowCounts["Products"],
            SQLiteNorthwindConformanceFixtures.productCount,
            oracle(pinned, "pinned fixture metadata")
        )

        let fixture = try makeReadOnlyFixture(
            for: pinned,
            source: "read-only fixture for pinned corpus selections"
        )
        defer { try? fixture.pool.close() }

        let customerCountStatement = sql { schema in
            let customers = schema.table(NorthwindCorpusCustomer.self)
            Select(customers.customerID.count())
            From(customers)
        }
        let orderCountStatement = sql { schema in
            let orders = schema.table(NorthwindCorpusOrder.self)
            Select(orders.orderID.count())
            From(orders)
        }
        let detailCountStatement = sql { schema in
            let details = schema.table(NorthwindCorpusOrderDetail.self)
            Select(details.orderID.count())
            From(details)
        }
        let productCountStatement = sql { schema in
            let products = schema.table(NorthwindCorpusProduct.self)
            Select(products.productID.count())
            From(products)
        }
        let typedCounts = [
            try XCTUnwrap(
                withEvidence(pinned, "typed Customers count fetch") {
                    try fixture.database.makeRequest(with: customerCountStatement).fetchOne()
                },
                oracle(pinned, "typed Customers count")
            ),
            try XCTUnwrap(
                withEvidence(pinned, "typed Orders count fetch") {
                    try fixture.database.makeRequest(with: orderCountStatement).fetchOne()
                },
                oracle(pinned, "typed Orders count")
            ),
            try XCTUnwrap(
                withEvidence(pinned, "typed Order Details count fetch") {
                    try fixture.database.makeRequest(with: detailCountStatement).fetchOne()
                },
                oracle(pinned, "typed Order Details count")
            ),
            try XCTUnwrap(
                withEvidence(pinned, "typed Products count fetch") {
                    try fixture.database.makeRequest(with: productCountStatement).fetchOne()
                },
                oracle(pinned, "typed Products count")
            ),
        ]
        let rawCounts = try withEvidence(pinned, "raw GRDB count SQL fetch") {
            try fixture.pool.read { database in
                try ["Customers", "Orders", "Order Details", "Products"].map { table in
                    try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM \(table.quotedDatabaseIdentifier)"
                    )!
                }
            }
        }
        XCTAssertEqual(typedCounts, rawCounts, oracle(pinned, "raw GRDB count SQL"))

        let detailStatement = sql { schema in
            let details = schema.table(NorthwindCorpusOrderDetail.self)
            Select(details)
            From(details)
            Where(details.orderID == SQLiteNorthwindConformanceFixtures.sentinelOrderID)
            OrderBy(details.productID.ascending())
        }
        let typedDetails = try withEvidence(.quotedOrderDetails, "typed quoted-table fetch") {
            try fixture.database.makeRequest(with: detailStatement).fetchAll()
        }
        let rawDetails = try withEvidence(
            .quotedOrderDetails,
            "raw GRDB SQL with quoted table name fetch"
        ) {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT OrderID AS orderID, ProductID AS productID,
                               UnitPrice AS unitPrice, Quantity AS quantity,
                               Discount AS discount
                        FROM "Order Details"
                        WHERE OrderID = ?
                        ORDER BY ProductID
                        """,
                    arguments: [SQLiteNorthwindConformanceFixtures.sentinelOrderID]
                ).map(NorthwindCorpusOrderDetail.init(raw:))
            }
        }
        XCTAssertEqual(
            typedDetails,
            rawDetails,
            oracle(.quotedOrderDetails, "raw GRDB SQL with quoted table name")
        )
        let expectedDetails = SQLiteNorthwindConformanceFixtures.sentinelOrderDetails.map {
            NorthwindCorpusOrderDetail(
                orderID: SQLiteNorthwindConformanceFixtures.sentinelOrderID,
                productID: $0.productID,
                unitPrice: $0.unitPrice,
                quantity: $0.quantity,
                discount: $0.discount
            )
        }
        XCTAssertEqual(
            typedDetails,
            expectedDetails,
            oracle(.orderDetailsCompoundKey, "pinned OrderID/ProductID compound-key rows")
        )
        let compoundPrimaryKey = try withEvidence(
            .orderDetailsCompoundKey,
            "raw GRDB PRAGMA table_info fetch"
        ) {
            try fixture.pool.read { database in
                try Row.fetchAll(database, sql: "PRAGMA table_info('Order Details')")
                    .compactMap { row -> String? in
                        let ordinal: Int = row["pk"]
                        guard ordinal > 0 else { return nil }
                        let name: String = row["name"]
                        return "\(ordinal):\(name)"
                    }
                    .sorted()
            }
        }
        XCTAssertEqual(
            compoundPrimaryKey,
            ["1:OrderID", "2:ProductID"],
            oracle(.orderDetailsCompoundKey, "raw GRDB PRAGMA table_info primary-key ordinals")
        )

        let shippingStatement = sql { schema in
            let orders = schema.table(NorthwindCorpusOrder.self)
            let row = NorthwindCorpusShippingRow.columns(
                orderID: orders.orderID,
                shippedDate: orders.shippedDate,
                shipRegion: orders.shipRegion
            )
            Select(row)
            From(orders)
            Where(orders.orderID == SQLiteNorthwindConformanceFixtures.nullableShippingOrderID)
        }
        let typedShipping = try XCTUnwrap(
            withEvidence(.nullableShipping, "typed nullable shipping fetch") {
                try fixture.database.makeRequest(with: shippingStatement).fetchOne()
            },
            oracle(.nullableShipping, "typed nullable shipping SELECT")
        )
        let rawShippingRow = try withEvidence(.nullableShipping, "raw GRDB nullable shipping fetch") {
            try fixture.pool.read { database in
                try Row.fetchOne(
                    database,
                    sql: """
                        SELECT OrderID AS orderID, ShippedDate AS shippedDate,
                               ShipRegion AS shipRegion
                        FROM Orders WHERE OrderID = ?
                        """,
                    arguments: [SQLiteNorthwindConformanceFixtures.nullableShippingOrderID]
                )
            }
        }
        let rawShipping = try XCTUnwrap(
            rawShippingRow,
            oracle(.nullableShipping, "raw GRDB nullable shipping SELECT")
        ).asShippingRow
        XCTAssertEqual(
            typedShipping,
            rawShipping,
            oracle(.nullableShipping, "raw GRDB nullable-column SQL")
        )
        XCTAssertNil(
            typedShipping.shippedDate,
            oracle(.nullableShipping, "pinned NULL ShippedDate sentinel")
        )

        let customerTextStatement = sql { schema in
            let customers = schema.table(NorthwindCorpusCustomer.self)
            Select(NorthwindCorpusCustomerTextRow.columns(
                customerID: customers.customerID,
                companyName: customers.companyName,
                city: customers.city
            ))
            From(customers)
            Where(customers.customerID == SQLiteNorthwindConformanceFixtures.unicodeCustomerID)
        }
        let productTextStatement = sql { schema in
            let products = schema.table(NorthwindCorpusProduct.self)
            Select(NorthwindCorpusProductRow.columns(
                productID: products.productID,
                productName: products.productName,
                unitPrice: products.unitPrice
            ))
            From(products)
            Where(products.productID == SQLiteNorthwindConformanceFixtures.unicodeProductID)
        }
        let employeePhotoStatement = sql { schema in
            let employees = schema.table(NorthwindCorpusEmployee.self)
            Select(NorthwindCorpusEmployeePhotoRow.columns(
                employeeID: employees.employeeID,
                photo: employees.photo
            ))
            From(employees)
            Where(employees.employeeID == SQLiteNorthwindConformanceFixtures.blobEmployeeID)
        }
        let typedCustomer = try XCTUnwrap(
            withEvidence(.unicodeBlob, "typed Unicode customer fetch") {
                try fixture.database.makeRequest(with: customerTextStatement).fetchOne()
            },
            oracle(.unicodeBlob, "typed Unicode customer SELECT")
        )
        let typedProduct = try XCTUnwrap(
            withEvidence(.unicodeBlob, "typed Unicode product fetch") {
                try fixture.database.makeRequest(with: productTextStatement).fetchOne()
            },
            oracle(.unicodeBlob, "typed Unicode product SELECT")
        )
        let typedEmployee = try XCTUnwrap(
            withEvidence(.unicodeBlob, "typed employee BLOB fetch") {
                try fixture.database.makeRequest(with: employeePhotoStatement).fetchOne()
            },
            oracle(.unicodeBlob, "typed employee BLOB SELECT")
        )
        let rawValueRows = try withEvidence(.unicodeBlob, "raw GRDB Unicode and BLOB fetches") {
            try fixture.pool.read { database in
                let customer = try Row.fetchOne(
                    database,
                    sql: "SELECT CustomerID AS customerID, CompanyName AS companyName, City AS city FROM Customers WHERE CustomerID = ?",
                    arguments: [SQLiteNorthwindConformanceFixtures.unicodeCustomerID]
                )
                let product = try Row.fetchOne(
                    database,
                    sql: "SELECT ProductID AS productID, ProductName AS productName, UnitPrice AS unitPrice FROM Products WHERE ProductID = ?",
                    arguments: [SQLiteNorthwindConformanceFixtures.unicodeProductID]
                )
                let employee = try Row.fetchOne(
                    database,
                    sql: "SELECT EmployeeID AS employeeID, Photo AS photo FROM Employees WHERE EmployeeID = ?",
                    arguments: [SQLiteNorthwindConformanceFixtures.blobEmployeeID]
                )
                return (customer, product, employee)
            }
        }
        let rawValues = (
            try XCTUnwrap(
                rawValueRows.0,
                oracle(.unicodeBlob, "raw GRDB Unicode customer SELECT")
            ).asCustomerTextRow,
            try XCTUnwrap(
                rawValueRows.1,
                oracle(.unicodeBlob, "raw GRDB Unicode product SELECT")
            ).asProductRow,
            try XCTUnwrap(
                rawValueRows.2,
                oracle(.unicodeBlob, "raw GRDB employee BLOB SELECT")
            ).asEmployeePhotoRow
        )
        XCTAssertEqual(typedCustomer, rawValues.0, oracle(.unicodeBlob, "raw GRDB text SQL"))
        XCTAssertEqual(typedProduct, rawValues.1, oracle(.unicodeBlob, "raw GRDB text SQL"))
        XCTAssertEqual(typedEmployee, rawValues.2, oracle(.unicodeBlob, "raw GRDB BLOB SQL"))
        XCTAssertEqual(
            typedCustomer.companyName,
            SQLiteNorthwindConformanceFixtures.unicodeCustomerCompany,
            oracle(.unicodeBlob, "pinned Unicode customer sentinel")
        )
        XCTAssertEqual(
            typedCustomer.city,
            SQLiteNorthwindConformanceFixtures.unicodeCustomerCity,
            oracle(.unicodeBlob, "pinned Unicode city sentinel")
        )
        XCTAssertEqual(
            typedProduct.productName,
            SQLiteNorthwindConformanceFixtures.unicodeProductName,
            oracle(.unicodeBlob, "pinned Unicode product sentinel")
        )
        XCTAssertEqual(
            typedEmployee.photo.count,
            SQLiteNorthwindConformanceFixtures.blobEmployeePhotoByteCount,
            oracle(.unicodeBlob, "pinned BLOB byte-count sentinel")
        )

        let paginationStatement = sql { schema in
            let products = schema.table(NorthwindCorpusProduct.self)
            Select(NorthwindCorpusProductRow.columns(
                productID: products.productID,
                productName: products.productName,
                unitPrice: products.unitPrice
            ))
            From(products)
            OrderBy(products.productName.ascending(), products.productID.ascending())
            Limit(7)
            Offset(11)
        }
        let typedPage = try withEvidence(.deterministicPagination, "typed ordered page fetch") {
            try fixture.database.makeRequest(with: paginationStatement).fetchAll()
        }
        let rawPage = try withEvidence(.deterministicPagination, "raw GRDB ordered page fetch") {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT ProductID AS productID, ProductName AS productName,
                               UnitPrice AS unitPrice
                        FROM Products
                        ORDER BY ProductName, ProductID
                        LIMIT 7 OFFSET 11
                        """
                ).map(\.asProductRow)
            }
        }
        XCTAssertEqual(
            typedPage,
            rawPage,
            oracle(.deterministicPagination, "raw GRDB ordered LIMIT/OFFSET SQL")
        )

        let emptyStatement = sql { schema in
            let customers = schema.table(NorthwindCorpusCustomer.self)
            Select(customers.customerID)
            From(customers)
            Where(customers.customerID == "__SWIFTQL_MISSING__")
            OrderBy(customers.customerID.ascending())
        }
        let typedEmpty = try withEvidence(.emptyResult, "typed empty-result fetch") {
            try fixture.database.makeRequest(with: emptyStatement).fetchAll()
        }
        let rawEmpty = try withEvidence(.emptyResult, "raw GRDB empty-result fetch") {
            try fixture.pool.read { database in
                try String.fetchAll(
                    database,
                    sql: "SELECT CustomerID FROM Customers WHERE CustomerID = ? ORDER BY CustomerID",
                    arguments: ["__SWIFTQL_MISSING__"]
                )
            }
        }
        XCTAssertEqual(typedEmpty, rawEmpty, oracle(.emptyResult, "raw GRDB empty-result SQL"))
        XCTAssertTrue(typedEmpty.isEmpty, oracle(.emptyResult, "pinned absent customer ID"))
    }

    func testJoinsAggregatesHavingAndPackagedView() throws {
        let fixture = try makeReadOnlyFixture(
            for: .customerOrderEmployeeProductJoin,
            source: "read-only fixture for joins and aggregates"
        )
        defer { try? fixture.pool.close() }

        let joinedStatement = sql { schema in
            let orders = schema.table(NorthwindCorpusOrder.self)
            let customers = schema.table(NorthwindCorpusCustomer.self)
            let employees = schema.table(NorthwindCorpusEmployee.self)
            let details = schema.table(NorthwindCorpusOrderDetail.self)
            let products = schema.table(NorthwindCorpusProduct.self)
            Select(NorthwindCorpusOrderLine.columns(
                orderID: orders.orderID,
                customerID: customers.customerID,
                companyName: customers.companyName,
                employeeID: employees.employeeID,
                employeeLastName: employees.lastName,
                productID: products.productID,
                productName: products.productName,
                unitPrice: details.unitPrice,
                quantity: details.quantity,
                discount: details.discount
            ))
            From(orders)
            Join.Inner(customers, on: customers.customerID == orders.customerID)
            Join.Inner(employees, on: employees.employeeID == orders.employeeID)
            Join.Inner(details, on: details.orderID == orders.orderID)
            Join.Inner(products, on: products.productID == details.productID)
            Where(orders.orderID == SQLiteNorthwindConformanceFixtures.sentinelOrderID)
            OrderBy(products.productID.ascending())
        }
        let typedLines = try withEvidence(
            .customerOrderEmployeeProductJoin,
            "typed five-table join fetch"
        ) {
            try fixture.database.makeRequest(with: joinedStatement).fetchAll()
        }
        let rawLines = try withEvidence(
            .customerOrderEmployeeProductJoin,
            "independent raw GRDB five-table join fetch"
        ) {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT o.OrderID AS orderID, c.CustomerID AS customerID,
                               c.CompanyName AS companyName, e.EmployeeID AS employeeID,
                               e.LastName AS employeeLastName, p.ProductID AS productID,
                               p.ProductName AS productName, d.UnitPrice AS unitPrice,
                               d.Quantity AS quantity, d.Discount AS discount
                        FROM Orders AS o
                        JOIN Customers AS c ON c.CustomerID = o.CustomerID
                        JOIN Employees AS e ON e.EmployeeID = o.EmployeeID
                        JOIN "Order Details" AS d ON d.OrderID = o.OrderID
                        JOIN Products AS p ON p.ProductID = d.ProductID
                        WHERE o.OrderID = ?
                        ORDER BY p.ProductID
                        """,
                    arguments: [SQLiteNorthwindConformanceFixtures.sentinelOrderID]
                ).map(\.asOrderLine)
            }
        }
        XCTAssertEqual(
            typedLines,
            rawLines,
            oracle(.customerOrderEmployeeProductJoin, "independent raw GRDB five-table join")
        )

        let managerStatement = sql { schema in
            let employees = schema.table(NorthwindCorpusEmployee.self)
            let managers = schema.nullableTable(NorthwindCorpusEmployee.self)
            Select(NorthwindCorpusEmployeeManagerRow.columns(
                employeeID: employees.employeeID,
                employeeLastName: employees.lastName,
                managerID: managers.employeeID,
                managerLastName: managers.lastName
            ))
            From(employees)
            Join.Left(managers, on: employees.reportsTo == managers.employeeID)
            OrderBy(employees.employeeID.ascending())
        }
        let typedManagers = try withEvidence(.leftNullManager, "typed self-left-join fetch") {
            try fixture.database.makeRequest(with: managerStatement).fetchAll()
        }
        let rawManagers = try withEvidence(
            .leftNullManager,
            "independent raw GRDB employee self-left-join fetch"
        ) {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT e.EmployeeID AS employeeID,
                               e.LastName AS employeeLastName,
                               m.EmployeeID AS managerID,
                               m.LastName AS managerLastName
                        FROM Employees AS e
                        LEFT JOIN Employees AS m ON e.ReportsTo = m.EmployeeID
                        ORDER BY e.EmployeeID
                        """
                ).map(\.asEmployeeManagerRow)
            }
        }
        XCTAssertEqual(
            typedManagers,
            rawManagers,
            oracle(.leftNullManager, "independent raw GRDB employee self-left-join")
        )
        XCTAssertTrue(
            typedManagers.contains { $0.managerID == nil && $0.managerLastName == nil },
            oracle(.leftNullManager, "pinned root employee with NULL manager")
        )

        let orderTotalStatement = sql { schema in
            let details = schema.table(NorthwindCorpusOrderDetail.self)
            let discountedLine = details.unitPrice
                * details.quantity.toDouble()
                * (1.0 - details.discount)
            Select(discountedLine.sumOrNull().coalesce(0))
            From(details)
            Where(details.orderID == SQLiteNorthwindConformanceFixtures.sentinelOrderID)
        }
        let typedTotal = try XCTUnwrap(
            withEvidence(.order10248Total, "typed discounted-line aggregate fetch") {
                try fixture.database.makeRequest(with: orderTotalStatement).fetchOne()
            },
            oracle(.order10248Total, "typed discounted-line aggregate")
        )
        let rawTotalValue = try withEvidence(.order10248Total, "raw GRDB aggregate fetch") {
            try fixture.pool.read { database in
                try Double.fetchOne(
                    database,
                    sql: """
                        SELECT COALESCE(SUM(UnitPrice * Quantity * (1.0 - Discount)), 0)
                        FROM "Order Details" WHERE OrderID = ?
                        """,
                    arguments: [SQLiteNorthwindConformanceFixtures.sentinelOrderID]
                )
            }
        }
        let rawTotal = try XCTUnwrap(
            rawTotalValue,
            oracle(.order10248Total, "raw GRDB discounted-line aggregate")
        )
        XCTAssertEqual(
            typedTotal,
            rawTotal,
            accuracy: 0.000_001,
            oracle(.order10248Total, "independent raw GRDB aggregate SQL")
        )
        XCTAssertEqual(
            typedTotal,
            SQLiteNorthwindConformanceFixtures.sentinelOrderSubtotal,
            accuracy: 0.000_001,
            oracle(.order10248Total, "pinned order 10248 subtotal")
        )

        let havingStatement = sql { schema in
            let orders = schema.table(NorthwindCorpusOrder.self)
            let row = NorthwindCorpusCustomerOrderVolume.columns(
                customerID: orders.customerID,
                orderCount: orders.orderID.count()
            )
            Select(row)
            From(orders)
            GroupBy(orders.customerID)
            Having(orders.orderID.count() >= 10)
            OrderBy(row.orderCount.descending(), row.customerID.ascending())
        }
        let typedHaving = try withEvidence(.groupedHaving, "typed GROUP BY/HAVING fetch") {
            try fixture.database.makeRequest(with: havingStatement).fetchAll()
        }
        let rawHaving = try withEvidence(.groupedHaving, "raw GRDB GROUP BY/HAVING fetch") {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT CustomerID AS customerID, COUNT(OrderID) AS orderCount
                        FROM Orders
                        GROUP BY CustomerID
                        HAVING COUNT(OrderID) >= 10
                        ORDER BY orderCount DESC, customerID ASC
                        """
                ).map(\.asCustomerOrderVolume)
            }
        }
        XCTAssertEqual(
            typedHaving,
            rawHaving,
            oracle(.groupedHaving, "independent raw GRDB GROUP BY/HAVING SQL")
        )

        let emptyAggregateStatement = sql { schema in
            let details = schema.table(NorthwindCorpusOrderDetail.self)
            Select(NorthwindCorpusNullableAggregate.columns(
                total: details.unitPrice.sumOrNull()
            ))
            From(details)
            Where(details.orderID == -1)
        }
        let typedEmptyAggregate = try XCTUnwrap(
            withEvidence(.emptyAggregateNull, "typed empty aggregate fetch") {
                try fixture.database.makeRequest(with: emptyAggregateStatement).fetchOne()
            },
            oracle(.emptyAggregateNull, "typed empty aggregate row")
        )
        let rawEmptyAggregateRow = try withEvidence(
            .emptyAggregateNull,
            "raw GRDB empty aggregate fetch"
        ) {
            try fixture.pool.read { database in
                try Row.fetchOne(
                    database,
                    sql: "SELECT SUM(UnitPrice) AS total FROM \"Order Details\" WHERE OrderID = -1"
                )
            }
        }
        let rawEmptyAggregate = try XCTUnwrap(
            rawEmptyAggregateRow,
            oracle(.emptyAggregateNull, "raw GRDB empty aggregate row")
        ).asNullableAggregate
        XCTAssertEqual(
            typedEmptyAggregate,
            rawEmptyAggregate,
            oracle(.emptyAggregateNull, "independent raw GRDB empty aggregate SQL")
        )
        XCTAssertNil(
            typedEmptyAggregate.total,
            oracle(.emptyAggregateNull, "SQLite SUM over empty input is NULL")
        )

        let viewStatement = sql { schema in
            let subtotals = schema.table(NorthwindCorpusOrderSubtotalView.self)
            Select(subtotals)
            From(subtotals)
            Where(subtotals.orderID == SQLiteNorthwindConformanceFixtures.sentinelOrderID)
            OrderBy(subtotals.orderID.ascending())
        }
        let typedView = try withEvidence(.packagedViewDecoding, "typed packaged-view fetch") {
            try fixture.database.makeRequest(with: viewStatement).fetchAll()
        }
        let rawView = try withEvidence(.packagedViewDecoding, "raw GRDB packaged-view fetch") {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT OrderID AS orderID, Subtotal AS subtotal
                        FROM "Order Subtotals"
                        WHERE OrderID = ?
                        ORDER BY OrderID
                        """,
                    arguments: [SQLiteNorthwindConformanceFixtures.sentinelOrderID]
                ).map(NorthwindCorpusOrderSubtotalView.init(raw:))
            }
        }
        XCTAssertEqual(
            typedView,
            rawView,
            oracle(.packagedViewDecoding, "independent raw read of packaged view")
        )
        XCTAssertEqual(
            try XCTUnwrap(
                typedView.first,
                oracle(.packagedViewDecoding, "typed packaged-view row")
            ).subtotal,
            SQLiteNorthwindConformanceFixtures.sentinelOrderSubtotal,
            accuracy: 0.000_001,
            oracle(.packagedViewDecoding, "pinned packaged-view subtotal")
        )
    }

    func testSubqueryCompoundAndCommonTableExpression() throws {
        let fixture = try makeReadOnlyFixture(
            for: .productsAboveAverage,
            source: "read-only fixture for subquery, compound, and CTE cases"
        )
        defer { try? fixture.pool.close() }

        let aboveAverageStatement = sql { schema in
            let products = schema.table(NorthwindCorpusProduct.self)
            let averageProducts = schema.table(NorthwindCorpusProduct.self)
            Select(NorthwindCorpusProductRow.columns(
                productID: products.productID,
                productName: products.productName,
                unitPrice: products.unitPrice
            ))
            From(products)
            Where(products.unitPrice > subquery {
                select(averageProducts.unitPrice.averageOrNull().coalesce(0))
                    .from(averageProducts)
            })
            OrderBy(products.unitPrice.descending(), products.productID.ascending())
        }
        let typedAboveAverage = try withEvidence(
            .productsAboveAverage,
            "typed scalar-subquery fetch"
        ) {
            try fixture.database.makeRequest(with: aboveAverageStatement).fetchAll()
        }
        let rawAboveAverage = try withEvidence(
            .productsAboveAverage,
            "raw GRDB scalar-subquery fetch"
        ) {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT ProductID AS productID, ProductName AS productName,
                               UnitPrice AS unitPrice
                        FROM Products
                        WHERE UnitPrice > (SELECT AVG(UnitPrice) FROM Products)
                        ORDER BY UnitPrice DESC, ProductID ASC
                        """
                ).map(\.asProductRow)
            }
        }
        XCTAssertEqual(
            typedAboveAverage,
            rawAboveAverage,
            oracle(.productsAboveAverage, "independent raw GRDB scalar-subquery SQL")
        )

        let compoundStatement = sql { schema in
            let customers = schema.table(NorthwindCorpusCustomer.self)
            let suppliers = schema.table(NorthwindCorpusSupplier.self)
            let customerRow = NorthwindCorpusContactLocation.columns(
                city: customers.city,
                companyName: customers.companyName,
                contactName: customers.contactName,
                relationship: "Customers"
            )
            let supplierRow = NorthwindCorpusContactLocation.columns(
                city: suppliers.city,
                companyName: suppliers.companyName,
                contactName: suppliers.contactName,
                relationship: "Suppliers"
            )
            Select(customerRow)
            From(customers)
            Union()
            Select(supplierRow)
            From(suppliers)
            OrderBy(
                customerRow.city.ascending(),
                customerRow.companyName.ascending(),
                customerRow.relationship.ascending(),
                customerRow.contactName.ascending()
            )
        }
        let typedLocations = try withEvidence(.customerSupplierCities, "typed UNION fetch") {
            try fixture.database.makeRequest(with: compoundStatement).fetchAll()
        }
        let rawLocations = try withEvidence(.customerSupplierCities, "raw GRDB UNION fetch") {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT City AS city, CompanyName AS companyName,
                               ContactName AS contactName, 'Customers' AS relationship
                        FROM Customers
                        UNION
                        SELECT City AS city, CompanyName AS companyName,
                               ContactName AS contactName, 'Suppliers' AS relationship
                        FROM Suppliers
                        ORDER BY city, companyName, relationship, contactName
                        """
                ).map(\.asContactLocation)
            }
        }
        XCTAssertEqual(
            typedLocations,
            rawLocations,
            oracle(.customerSupplierCities, "independent raw GRDB UNION SQL")
        )

        let cteStatement = sql { schema in
            let subtotals = schema.commonTableExpression { schema in
                let details = schema.table(NorthwindCorpusOrderDetail.self)
                let discountedLine = details.unitPrice
                    * details.quantity.toDouble()
                    * (1.0 - details.discount)
                Select(NorthwindCorpusOrderSubtotal.columns(
                    orderID: details.orderID,
                    subtotal: discountedLine.sumOrNull().coalesce(0)
                ))
                From(details)
                GroupBy(details.orderID)
            }
            let rows = schema.table(subtotals)
            With(subtotals)
            Select(rows)
            From(rows)
            Where(rows.orderID == SQLiteNorthwindConformanceFixtures.sentinelOrderID)
            OrderBy(rows.orderID.ascending())
        }
        let typedCTE = try withEvidence(.cteOrderSubtotals, "typed CTE fetch") {
            try fixture.database.makeRequest(with: cteStatement).fetchAll()
        }
        let rawCTE = try withEvidence(.cteOrderSubtotals, "raw GRDB WITH aggregate fetch") {
            try fixture.pool.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                        WITH order_subtotals AS (
                            SELECT OrderID AS orderID,
                                   SUM(UnitPrice * Quantity * (1.0 - Discount)) AS subtotal
                            FROM "Order Details"
                            GROUP BY OrderID
                        )
                        SELECT orderID, subtotal
                        FROM order_subtotals
                        WHERE orderID = ?
                        ORDER BY orderID
                        """,
                    arguments: [SQLiteNorthwindConformanceFixtures.sentinelOrderID]
                ).map(\.asOrderSubtotal)
            }
        }
        XCTAssertEqual(
            typedCTE,
            rawCTE,
            oracle(.cteOrderSubtotals, "independent raw GRDB WITH aggregate SQL")
        )
        XCTAssertEqual(
            try XCTUnwrap(
                typedCTE.first,
                oracle(.cteOrderSubtotals, "typed CTE subtotal row")
            ).subtotal,
            SQLiteNorthwindConformanceFixtures.sentinelOrderSubtotal,
            accuracy: 0.000_001,
            oracle(.cteOrderSubtotals, "pinned order 10248 subtotal")
        )
    }

    func testTemporaryCopyCRUDAndThrowingRollback() throws {
        let before = try withEvidence(.crudTemporaryCopy, "canonical fixture validation before DML") {
            try NorthwindFixture.validateCanonical()
        }
        let mutationID = "ZQ254"
        let inserted = NorthwindCorpusCustomer(
            customerID: mutationID,
            companyName: "SwiftQL Corpus Insert",
            contactName: "Typed DML",
            city: "Cape Town",
            region: nil,
            country: "South Africa"
        )

        try NorthwindFixture.withTemporaryCopy { copy in
            let database = try self.withEvidence(
                .crudTemporaryCopy,
                "typed database adapter initialization on temporary copy"
            ) {
                try GRDBDatabase(
                    databasePool: copy.databasePool,
                    formatter: XLiteFormatter(),
                    logger: nil
                )
            }
            try self.withEvidence(.crudTemporaryCopy, "typed INSERT execution") {
                try database.makeRequest(with: sqlInsert(inserted)).execute()
            }
            let typedInserted = try self.fetchCustomer(
                mutationID,
                from: database,
                caseID: .crudTemporaryCopy,
                source: "typed SELECT after typed INSERT"
            )
            let rawInserted = try self.fetchRawCustomer(
                mutationID,
                from: copy.databasePool,
                caseID: .crudTemporaryCopy,
                source: "raw GRDB SELECT after typed INSERT"
            )
            XCTAssertEqual(
                typedInserted,
                rawInserted,
                oracle(.crudTemporaryCopy, "raw GRDB read after typed INSERT")
            )
            XCTAssertEqual(
                typedInserted,
                inserted,
                oracle(.crudTemporaryCopy, "typed INSERT input")
            )

            let updateStatement = sql { schema in
                let customers = schema.into(NorthwindCorpusCustomer.self)
                Update(customers)
                Setting<NorthwindCorpusCustomer> { row in
                    row.companyName = "SwiftQL Corpus Updated"
                }
                Where(customers.customerID == mutationID)
            }
            try self.withEvidence(.crudTemporaryCopy, "typed UPDATE execution") {
                try database.makeRequest(with: updateStatement).execute()
            }
            let typedUpdated = try XCTUnwrap(
                self.fetchCustomer(
                    mutationID,
                    from: database,
                    caseID: .crudTemporaryCopy,
                    source: "typed SELECT after typed UPDATE"
                ),
                oracle(.crudTemporaryCopy, "typed SELECT after typed UPDATE")
            )
            let rawUpdated = try XCTUnwrap(
                self.fetchRawCustomer(
                    mutationID,
                    from: copy.databasePool,
                    caseID: .crudTemporaryCopy,
                    source: "raw GRDB SELECT after typed UPDATE"
                ),
                oracle(.crudTemporaryCopy, "raw GRDB read after typed UPDATE")
            )
            XCTAssertEqual(
                typedUpdated,
                rawUpdated,
                oracle(.crudTemporaryCopy, "raw GRDB read after typed UPDATE")
            )
            XCTAssertEqual(
                typedUpdated.companyName,
                "SwiftQL Corpus Updated",
                oracle(.crudTemporaryCopy, "typed UPDATE value")
            )

            let deleteStatement = sql { schema in
                let customers = schema.into(NorthwindCorpusCustomer.self)
                Delete(customers)
                Where(customers.customerID == mutationID)
            }
            try self.withEvidence(.crudTemporaryCopy, "typed DELETE execution") {
                try database.makeRequest(with: deleteStatement).execute()
            }
            XCTAssertNil(
                try self.fetchCustomer(
                    mutationID,
                    from: database,
                    caseID: .crudTemporaryCopy,
                    source: "typed SELECT after typed DELETE"
                ),
                oracle(.crudTemporaryCopy, "typed SELECT after typed DELETE")
            )
            XCTAssertNil(
                try self.fetchRawCustomer(
                    mutationID,
                    from: copy.databasePool,
                    caseID: .crudTemporaryCopy,
                    source: "raw GRDB SELECT after typed DELETE"
                ),
                oracle(.crudTemporaryCopy, "raw GRDB read after typed DELETE")
            )
        }

        let rollbackID = "ZR254"
        try NorthwindFixture.withTemporaryCopy { copy in
            XCTAssertThrowsError(
                try copy.databasePool.writeWithoutTransaction { database in
                    try database.inTransaction {
                        try self.withEvidence(.throwingRollback, "raw GRDB INSERT inside rollback") {
                            try database.execute(
                                sql: "INSERT INTO Customers (CustomerID, CompanyName) VALUES (?, ?)",
                                arguments: [rollbackID, "Must Roll Back"]
                            )
                        }
                        throw RollbackSignal.requested
                    }
                },
                oracle(.throwingRollback, "GRDB transaction throwing body")
            ) { error in
                XCTAssertEqual(
                    error as? RollbackSignal,
                    .requested,
                    self.oracle(.throwingRollback, "preserved transaction body error")
                )
            }
            let database = try self.withEvidence(
                .throwingRollback,
                "typed database adapter initialization after rollback"
            ) {
                try GRDBDatabase(
                    databasePool: copy.databasePool,
                    formatter: XLiteFormatter(),
                    logger: nil
                )
            }
            XCTAssertNil(
                try self.fetchCustomer(
                    rollbackID,
                    from: database,
                    caseID: .throwingRollback,
                    source: "typed SELECT after rollback"
                ),
                oracle(.throwingRollback, "typed SwiftQL read after rollback")
            )
            XCTAssertNil(
                try self.fetchRawCustomer(
                    rollbackID,
                    from: copy.databasePool,
                    caseID: .throwingRollback,
                    source: "raw GRDB SELECT after rollback"
                ),
                oracle(.throwingRollback, "raw GRDB read after rollback")
            )
        }

        let after = try withEvidence(.crudTemporaryCopy, "canonical fixture validation after DML") {
            try NorthwindFixture.validateCanonical()
        }
        XCTAssertEqual(
            after.databaseSHA256,
            before.databaseSHA256,
            oracle(.crudTemporaryCopy, "canonical fixture checksum after temporary mutation")
        )
        XCTAssertEqual(
            after.rowCounts,
            before.rowCounts,
            oracle(.throwingRollback, "canonical fixture row counts after temporary rollback")
        )
    }

    private func makeReadOnlyFixture(
        for caseID: SQLiteNorthwindConformanceCaseID,
        source: String
    ) throws -> (pool: DatabasePool, database: GRDBDatabase) {
        let pool = try withEvidence(caseID, "\(source) pool initialization") {
            try NorthwindFixture.validatedReadOnlyPool()
        }
        do {
            let database = try withEvidence(caseID, "\(source) adapter initialization") {
                try GRDBDatabase(
                    databasePool: pool,
                    formatter: XLiteFormatter(),
                    logger: nil
                )
            }
            return (pool, database)
        } catch {
            try? pool.close()
            throw error
        }
    }

    private func fetchCustomer(
        _ id: String,
        from database: GRDBDatabase,
        caseID: SQLiteNorthwindConformanceCaseID,
        source: String
    ) throws -> NorthwindCorpusCustomer? {
        let statement = sql { schema in
            let customers = schema.table(NorthwindCorpusCustomer.self)
            Select(customers)
            From(customers)
            Where(customers.customerID == id)
        }
        return try withEvidence(caseID, source) {
            try database.makeRequest(with: statement).fetchOne()
        }
    }

    private func fetchRawCustomer(
        _ id: String,
        from pool: DatabasePool,
        caseID: SQLiteNorthwindConformanceCaseID,
        source: String
    ) throws -> NorthwindCorpusCustomer? {
        try withEvidence(caseID, source) {
            try pool.read { database in
                try Row.fetchOne(
                    database,
                    sql: """
                        SELECT CustomerID AS customerID, CompanyName AS companyName,
                               ContactName AS contactName, City AS city,
                               Region AS region, Country AS country
                        FROM Customers WHERE CustomerID = ?
                        """,
                    arguments: [id]
                ).map(NorthwindCorpusCustomer.init(raw:))
            }
        }
    }

    /// Keep XCTest assertions outside this closure so assertion failures retain XCTest's diagnostics.
    private func withEvidence<T>(
        _ id: SQLiteNorthwindConformanceCaseID,
        _ source: String,
        operation: () throws -> T
    ) throws -> T {
        do {
            return try operation()
        } catch let error as SemanticOperationFailure {
            throw error
        } catch {
            throw SemanticOperationFailure(
                context: oracle(id, source),
                underlyingError: error
            )
        }
    }

    private func oracle(
        _ id: SQLiteNorthwindConformanceCaseID,
        _ source: String
    ) -> String {
        "[\(id.rawValue)] typed SwiftQL vs \(source) oracle; \(fixtureEvidence)"
    }
}


private extension NorthwindCorpusCustomer {
    init(raw row: Row) {
        self.init(
            customerID: row["customerID"],
            companyName: row["companyName"],
            contactName: row["contactName"],
            city: row["city"],
            region: row["region"],
            country: row["country"]
        )
    }
}


private extension NorthwindCorpusOrderDetail {
    init(raw row: Row) {
        self.init(
            orderID: row["orderID"],
            productID: row["productID"],
            unitPrice: row["unitPrice"],
            quantity: row["quantity"],
            discount: row["discount"]
        )
    }
}


private extension NorthwindCorpusOrderSubtotalView {
    init(raw row: Row) {
        self.init(orderID: row["orderID"], subtotal: row["subtotal"])
    }
}


private extension Row {
    var asShippingRow: NorthwindCorpusShippingRow {
        NorthwindCorpusShippingRow(
            orderID: self["orderID"],
            shippedDate: self["shippedDate"],
            shipRegion: self["shipRegion"]
        )
    }

    var asCustomerTextRow: NorthwindCorpusCustomerTextRow {
        NorthwindCorpusCustomerTextRow(
            customerID: self["customerID"],
            companyName: self["companyName"],
            city: self["city"]
        )
    }

    var asEmployeePhotoRow: NorthwindCorpusEmployeePhotoRow {
        NorthwindCorpusEmployeePhotoRow(
            employeeID: self["employeeID"],
            photo: self["photo"]
        )
    }

    var asOrderLine: NorthwindCorpusOrderLine {
        NorthwindCorpusOrderLine(
            orderID: self["orderID"],
            customerID: self["customerID"],
            companyName: self["companyName"],
            employeeID: self["employeeID"],
            employeeLastName: self["employeeLastName"],
            productID: self["productID"],
            productName: self["productName"],
            unitPrice: self["unitPrice"],
            quantity: self["quantity"],
            discount: self["discount"]
        )
    }

    var asEmployeeManagerRow: NorthwindCorpusEmployeeManagerRow {
        NorthwindCorpusEmployeeManagerRow(
            employeeID: self["employeeID"],
            employeeLastName: self["employeeLastName"],
            managerID: self["managerID"],
            managerLastName: self["managerLastName"]
        )
    }

    var asCustomerOrderVolume: NorthwindCorpusCustomerOrderVolume {
        NorthwindCorpusCustomerOrderVolume(
            customerID: self["customerID"],
            orderCount: self["orderCount"]
        )
    }

    var asNullableAggregate: NorthwindCorpusNullableAggregate {
        NorthwindCorpusNullableAggregate(total: self["total"])
    }

    var asProductRow: NorthwindCorpusProductRow {
        NorthwindCorpusProductRow(
            productID: self["productID"],
            productName: self["productName"],
            unitPrice: self["unitPrice"]
        )
    }

    var asContactLocation: NorthwindCorpusContactLocation {
        NorthwindCorpusContactLocation(
            city: self["city"],
            companyName: self["companyName"],
            contactName: self["contactName"],
            relationship: self["relationship"]
        )
    }

    var asOrderSubtotal: NorthwindCorpusOrderSubtotal {
        NorthwindCorpusOrderSubtotal(
            orderID: self["orderID"],
            subtotal: self["subtotal"]
        )
    }
}
