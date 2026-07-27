import XCTest
import SwiftQLSQLiteEQPVariancePrototype
@testable import SwiftQLSQLiteIndexAdvisorPrototype


final class IndexCandidateExtractionTests: XCTestCase {
    // MARK: - Real corpus statements (Tests/SwiftQLSQLiteCombinatorialSupport / #390 anchors)

    func testEqualityComparisonOnPrimaryAlias() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" CROSS JOIN "Customers" AS "customers_cross" WHERE ("t0"."orderID" == 10248)"#
        let comparisons = IndexCandidateExtraction.whereComparisons(for: "t0", in: sql)
        XCTAssertEqual(comparisons, [WhereComparison(alias: "t0", column: "orderID", kind: .equality)])
    }

    func testRangeComparisonWithNamedBinding() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" CROSS JOIN "Customers" AS "customers_cross" WHERE ("t0"."orderID" >= :minimum_order_id)"#
        let comparisons = IndexCandidateExtraction.whereComparisons(for: "t0", in: sql)
        XCTAssertEqual(comparisons, [WhereComparison(alias: "t0", column: "orderID", kind: .range)])
    }

    func testRepeatedRangeBindingProducesTwoRangeComparisons() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" CROSS JOIN "Customers" AS "customers_cross" WHERE (("t0"."employeeID" >= :repeated_employee_id) AND ("t0"."employeeID" <= :repeated_employee_id))"#
        let comparisons = IndexCandidateExtraction.whereComparisons(for: "t0", in: sql)
        XCTAssertEqual(comparisons, [
            WhereComparison(alias: "t0", column: "employeeID", kind: .range),
            WhereComparison(alias: "t0", column: "employeeID", kind: .range),
        ])
    }

    /// A top-level OR is exactly the case this extractor deliberately
    /// refuses to interpret rather than guess at.
    func testTopLevelOrYieldsNoComparisons() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" CROSS JOIN "Customers" AS "customers_cross" WHERE ((("t0"."orderID" > 10248) AND ("t0"."employeeID" == 1)) OR ("t0"."customerID" == 'VINET'))"#
        XCTAssertEqual(IndexCandidateExtraction.whereComparisons(for: "t0", in: sql), [])
    }

    func testINComparisonIsNotRecognisedAndYieldsNoComparisonForThatConjunct() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" CROSS JOIN "Customers" AS "customers_cross" WHERE ("t0"."orderID" IN (10248, 10249, 10250))"#
        XCTAssertEqual(IndexCandidateExtraction.whereComparisons(for: "t0", in: sql), [])
    }

    func testJoinKeysFromInnerJoin() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" INNER JOIN "Customers" AS "customers_join" ON ("t0"."customerID" == "customers_join"."customerID") WHERE ("t0"."orderID" == 10248)"#
        XCTAssertEqual(
            IndexCandidateExtraction.joinKeys(for: "t0", in: sql),
            [JoinKey(alias: "t0", column: "customerID")]
        )
        XCTAssertEqual(
            IndexCandidateExtraction.joinKeys(for: "customers_join", in: sql),
            [JoinKey(alias: "customers_join", column: "customerID")]
        )
    }

    func testJoinKeysFromLeftJoinUsesIS() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" LEFT JOIN "Employees" AS "employees_join" ON ("t0"."employeeID" IS "employees_join"."employeeID") WHERE ("t0"."orderID" == 10248)"#
        XCTAssertEqual(
            IndexCandidateExtraction.joinKeys(for: "t0", in: sql),
            [JoinKey(alias: "t0", column: "employeeID")]
        )
    }

    func testOrderByColumnsIgnoringCollateAndDirection() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" WHERE ("t0"."orderID" >= :minimum_order_id) ORDER BY ("t0"."customerID" COLLATE NOCASE) ASC"#
        XCTAssertEqual(IndexCandidateExtraction.orderByColumns(for: "t0", in: sql), ["customerID"])
    }

    func testOrderByMultipleColumns() {
        let sql = #"SELECT "customerID" FROM "Orders" AS "t0" GROUP BY "t0"."customerID" HAVING COUNT("t0"."orderID") >= 10 ORDER BY "orderCount" DESC, "t0"."customerID" ASC"#
        // Only the second term is qualified by "t0"; the first ("orderCount")
        // is an unqualified result-column alias this extractor deliberately
        // does not resolve.
        XCTAssertEqual(IndexCandidateExtraction.orderByColumns(for: "t0", in: sql), ["customerID"])
    }

    // MARK: - Real five-table join anchor from #390

    func testFiveTableJoinRealAnchorStatement() throws {
        let corpus = try EQPVarianceCorpus.assemble()
        let statement = try XCTUnwrap(
            corpus.first { $0.id == "c390.northwind.join.customer-order-employee-product" }
        )
        let comparisons = IndexCandidateExtraction.whereComparisons(for: "o", in: statement.renderedSQL)
        XCTAssertEqual(comparisons, [WhereComparison(alias: "o", column: "OrderID", kind: .equality)])

        XCTAssertEqual(
            IndexCandidateExtraction.joinKeys(for: "c", in: statement.renderedSQL),
            [JoinKey(alias: "c", column: "CustomerID")]
        )
        // "d" (Order Details) is joined twice: to Orders via OrderID and to
        // Products via ProductID — both are genuine join keys for "d".
        XCTAssertEqual(
            IndexCandidateExtraction.joinKeys(for: "d", in: statement.renderedSQL),
            [JoinKey(alias: "d", column: "OrderID"), JoinKey(alias: "d", column: "ProductID")]
        )
        XCTAssertEqual(
            IndexCandidateExtraction.orderByColumns(for: "p", in: statement.renderedSQL),
            ["ProductID"]
        )

        let tableAliases = IndexCandidateExtraction.tableAliasMap(in: statement.renderedSQL)
        XCTAssertEqual(tableAliases, [
            "o": "Orders",
            "c": "Customers",
            "e": "Employees",
            "d": "Order Details",
            "p": "Products",
        ])
    }

    func testTableAliasMapQuotedStyle() {
        let sql = #"SELECT "t0"."orderID" FROM "Orders" AS "t0" INNER JOIN "Customers" AS "customers_join" ON ("t0"."customerID" == "customers_join"."customerID")"#
        XCTAssertEqual(
            IndexCandidateExtraction.tableAliasMap(in: sql),
            ["t0": "Orders", "customers_join": "Customers"]
        )
    }
}
