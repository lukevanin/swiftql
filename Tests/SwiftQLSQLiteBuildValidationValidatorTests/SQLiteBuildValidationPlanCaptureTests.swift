//
//  SQLiteBuildValidationPlanCaptureTests.swift
//
//  Issue #394: a normalised EXPLAIN QUERY PLAN record per manifest entry,
//  in a sidecar, that adds data without touching a correctness verdict.
//

import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationPlanShapeClassifierTests: XCTestCase {
    typealias Classifier = SQLiteBuildValidationPlanShapeClassifier

    func testScanAndSearchDetailsAreClassifiedWithTheirTable() {
        let (scanShape, scanAttributes) = Classifier.classify(
            detail: "SCAN Customers",
            parentShape: nil
        )
        XCTAssertEqual(scanShape, .fullTableScan)
        XCTAssertEqual(scanAttributes.table, "Customers")

        let (searchShape, searchAttributes) = Classifier.classify(
            detail: "SEARCH Orders USING INDEX ix_orders_customer (CustomerID=?)",
            parentShape: nil
        )
        XCTAssertEqual(searchShape, .indexSearch)
        XCTAssertEqual(searchAttributes.table, "Orders")
        XCTAssertEqual(searchAttributes.indexName, "ix_orders_customer")
        XCTAssertEqual(searchAttributes.constrainedColumns, ["CustomerID"])
        XCTAssertFalse(searchAttributes.isCovering)
    }

    func testCoveringAndAutomaticIndexFormsAreDistinguished() {
        let (coveringShape, coveringAttributes) = Classifier.classify(
            detail: "SCAN Products USING COVERING INDEX ix_products_name",
            parentShape: nil
        )
        XCTAssertEqual(coveringShape, .coveringIndexScan)
        XCTAssertTrue(coveringAttributes.isCovering)
        XCTAssertFalse(coveringAttributes.isAutomatic)

        let (automaticShape, automaticAttributes) = Classifier.classify(
            detail: "SEARCH p USING AUTOMATIC COVERING INDEX (CategoryID=?)",
            parentShape: nil
        )
        XCTAssertEqual(automaticShape, .automaticCoveringIndex)
        XCTAssertTrue(automaticAttributes.isAutomatic)
        XCTAssertEqual(automaticAttributes.constrainedColumns, ["CategoryID"])
    }

    func testTempBTreeDetailsAreClassifiedByTheirPurpose() {
        let cases: [(String, SQLiteBuildValidationPlanShape)] = [
            ("USE TEMP B-TREE FOR ORDER BY", .tempBTreeForOrderBy),
            ("USE TEMP B-TREE FOR GROUP BY", .tempBTreeForGroupBy),
            ("USE TEMP B-TREE FOR count(DISTINCT)", .tempBTreeForDistinctAggregate),
            ("UNION USING TEMP B-TREE", .tempBTreeForCompoundOperation),
        ]
        for (detail, expected) in cases {
            XCTAssertEqual(
                Classifier.classify(detail: detail, parentShape: nil).0,
                expected,
                detail
            )
        }
    }

    /// The parent shape is the only thing that separates the two, and it is
    /// the whole reason classification takes one.
    func testScalarSubqueryIsCorrelatedOnlyUnderARowLoopingParent() {
        XCTAssertEqual(
            Classifier.classify(detail: "SCALAR SUBQUERY 1", parentShape: nil).0,
            .scalarSubquery
        )
        XCTAssertEqual(
            Classifier.classify(
                detail: "SCALAR SUBQUERY 1",
                parentShape: .fullTableScan
            ).0,
            .correlatedScalarSubquery
        )
        XCTAssertEqual(
            Classifier.classify(
                detail: "SCALAR SUBQUERY 1",
                parentShape: .tempBTreeForOrderBy
            ).0,
            .scalarSubquery
        )
    }

    /// Detail text this classifier has never seen must stay `unclassified`.
    /// Coercing it into a neighbouring shape is how a diagnostic later fires
    /// on something it never actually recognized.
    func testUnrecognizedDetailIsUnclassifiedRatherThanCoerced() {
        let (shape, attributes) = Classifier.classify(
            detail: "SCAN Orders USING SOMETHING SQLITE HAS NOT SHIPPED YET",
            parentShape: nil
        )
        XCTAssertEqual(shape, .unclassified)
        XCTAssertEqual(attributes.table, "Orders")

        XCTAssertEqual(
            Classifier.classify(detail: "ENTIRELY NOVEL NODE", parentShape: nil).0,
            .unclassified
        )
    }

    /// Adjacency comes from each row's own `parent`, not from row order, so
    /// the same rows in a different emission order build the same tree.
    func testTreeIsBuiltFromParentIDsAndNotRowOrder() {
        let rows = [
            SQLiteBuildValidationPlanRow(id: 3, parent: 2, detail: "SCAN Orders"),
            SQLiteBuildValidationPlanRow(id: 2, parent: 0, detail: "SCAN Customers"),
        ]
        let roots = Classifier.classify(rows: rows)

        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.attributes.table, "Customers")
        XCTAssertEqual(roots.first?.children.first?.attributes.table, "Orders")
    }
}


final class SQLiteBuildValidationPlanCaptureTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport

    private static let scanQuery = Support.query(
        id: "orders-scan",
        sql: "SELECT ShipCity AS ship_city FROM Orders ORDER BY ShipCity",
        results: [
            Support.result(
                identity: "result/ship_city",
                declaredAlias: "ship_city",
                valueTypeIdentifier: "swift.string",
                valueTypeName: "Swift.String",
                nullability: "nullable",
                storageIdentifier: "text"
            ),
        ]
    )

    private static let trivialQuery = Support.query(
        id: "trivial",
        sql: "SELECT 1 AS value"
    )

    // MARK: - Every entry carries a record

    func testEveryManifestEntryCarriesAPlanRecord() throws {
        let manifest = Support.manifest(queries: [Self.scanQuery, Self.trivialQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let result = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )
            let planReport = try XCTUnwrap(result.planReport)

            XCTAssertEqual(
                planReport.records.map(\.queryID),
                ["orders-scan", "trivial"]
            )
            XCTAssertEqual(
                planReport.capturedRecords.count + planReport.unsupportedRecords.count,
                planReport.records.count,
                "every record is either captured or explicitly unsupported"
            )
            XCTAssertTrue(planReport.unsupportedRecords.isEmpty)
        }
    }

    func testAScannedAndSortedStatementNormalisesToItsRealShapes() throws {
        let manifest = Support.manifest(queries: [Self.scanQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let result = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )
            let record = try XCTUnwrap(result.planReport?.records.first)
            let roots = try XCTUnwrap(record.outcome.capturedRoots)

            XCTAssertTrue(
                roots.contains { $0.shape == .fullTableScan && $0.attributes.table == "Orders" },
                "expected a full table scan of Orders, got \(roots.map(\.detail))"
            )
            XCTAssertTrue(
                roots.contains { $0.shape == .tempBTreeForOrderBy },
                "expected a temp B-tree for ORDER BY, got \(roots.map(\.detail))"
            )
            XCTAssertFalse(
                roots.contains { $0.shape == .unclassified },
                "no node of a real Northwind statement should be unclassified"
            )
        }
    }

    // MARK: - Provenance

    func testPlanProvenanceIdentifiesTheSQLiteThatProducedIt() throws {
        let manifest = Support.manifest(queries: [Self.trivialQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let result = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )
            let record = try XCTUnwrap(result.planReport?.records.first)
            let provenance = try XCTUnwrap(record.provenance)
            let runtimeMetadata = try XCTUnwrap(result.report.runtimeMetadata)

            XCTAssertEqual(provenance.sqliteVersion, runtimeMetadata.sqliteVersion)
            XCTAssertEqual(provenance.sqliteSourceID, runtimeMetadata.sqliteSourceID)
            XCTAssertFalse(provenance.sqliteVersion.isEmpty)
            XCTAssertFalse(provenance.sqliteSourceID.isEmpty)
        }
    }

    /// The record keeps the options that can change a plan and drops the ones
    /// that cannot, so a reader can tell which planner inputs were in force
    /// without wading through the connection's whole option list.
    func testProvenanceKeepsOnlyPlanRelevantCompileOptions() {
        XCTAssertTrue(SQLiteBuildValidationPlanProvenance.isPlanRelevant("ENABLE_STAT4"))
        XCTAssertTrue(SQLiteBuildValidationPlanProvenance.isPlanRelevant("enable_fts5"))
        XCTAssertTrue(SQLiteBuildValidationPlanProvenance.isPlanRelevant("OMIT_AUTOMATIC_INDEX"))
        XCTAssertFalse(SQLiteBuildValidationPlanProvenance.isPlanRelevant("THREADSAFE=1"))
        XCTAssertFalse(SQLiteBuildValidationPlanProvenance.isPlanRelevant("ENABLE_COLUMN_METADATA"))

        let metadata = SQLiteBuildValidationRuntimeMetadata(
            sqliteVersion: "3.99.0",
            sqliteSourceID: "abc",
            compileOptions: ["THREADSAFE=1", "ENABLE_STAT4", "ENABLE_COLUMN_METADATA"],
            functions: [],
            collations: [],
            moduleNames: [],
            extensionNames: [],
            schemaRowCount: 0,
            schemaFNV1A64: "0"
        )
        XCTAssertEqual(
            SQLiteBuildValidationPlanProvenance(metadata).compileOptions,
            ["ENABLE_STAT4"]
        )
    }

    // MARK: - Unsupported, never absent and never silently passed

    func testAStatementWhosePlanCannotBeCapturedIsExplicitlyUnsupported() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                id: "missing-table",
                sql: "SELECT * FROM tests_totally_missing_table"
            ),
        ])

        try Support.withValidatorOwnedNorthwindURL { url in
            let result = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )
            let record = try XCTUnwrap(result.planReport?.records.first)

            XCTAssertNil(record.outcome.capturedRoots)
            let reason = try XCTUnwrap(record.outcome.unsupportedReason)
            XCTAssertTrue(
                reason.contains("EXPLAIN QUERY PLAN"),
                "the reason should name what failed, got: \(reason)"
            )
            // The correctness report still owns the verdict.
            XCTAssertEqual(result.report.overallVerdict, .failed)
        }
    }

    /// Planning against a snapshot already known not to match the manifest
    /// would produce records that look like evidence and are not.
    func testASchemaIdentityMismatchMakesEveryPlanRecordUnsupported() throws {
        let manifest = SQLiteBuildValidationManifest(
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: Support.schemaSnapshot(
                databaseSHA256: String(repeating: "0", count: 64)
            ),
            queries: [Self.trivialQuery, Self.scanQuery]
        )

        try Support.withValidatorOwnedNorthwindURL { url in
            let result = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )
            let planReport = try XCTUnwrap(result.planReport)

            XCTAssertEqual(planReport.records.count, 2)
            XCTAssertTrue(planReport.capturedRecords.isEmpty)
            for record in planReport.records {
                XCTAssertEqual(
                    record.outcome.unsupportedReason,
                    "Plan capture was skipped because the database snapshot's schema identity does not match the manifest.",
                    record.queryID
                )
            }
        }
    }

    /// A captured plan must always name the SQLite that produced it, so the
    /// record model cannot express one that does not.
    func testACapturedOutcomeRequiresProvenance() {
        let outcome = SQLiteBuildValidationPlanCaptureOutcome.unsupported(reason: "nothing to plan")
        let record = SQLiteBuildValidationPlanRecord(
            queryID: "q",
            definitionIdentity: "d",
            descriptorIdentity: "s",
            provenance: nil,
            outcome: outcome
        )
        XCTAssertNil(record.provenance)
        XCTAssertEqual(record.outcome.unsupportedReason, "nothing to plan")
    }

    // MARK: - Plan capture changes no verdict

    func testCapturingPlansLeavesTheCorrectnessReportByteIdentical() throws {
        let manifest = Support.manifest(queries: [Self.scanQuery, Self.trivialQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let withoutPlans = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: false
            )
            let withPlans = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )

            XCTAssertNil(withoutPlans.planReport)
            XCTAssertNotNil(withPlans.planReport)
            XCTAssertEqual(
                try withoutPlans.report.canonicalJSONData(),
                try withPlans.report.canonicalJSONData()
            )
        }
    }

    func testCapturingPlansLeavesAFailingRunFailingAndNoWorse() throws {
        let manifest = Support.manifest(queries: [
            Support.query(id: "missing-table", sql: "SELECT * FROM tests_totally_missing_table"),
        ])

        try Support.withValidatorOwnedNorthwindURL { url in
            let withoutPlans = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: false
            )
            let withPlans = try SQLiteBuildValidator.run(
                manifest: manifest,
                againstDatabaseAt: url,
                capturesPlans: true
            )

            XCTAssertEqual(withoutPlans.report.overallVerdict, .failed)
            XCTAssertEqual(
                try withoutPlans.report.canonicalJSONData(),
                try withPlans.report.canonicalJSONData()
            )
        }
    }

    // MARK: - Determinism

    func testRepeatedRunsProduceByteIdenticalPlanSidecars() throws {
        let manifest = Support.manifest(queries: [Self.scanQuery, Self.trivialQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let first = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: manifest,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )
            let second = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: manifest,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )

            XCTAssertEqual(
                try first.canonicalJSONData(),
                try second.canonicalJSONData()
            )
        }
    }

    func testPlanRecordsAreOrderedByQueryIDRegardlessOfManifestOrder() throws {
        let ascending = Support.manifest(queries: [Self.scanQuery, Self.trivialQuery])
        let descending = Support.manifest(queries: [Self.trivialQuery, Self.scanQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let first = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: ascending,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )
            let second = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: descending,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )

            XCTAssertEqual(
                try first.canonicalJSONData(),
                try second.canonicalJSONData()
            )
        }
    }

    func testPlanSidecarRoundTripsThroughItsCanonicalJSON() throws {
        let manifest = Support.manifest(queries: [Self.scanQuery])

        try Support.withValidatorOwnedNorthwindURL { url in
            let planReport = try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: manifest,
                    againstDatabaseAt: url,
                    capturesPlans: true
                ).planReport
            )
            let data = try planReport.canonicalJSONData()
            let decoded = try JSONDecoder().decode(
                SQLiteBuildValidationPlanReport.self,
                from: data
            )

            XCTAssertEqual(decoded, planReport)
            XCTAssertEqual(try decoded.canonicalJSONData(), data)
        }
    }
}
