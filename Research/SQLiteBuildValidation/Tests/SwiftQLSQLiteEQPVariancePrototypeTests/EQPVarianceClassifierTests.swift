import XCTest
import SwiftQLSQLiteBuildValidationPrototype
import SwiftQLSQLiteEQPVariancePrototype


final class EQPVarianceClassifierTests: XCTestCase {
    // MARK: - Real evidence

    /// Replays the actual observed variance between two real, distinct
    /// SQLite builds captured on this host (Apple system libsqlite3 3.51.0
    /// vs. Homebrew's 3.53.2, both against the same pinned Northwind copy —
    /// see `capture_eqp.py` and `SQLiteEQPVariance.md`). This is not a
    /// synthetic fixture: it is the literal evidence checked in alongside
    /// this test, so a change to the classifier's heuristics that would
    /// mis-classify real, observed variance is caught here.
    func testClassifiesRealObservedVarianceBetweenTwoSQLiteBuilds() throws {
        let baseline = try loadEvidence("capture_apple-system-3.51.0.json")
        let comparison = try loadEvidence("capture_homebrew-3.53.2.json")

        let comparisons = try EQPVarianceClassifier.compare(baseline: baseline, comparison: comparison)
        XCTAssertEqual(comparisons.count, 214)

        var counts: [EQPVarianceDifferenceClass: Int] = [:]
        for entry in comparisons {
            counts[entry.classification, default: 0] += 1
        }

        // Exactly what was observed: 203 statements produced byte-identical
        // plans, 2 produced the same plan renumbered, and 9 (all CTE
        // compound-query cases: UNION/EXCEPT/INTERSECT) used a materially
        // different compound-execution strategy between the two builds.
        XCTAssertEqual(counts[.identical], 203)
        XCTAssertEqual(counts[.idRenumberingOnly], 2)
        XCTAssertEqual(counts[.materializationStrategyChange], 9)
        XCTAssertEqual(counts[.accessPathChange] ?? 0, 0)
        XCTAssertEqual(counts[.joinOrderChange] ?? 0, 0)
        XCTAssertEqual(counts[.cosmeticWordingChange] ?? 0, 0)
        XCTAssertEqual(counts[.unclassified] ?? 0, 0)
    }

    func testIDRenumberingCaseIsTheFiveTableJoinAndTheScalarSubquery() throws {
        let baseline = try loadEvidence("capture_apple-system-3.51.0.json")
        let comparison = try loadEvidence("capture_homebrew-3.53.2.json")
        let comparisons = try EQPVarianceClassifier.compare(baseline: baseline, comparison: comparison)

        let renumbered = comparisons
            .filter { $0.classification == .idRenumberingOnly }
            .map(\.statementID)
            .sorted()

        XCTAssertEqual(renumbered, [
            "c390.northwind.join.customer-order-employee-product",
            "c390.northwind.subquery.products-above-average",
        ])
    }

    func testComparingIdenticalRunsProducesOnlyIdenticalClassifications() throws {
        let run = try loadEvidence("capture_apple-system-3.51.0.json")
        let comparisons = try EQPVarianceClassifier.compare(baseline: run, comparison: run)
        XCTAssertTrue(comparisons.allSatisfy { $0.classification == .identical })
    }

    func testMismatchedStatementSetsThrow() {
        let baseline = EQPCaptureRun(
            label: "a",
            captureMethod: "test",
            runtimeMetadata: .fixture(),
            statements: [EQPStatementCapture(statementID: "only-in-baseline", rows: [])]
        )
        let comparison = EQPCaptureRun(
            label: "b",
            captureMethod: "test",
            runtimeMetadata: .fixture(),
            statements: [EQPStatementCapture(statementID: "only-in-comparison", rows: [])]
        )
        XCTAssertThrowsError(try EQPVarianceClassifier.compare(baseline: baseline, comparison: comparison))
    }

    // MARK: - Synthetic fixtures for axes not observed in the real 3.51.0/3.53.2 pair

    /// Illustrative only: this exact shape was not observed between the two
    /// real SQLite builds captured for #390. It exists so the classifier's
    /// access-path-change branch has a unit test independent of whatever
    /// variance a future SQLite pairing happens to produce.
    func testSyntheticAccessPathChangeIsClassified() {
        let baseline = [
            EQPRow(id: 1, parent: 0, notused: 0, detail: "SEARCH t0 USING INDEX ix_a (col=?)"),
        ]
        let comparison = [
            EQPRow(id: 1, parent: 0, notused: 0, detail: "SEARCH t0 USING INDEX ix_b (col=?)"),
        ]
        XCTAssertEqual(
            EQPVarianceClassifier.classify(baselineRows: baseline, comparisonRows: comparison),
            .accessPathChange
        )
    }

    func testSyntheticJoinOrderChangeIsClassified() {
        let baseline = [
            EQPRow(id: 1, parent: 0, notused: 0, detail: "SCAN t0"),
            EQPRow(id: 2, parent: 0, notused: 0, detail: "SEARCH t1 USING INTEGER PRIMARY KEY (rowid=?)"),
        ]
        let comparison = [
            EQPRow(id: 1, parent: 0, notused: 0, detail: "SCAN t1"),
            EQPRow(id: 2, parent: 0, notused: 0, detail: "SEARCH t0 USING INTEGER PRIMARY KEY (rowid=?)"),
        ]
        XCTAssertEqual(
            EQPVarianceClassifier.classify(baselineRows: baseline, comparisonRows: comparison),
            .joinOrderChange
        )
    }

    func testSyntheticCosmeticWordingChangeIsClassified() {
        let baseline = [
            EQPRow(id: 1, parent: 0, notused: 0, detail: "SCAN t0"),
        ]
        let comparison = [
            EQPRow(id: 7, parent: 0, notused: 0, detail: "SCAN t0 (~1000000 rows)"),
        ]
        XCTAssertEqual(
            EQPVarianceClassifier.classify(baselineRows: baseline, comparisonRows: comparison),
            .cosmeticWordingChange
        )
    }

    func testSyntheticIdenticalRowsAreIdentical() {
        let rows = [EQPRow(id: 1, parent: 0, notused: 0, detail: "SCAN t0")]
        XCTAssertEqual(
            EQPVarianceClassifier.classify(baselineRows: rows, comparisonRows: rows),
            .identical
        )
    }
}


private func loadEvidence(_ name: String) throws -> EQPCaptureRun {
    let url = try pinnedEvidenceURL(named: name)
    return try JSONDecoder().decode(EQPCaptureRun.self, from: Data(contentsOf: url))
}


extension SQLiteBuildValidationRuntimeMetadata {
    static func fixture() -> SQLiteBuildValidationRuntimeMetadata {
        SQLiteBuildValidationRuntimeMetadata(
            sqliteVersion: "0.0.0",
            sqliteSourceID: "test-fixture",
            compileOptions: [],
            functions: [],
            collations: [],
            moduleNames: [],
            extensionNames: [],
            schemaRowCount: 0,
            schemaFNV1A64: "0000000000000000"
        )
    }
}
