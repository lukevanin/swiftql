//
//  SQLiteBuildValidationPlanDiagnosticsTests.swift
//
//  Issue #395: advisory diagnostics for the plan shapes that indicate
//  avoidable work, with explicit checked-in suppression, and no effect on any
//  verdict or exit status.
//

import Foundation
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationPlanTableResolverTests: XCTestCase {
    typealias Resolver = SQLiteBuildValidationPlanTableResolver

    func testResolvesTheQuotedAliasStyleSwiftQLRenders() {
        let sql = """
            SELECT "t0"."ShipCity" FROM "Order Details" AS "t1" \
            JOIN "Orders" AS "t0" ON "t0"."OrderID" = "t1"."OrderID"
            """
        let aliases = Resolver.tableAliases(in: sql)

        XCTAssertEqual(aliases["t0"], "Orders")
        XCTAssertEqual(aliases["t1"], "Order Details")
    }

    func testResolvesTheBareAliasStyleAnchorStatementsUse() {
        let aliases = Resolver.tableAliases(
            in: "SELECT p.ProductName FROM Products p JOIN Categories c ON c.CategoryID = p.CategoryID"
        )

        XCTAssertEqual(aliases["p"], "Products")
        XCTAssertEqual(aliases["c"], "Categories")
    }

    /// EQP prints the table name when the statement declared no alias, so a
    /// table has to resolve to itself for a lookup to succeed.
    func testAnUnaliasedTableResolvesToItself() {
        XCTAssertEqual(
            Resolver.tableAliases(in: "SELECT ShipCity FROM Orders WHERE OrderID = 1")["Orders"],
            "Orders"
        )
        XCTAssertEqual(
            Resolver.tableAliases(in: "SELECT ShipCity FROM Orders ORDER BY ShipCity")["Orders"],
            "Orders"
        )
    }

    /// `CREATE INDEX` on a CTE would fail, and a diagnostic naming one would
    /// name something that is not a table.
    func testCTENamesAreNotResolvedAsTables() {
        let sql = """
            WITH "cte0" AS (SELECT "OrderID" FROM "Orders") \
            SELECT "t0"."OrderID" FROM "cte0" AS "t0"
            """
        XCTAssertNil(Resolver.tableAliases(in: sql)["t0"])
    }

    /// The same alias bound to two tables in two scopes cannot be resolved
    /// without real scope tracking, so it resolves to neither.
    func testAnAliasReboundToADifferentTableResolvesToNothing() {
        let sql = """
            SELECT "t0"."OrderID" FROM "Orders" AS "t0" \
            WHERE "t0"."EmployeeID" IN (SELECT "t0"."EmployeeID" FROM "Employees" AS "t0")
            """
        XCTAssertNil(Resolver.tableAliases(in: sql)["t0"])
    }
}


