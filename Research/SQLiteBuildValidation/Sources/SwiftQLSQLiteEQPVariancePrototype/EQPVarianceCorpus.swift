import Foundation
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteConformanceFixtures


package enum EQPVarianceCorpus {
    /// Assembles the #390 statement corpus: every #191 combinatorial case
    /// (`SQLiteCombinatorialSuite.makeManifest()`, reused unmodified) plus a
    /// small set of hand-authored Northwind (#254) semantic anchors covering
    /// join/CTE/subquery shapes the pairwise grid does not itself exercise
    /// against real data. Deterministic: the same manifest generator plus a
    /// fixed anchor list always yields the same corpus, sorted by id.
    package static func assemble() throws -> [EQPVarianceStatement] {
        let manifest = try SQLiteCombinatorialSuite.makeManifest()
        let combinatorial = manifest.cases.map { testCase in
            EQPVarianceStatement(
                id: testCase.id,
                source: .combinatorial,
                renderedSQL: testCase.renderedSQL,
                northwindAnchorCaseIDs: testCase.northwindAnchorCaseIDs ?? [],
                bindings: testCase.bindings
            )
        }
        return (combinatorial + northwindAnchorStatements()).sorted { $0.id < $1.id }
    }

    /// Cribbed verbatim from the raw-SQL oracle strings in
    /// `Tests/SQLTests/NorthwindSemanticCorpusTests.swift`, which is the only
    /// place in the repo that defines these shapes as literal SQL today.
    package static func northwindAnchorStatements() -> [EQPVarianceStatement] {
        let sentinelOrderID = SQLiteNorthwindConformanceFixtures.sentinelOrderID

        return [
            EQPVarianceStatement(
                id: "c390.northwind.join.customer-order-employee-product",
                source: .northwindAnchor,
                renderedSQL: """
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
                northwindAnchorCaseIDs: [SQLiteNorthwindConformanceCaseID.customerOrderEmployeeProductJoin.rawValue],
                bindings: [indexedIntegerBinding(logicalIndex: 0, value: Int64(sentinelOrderID))]
            ),
            EQPVarianceStatement(
                id: "c390.northwind.join.left-null-manager",
                source: .northwindAnchor,
                renderedSQL: """
                    SELECT e.EmployeeID AS employeeID,
                           e.LastName AS employeeLastName,
                           m.EmployeeID AS managerID,
                           m.LastName AS managerLastName
                    FROM Employees AS e
                    LEFT JOIN Employees AS m ON e.ReportsTo = m.EmployeeID
                    ORDER BY e.EmployeeID
                    """,
                northwindAnchorCaseIDs: [SQLiteNorthwindConformanceCaseID.leftNullManager.rawValue],
                bindings: []
            ),
            EQPVarianceStatement(
                id: "c390.northwind.aggregate.grouped-having",
                source: .northwindAnchor,
                renderedSQL: """
                    SELECT CustomerID AS customerID, COUNT(OrderID) AS orderCount
                    FROM Orders
                    GROUP BY CustomerID
                    HAVING COUNT(OrderID) >= 10
                    ORDER BY orderCount DESC, customerID ASC
                    """,
                northwindAnchorCaseIDs: [SQLiteNorthwindConformanceCaseID.groupedHaving.rawValue],
                bindings: []
            ),
            EQPVarianceStatement(
                id: "c390.northwind.subquery.products-above-average",
                source: .northwindAnchor,
                renderedSQL: """
                    SELECT ProductID AS productID, ProductName AS productName,
                           UnitPrice AS unitPrice
                    FROM Products
                    WHERE UnitPrice > (SELECT AVG(UnitPrice) FROM Products)
                    ORDER BY UnitPrice DESC, ProductID ASC
                    """,
                northwindAnchorCaseIDs: [SQLiteNorthwindConformanceCaseID.productsAboveAverage.rawValue],
                bindings: []
            ),
            EQPVarianceStatement(
                id: "c390.northwind.compound.customer-supplier-cities",
                source: .northwindAnchor,
                renderedSQL: """
                    SELECT City AS city, CompanyName AS companyName,
                           ContactName AS contactName, 'Customers' AS relationship
                    FROM Customers
                    UNION
                    SELECT City AS city, CompanyName AS companyName,
                           ContactName AS contactName, 'Suppliers' AS relationship
                    FROM Suppliers
                    ORDER BY city, companyName, relationship, contactName
                    """,
                northwindAnchorCaseIDs: [SQLiteNorthwindConformanceCaseID.customerSupplierCities.rawValue],
                bindings: []
            ),
            EQPVarianceStatement(
                id: "c390.northwind.cte.order-subtotals",
                source: .northwindAnchor,
                renderedSQL: """
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
                northwindAnchorCaseIDs: [SQLiteNorthwindConformanceCaseID.cteOrderSubtotals.rawValue],
                bindings: [indexedIntegerBinding(logicalIndex: 0, value: Int64(sentinelOrderID))]
            ),
        ]
    }

    private static func indexedIntegerBinding(
        logicalIndex: Int,
        value: Int64
    ) -> SQLiteCombinatorialBinding {
        SQLiteCombinatorialBinding(
            logicalIndex: logicalIndex,
            keyKind: .indexed,
            keyName: nil,
            keyIndex: logicalIndex + 1,
            storage: .integer,
            taggedValue: .integer(value),
            repeatCount: 1
        )
    }
}