final class SQLiteBuildValidationPlanDiagnosticsTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport

    // MARK: - Fixtures
    //
    // Every diagnosed shape gets a statement that produces it and one that
    // does not, all against the real pinned Northwind snapshot. Orders has
    // 830 rows and Categories has 8, which is what makes the row threshold
    // testable with real data rather than a synthetic table.

    private static func text(_ index: Int, _ alias: String) -> SQLiteBuildValidationResultEntry {
        Support.result(
            index: index,
            identity: "result/\(alias)",
            declaredAlias: alias,
            valueTypeIdentifier: "swift.string",
            valueTypeName: "Swift.String",
            nullability: "nullable",
            storageIdentifier: "text"
        )
    }

    private static func integer(_ index: Int, _ alias: String) -> SQLiteBuildValidationResultEntry {
        Support.result(
            index: index,
            identity: "result/\(alias)",
            declaredAlias: alias,
            valueTypeIdentifier: "swift.int",
            valueTypeName: "Swift.Int",
            storageIdentifier: "integer"
        )
    }

    /// SCAN Orders, 830 rows: above the threshold.
    static let scansLargeTable = Support.query(
        id: "a.scan-orders",
        sql: "SELECT ShipCity AS ship_city FROM Orders",
        results: [text(0, "ship_city")]
    )

    /// SCAN Categories, 8 rows: below the threshold.
    static let scansSmallTable = Support.query(
        id: "b.scan-categories",
        sql: "SELECT CategoryName AS category_name FROM Categories",
        results: [text(0, "category_name")]
    )

    /// A rowid seek: no scan at all.
    static let seeksByPrimaryKey = Support.query(
        id: "c.seek-order",
        sql: "SELECT ShipCity AS ship_city FROM Orders WHERE OrderID = :order_id",
        parameters: [
            Support.parameter(
                identity: "parameter/order_id",
                keyName: "order_id",
                valueTypeIdentifier: "swift.int",
                valueTypeName: "Swift.Int",
                storageIdentifier: "integer"
            ),
        ],
        results: [text(0, "ship_city")]
    )

    static let sortsWithTempBTree = Support.query(
        id: "d.order-by-ship-city",
        sql: "SELECT ShipCity AS ship_city FROM Orders ORDER BY ShipCity",
        results: [text(0, "ship_city")]
    )

    /// Ordering by the rowid needs no sort.
    static let sortsWithoutTempBTree = Support.query(
        id: "e.order-by-order-id",
        sql: "SELECT OrderID AS order_id FROM Orders ORDER BY OrderID",
        results: [integer(0, "order_id")]
    )

    static let groupsWithTempBTree = Support.query(
        id: "f.group-by-ship-city",
        sql: "SELECT ShipCity AS ship_city, COUNT(*) AS order_count FROM Orders GROUP BY ShipCity",
        results: [text(0, "ship_city"), integer(1, "order_count")]
    )

    /// Grouping by the rowid needs no sort.
    static let groupsWithoutTempBTree = Support.query(
        id: "g.group-by-order-id",
        sql: "SELECT OrderID AS order_id, COUNT(*) AS order_count FROM Orders GROUP BY OrderID",
        results: [integer(0, "order_id"), integer(1, "order_count")]
    )

    /// The real correlated-scalar-subquery fixture #395 requires before that
    /// diagnostic ships: the subquery reads `p.CategoryID` from the outer
    /// row, so SQLite must re-evaluate it per row.
    static let correlatedSubquery = Support.query(
        id: "h.correlated-category",
        sql: """
            SELECT p.ProductName AS product_name, \
            (SELECT c.CategoryName FROM Categories c WHERE c.CategoryID = p.CategoryID) AS category_name \
            FROM Products p
            """,
        results: [text(0, "product_name"), text(1, "category_name")]
    )

    /// The same statement shape without the correlation: SQLite evaluates the
    /// subquery once.
    static let uncorrelatedSubquery = Support.query(
        id: "i.uncorrelated-average",
        sql: "SELECT p.ProductName AS product_name FROM Products p WHERE p.UnitPrice > (SELECT AVG(UnitPrice) FROM Products)",
        results: [text(0, "product_name")]
    )

    private static let corpus = [
        scansLargeTable,
        scansSmallTable,
        seeksByPrimaryKey,
        sortsWithTempBTree,
        sortsWithoutTempBTree,
        groupsWithTempBTree,
        groupsWithoutTempBTree,
        correlatedSubquery,
        uncorrelatedSubquery,
    ]

    private func planReport(
        queries: [SQLiteBuildValidationQueryEntry],
        settings: SQLiteBuildValidationPlanDiagnosticSettings = .init()
    ) throws -> SQLiteBuildValidationPlanReport {
        try Support.withValidatorOwnedNorthwindURL { url in
            try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: Support.manifest(queries: queries),
                    againstDatabaseAt: url,
                    capturesPlans: true,
                    planDiagnosticSettings: settings
                ).planReport
            )
        }
    }

    private func codes(
        _ report: SQLiteBuildValidationPlanReport,
        for queryID: String
    ) -> [SQLiteBuildValidationPlanDiagnosticCode] {
        report.diagnostics.filter { $0.queryID == queryID }.map(\.code)
    }

    // MARK: - Each shape has a fixture that produces it, and one that does not

    func testEachDiagnosedShapeHasAProducingAndANonProducingFixture() throws {
        let report = try planReport(queries: Self.corpus)

        XCTAssertEqual(codes(report, for: "a.scan-orders"), [.fullTableScan])
        XCTAssertEqual(codes(report, for: "b.scan-categories"), [])
        XCTAssertEqual(codes(report, for: "c.seek-order"), [])

        XCTAssertEqual(
            codes(report, for: "d.order-by-ship-city"),
            [.fullTableScan, .tempBTreeForOrderBy]
        )
        XCTAssertEqual(codes(report, for: "e.order-by-order-id"), [.fullTableScan])

        XCTAssertEqual(
            codes(report, for: "f.group-by-ship-city"),
            [.fullTableScan, .tempBTreeForGroupBy]
        )
        XCTAssertEqual(codes(report, for: "g.group-by-order-id"), [.fullTableScan])

        XCTAssertEqual(
            codes(report, for: "h.correlated-category"),
            [.correlatedScalarSubquery]
        )
        XCTAssertEqual(codes(report, for: "i.uncorrelated-average"), [])
    }

    /// The whole corpus, asserted exactly: an advisory set with no extra
    /// finding is the only way "no false positives" is checkable.
    func testTheNorthwindCorpusProducesExactlyTheExpectedAdvisorySet() throws {
        let report = try planReport(queries: Self.corpus)

        XCTAssertEqual(
            report.diagnostics.map { "\($0.queryID)|\($0.code.rawValue)" },
            [
                "a.scan-orders|plan.full-table-scan",
                "d.order-by-ship-city|plan.full-table-scan",
                "d.order-by-ship-city|plan.temp-b-tree-order-by",
                "e.order-by-order-id|plan.full-table-scan",
                "f.group-by-ship-city|plan.full-table-scan",
                "f.group-by-ship-city|plan.temp-b-tree-group-by",
                "g.group-by-order-id|plan.full-table-scan",
                "h.correlated-category|plan.correlated-scalar-subquery",
            ].sorted()
        )
    }

    func testAScanDiagnosticNamesTheTableItsRowCountAndThePlanNode() throws {
        let report = try planReport(queries: [Self.scansLargeTable])
        let diagnostic = try XCTUnwrap(report.diagnostics.first)

        XCTAssertEqual(diagnostic.severity, .advisory)
        XCTAssertEqual(diagnostic.code, .fullTableScan)
        XCTAssertEqual(diagnostic.table, "Orders")
        XCTAssertEqual(diagnostic.alias, "Orders")
        XCTAssertEqual(diagnostic.tableRowCount, 830)
        XCTAssertEqual(diagnostic.planNodeShape, .fullTableScan)
        XCTAssertEqual(diagnostic.planNodeDetail, "SCAN Orders")
        XCTAssertEqual(diagnostic.descriptorIdentity, Self.scansLargeTable.descriptorIdentity)
        XCTAssertTrue(diagnostic.message.contains("Orders"))
    }

    /// A statement that declares an alias must still be reported against the
    /// real table, because that is the name a reader and `CREATE INDEX` both
    /// need.
    func testADiagnosticResolvesAnAliasToItsRealTable() throws {
        let aliased = Support.query(
            id: "aliased-scan",
            sql: "SELECT o.ShipCity AS ship_city FROM Orders AS o",
            results: [Self.text(0, "ship_city")]
        )
        let report = try planReport(queries: [aliased])
        let diagnostic = try XCTUnwrap(report.diagnostics.first)

        XCTAssertEqual(diagnostic.alias, "o")
        XCTAssertEqual(diagnostic.table, "Orders")
    }

    // MARK: - The row threshold

    func testTheScanThresholdIsWhatDecidesAScanDiagnostic() throws {
        let strict = try planReport(
            queries: [Self.scansSmallTable],
            settings: SQLiteBuildValidationPlanDiagnosticSettings(
                fullTableScanRowThreshold: 1
            )
        )
        XCTAssertEqual(strict.diagnostics.map(\.code), [.fullTableScan])
        XCTAssertEqual(strict.diagnostics.first?.tableRowCount, 8)

        let lenient = try planReport(
            queries: [Self.scansLargeTable],
            settings: SQLiteBuildValidationPlanDiagnosticSettings(
                fullTableScanRowThreshold: 100_000
            )
        )
        XCTAssertTrue(lenient.diagnostics.isEmpty)
    }

    // MARK: - Suppression

    func testAPerQuerySuppressionSilencesOneDiagnosticAndLeavesTheOthers() throws {
        let settings = SQLiteBuildValidationPlanDiagnosticSettings(
            suppressions: [
                SQLiteBuildValidationPlanSuppression(
                    code: .fullTableScan,
                    queryID: "d.order-by-ship-city",
                    reason: "This export deliberately reads the whole table once."
                ),
            ]
        )
        let report = try planReport(queries: Self.corpus, settings: settings)

        XCTAssertEqual(codes(report, for: "d.order-by-ship-city"), [.tempBTreeForOrderBy])
        // Every other statement keeps its findings.
        XCTAssertEqual(codes(report, for: "a.scan-orders"), [.fullTableScan])
        XCTAssertEqual(codes(report, for: "f.group-by-ship-city"), [.fullTableScan, .tempBTreeForGroupBy])

        XCTAssertEqual(report.suppressedDiagnostics.count, 1)
        XCTAssertEqual(
            report.suppressedDiagnostics.first?.reason,
            "This export deliberately reads the whole table once."
        )
        XCTAssertEqual(report.suppressedDiagnostics.first?.diagnostic.code, .fullTableScan)
        XCTAssertTrue(report.unusedSuppressions.isEmpty)
    }

    func testAPerTableSuppressionSilencesEveryQueryThatScansThatTable() throws {
        let settings = SQLiteBuildValidationPlanDiagnosticSettings(
            suppressions: [
                SQLiteBuildValidationPlanSuppression(
                    code: .fullTableScan,
                    table: "Orders",
                    reason: "Orders is scanned by design in the reporting queries."
                ),
            ]
        )
        let report = try planReport(queries: Self.corpus, settings: settings)

        XCTAssertTrue(report.diagnostics.allSatisfy { $0.code != .fullTableScan })
        XCTAssertEqual(
            report.diagnostics.map(\.code).sorted { $0.rawValue < $1.rawValue },
            [.correlatedScalarSubquery, .tempBTreeForGroupBy, .tempBTreeForOrderBy]
                .sorted { $0.rawValue < $1.rawValue }
        )
    }

    /// A suppression that no longer silences anything is an instruction to
    /// ignore a finding that has been fixed. The report names it so a
    /// reviewer can delete it.
    func testAStaleSuppressionIsReportedAsUnused() throws {
        let stale = SQLiteBuildValidationPlanSuppression(
            code: .fullTableScan,
            queryID: "no-such-query",
            reason: "Left behind by a rename."
        )
        let report = try planReport(
            queries: [Self.scansLargeTable],
            settings: SQLiteBuildValidationPlanDiagnosticSettings(suppressions: [stale])
        )

        XCTAssertEqual(report.unusedSuppressions, [stale])
        XCTAssertEqual(report.diagnostics.count, 1)
    }

    func testASuppressionMustNameAScopeAndAReason() throws {
        XCTAssertThrowsError(
            try SQLiteBuildValidationPlanSuppressions(suppressions: [
                SQLiteBuildValidationPlanSuppression(code: .fullTableScan, reason: "because"),
            ]).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationPlanSuppressionError,
                .rulesEverything(code: "plan.full-table-scan")
            )
        }

        XCTAssertThrowsError(
            try SQLiteBuildValidationPlanSuppressions(suppressions: [
                SQLiteBuildValidationPlanSuppression(
                    code: .fullTableScan,
                    table: "Orders",
                    reason: "   "
                ),
            ]).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationPlanSuppressionError,
                .missingReason(code: "plan.full-table-scan")
            )
        }
    }

    func testSuppressionsRoundTripThroughTheirCheckedInFile() throws {
        let suppressions = SQLiteBuildValidationPlanSuppressions(suppressions: [
            SQLiteBuildValidationPlanSuppression(
                code: .tempBTreeForOrderBy,
                queryID: "a.scan-orders",
                reason: "The result set is at most a handful of rows."
            ),
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-suppressions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(suppressions).write(to: url)

        XCTAssertEqual(
            try SQLiteBuildValidationPlanSuppressions.decode(contentsOf: url),
            suppressions
        )
    }

    // MARK: - Advice never becomes a verdict

    func testAdvisoryDiagnosticsLeaveTheReportAndExitStatusAlone() throws {
        try Support.withValidatorOwnedNorthwindURL { url in
            let manifest = Support.manifest(queries: Self.corpus)
            let result = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )
            let planReport = try XCTUnwrap(result.planReport)

            XCTAssertFalse(planReport.diagnostics.isEmpty)
            XCTAssertEqual(result.report.overallVerdict, .passed)
            XCTAssertEqual(
                SQLiteBuildValidationValidatorCLIRunResult(
                    report: result.report,
                    planReport: planReport
                ).exitCode,
                0
            )
            XCTAssertEqual(
                try result.report.canonicalJSONData(),
                try SQLiteBuildValidator.run(
                    manifest: manifest,
                    againstDatabaseAt: url,
                    capturesPlans: false
                ).report.canonicalJSONData()
            )
        }
    }

    /// A shape the classifier did not recognise carries no advice, and the
    /// diagnostic model itself refuses to express one.
    func testNoDiagnosticFiresOnAnUnclassifiedShape() {
        let unclassified = SQLiteBuildValidationPlanNode(
            detail: "SCAN Orders USING SOMETHING SQLITE HAS NOT SHIPPED YET",
            shape: .unclassified,
            attributes: SQLiteBuildValidationPlanAttributes(table: "Orders"),
            children: []
        )
        let diagnostics = SQLiteBuildValidationPlanDiagnoser.diagnostics(
            for: Self.scansLargeTable,
            roots: [unclassified],
            tableRowCounts: ["Orders": 830],
            settings: .init()
        )

        XCTAssertTrue(diagnostics.isEmpty)
        XCTAssertFalse(
            SQLiteBuildValidationPlanDiagnosticCode.allCases
                .map(\.shape)
                .contains(.unclassified)
        )
    }

    /// A full scan whose alias this validator cannot resolve has no row count
    /// to compare, so it produces nothing rather than a finding resting on an
    /// assumed table size.
    func testAnUnresolvableAliasProducesNoScanDiagnostic() {
        let node = SQLiteBuildValidationPlanNode(
            detail: "SCAN t9",
            shape: .fullTableScan,
            attributes: SQLiteBuildValidationPlanAttributes(table: "t9"),
            children: []
        )
        let diagnostics = SQLiteBuildValidationPlanDiagnoser.diagnostics(
            for: Self.scansLargeTable,
            roots: [node],
            tableRowCounts: ["Orders": 830],
            settings: .init()
        )

        XCTAssertTrue(diagnostics.isEmpty)
    }

    // MARK: - Determinism

    func testRepeatedRunsProduceByteIdenticalDiagnostics() throws {
        let settings = SQLiteBuildValidationPlanDiagnosticSettings(
            suppressions: [
                SQLiteBuildValidationPlanSuppression(
                    code: .fullTableScan,
                    table: "Orders",
                    reason: "Deliberate."
                ),
            ]
        )
        let first = try planReport(queries: Self.corpus, settings: settings)
        let second = try planReport(queries: Self.corpus.reversed(), settings: settings)

        XCTAssertEqual(try first.canonicalJSONData(), try second.canonicalJSONData())
    }

    func testTheSidecarWithDiagnosticsRoundTripsThroughItsCanonicalJSON() throws {
        let report = try planReport(queries: Self.corpus)
        let data = try report.canonicalJSONData()
        let decoded = try JSONDecoder().decode(
            SQLiteBuildValidationPlanReport.self,
            from: data
        )

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(try decoded.canonicalJSONData(), data)
    }
}
