import XCTest
import SwiftQLSQLiteEQPVariancePrototype
@testable import SwiftQLSQLitePlanShapePrototype


final class EQPPlanShapeClassifierTests: XCTestCase {
    // MARK: - Real #390 evidence

    /// The strongest evidence this classifier can offer: every one of the
    /// 214 real statements' EQP rows, captured from a real SQLite build
    /// against the pinned Northwind snapshot, classifies to a named shape —
    /// not one falls through to `.unclassified`.
    func testEveryRealCaptureRowClassifiesWithoutFallingBackToUnclassified() throws {
        let run = try loadCapture("capture_apple-system-3.51.0.json")
        var unclassifiedDetails: [String] = []

        for statement in run.statements {
            let plan = EQPPlanShapeClassifier.classify(rows: statement.rows, statementID: statement.statementID)
            for root in plan.roots {
                collectUnclassified(root, into: &unclassifiedDetails)
            }
        }

        XCTAssertTrue(
            unclassifiedDetails.isEmpty,
            "unexpected unclassified detail(s): \(unclassifiedDetails)"
        )
    }

    func testClassificationIsDeterministicAcrossRepeatedRuns() throws {
        let run = try loadCapture("capture_apple-system-3.51.0.json")
        let statement = try XCTUnwrap(run.statements.first)

        let first = EQPPlanShapeClassifier.classify(rows: statement.rows, statementID: statement.statementID)
        let second = EQPPlanShapeClassifier.classify(rows: statement.rows, statementID: statement.statementID)
        XCTAssertEqual(first, second)
    }

    /// Reconciles with #390 Finding 1: the five-table join's EQP rows have
    /// different raw `id`/`parent` values between the two real SQLite builds
    /// (apple-system-3.51.0 vs homebrew-3.53.2), but the classifier's
    /// normalised plan — which never encodes `id`/`parent` — is byte-for-byte
    /// identical, because the table/index/constraint structure genuinely did
    /// not change.
    func testIDRenumberedJoinStatementNormalisesIdenticallyAcrossBuilds() throws {
        let appleRun = try loadCapture("capture_apple-system-3.51.0.json")
        let homebrewRun = try loadCapture("capture_homebrew-3.53.2.json")
        let statementID = "c390.northwind.join.customer-order-employee-product"

        let appleRows = try XCTUnwrap(appleRun.statements.first { $0.statementID == statementID }).rows
        let homebrewRows = try XCTUnwrap(homebrewRun.statements.first { $0.statementID == statementID }).rows
        XCTAssertNotEqual(appleRows, homebrewRows, "precondition: raw rows must actually differ (id renumbering)")

        let applePlan = EQPPlanShapeClassifier.classify(rows: appleRows, statementID: statementID)
        let homebrewPlan = EQPPlanShapeClassifier.classify(rows: homebrewRows, statementID: statementID)
        XCTAssertEqual(applePlan, homebrewPlan)

        // Also pins the extracted structured detail for this real statement,
        // proving "index search with the index identity and constrained
        // columns" against actual SQLite output, not a synthetic example.
        let searches = applePlan.roots.filter { $0.shape == .indexSearch }
        XCTAssertEqual(searches.count, 5, "one SEARCH per joined table: o, c, e, d, p")
        XCTAssertTrue(searches.contains {
            $0.attributes.table == "c"
                && $0.attributes.indexName == "sqlite_autoindex_Customers_1"
                && $0.attributes.constrainedColumns == ["CustomerID"]
        })
        XCTAssertTrue(searches.contains {
            $0.attributes.table == "o"
                && $0.attributes.indexName == "INTEGER PRIMARY KEY"
                && $0.attributes.constrainedColumns == ["rowid"]
        })
    }

    /// Reconciles with #390 Finding 2: the two builds render a CTE ×
    /// UNION/EXCEPT/INTERSECT compound query with a materially different
    /// structure (legacy `COMPOUND QUERY`/`<OP> USING TEMP B-TREE` vs.
    /// `MERGE (<OP>)`/`USE TEMP B-TREE FOR ORDER BY`). Both classify fully
    /// (no `unclassified`), which is the point: the classifier's job is to
    /// name what changed, not to claim it didn't.
    func testCompoundQueryVarianceClassifiesFullyOnBothBuildsButDiffers() throws {
        let appleRun = try loadCapture("capture_apple-system-3.51.0.json")
        let homebrewRun = try loadCapture("capture_homebrew-3.53.2.json")
        let statementID = "c191.v1.cte.ordinary-nullable.union"

        let appleRows = try XCTUnwrap(appleRun.statements.first { $0.statementID == statementID }).rows
        let homebrewRows = try XCTUnwrap(homebrewRun.statements.first { $0.statementID == statementID }).rows

        let applePlan = EQPPlanShapeClassifier.classify(rows: appleRows, statementID: statementID)
        let homebrewPlan = EQPPlanShapeClassifier.classify(rows: homebrewRows, statementID: statementID)

        XCTAssertNotEqual(applePlan, homebrewPlan)
        for plan in [applePlan, homebrewPlan] {
            for root in plan.roots {
                var unclassified: [String] = []
                collectUnclassified(root, into: &unclassified)
                XCTAssertTrue(unclassified.isEmpty)
            }
        }

        let appleShapes = Set(allShapes(in: applePlan))
        let homebrewShapes = Set(allShapes(in: homebrewPlan))
        XCTAssertTrue(appleShapes.contains(.tempBTreeForCompoundOperation))
        XCTAssertFalse(homebrewShapes.contains(.tempBTreeForCompoundOperation))
        XCTAssertTrue(appleShapes.contains(.compoundQueryStrategy))
        XCTAssertTrue(homebrewShapes.contains(.compoundQueryStrategy))
    }

    // MARK: - Synthetic fixtures: shapes not observed in the real 3.51.0/3.53.2 pair

    /// Illustrative only: the real corpus's WHERE clauses always hit either
    /// the rowid or an existing named index, so `automatic_index` (SQLite's
    /// on-the-fly ephemeral index) was never exercised.
    func testSyntheticAutomaticCoveringIndexIsClassified() {
        let (shape, attributes) = EQPPlanShapeClassifier.classifyDetail(
            "SEARCH t1 USING AUTOMATIC COVERING INDEX (x=?)",
            parentShape: nil
        )
        XCTAssertEqual(shape, .automaticCoveringIndex)
        XCTAssertEqual(attributes.table, "t1")
        XCTAssertEqual(attributes.constrainedColumns, ["x"])
        XCTAssertTrue(attributes.isAutomatic)
        XCTAssertTrue(attributes.isCovering)
    }

    /// Illustrative only: no case in the real corpus references a CTE more
    /// than once in a way that makes SQLite choose materialization over a
    /// coroutine.
    func testSyntheticMaterializedCTEIsClassified() {
        let (shape, _) = EQPPlanShapeClassifier.classifyDetail("MATERIALIZE cte0", parentShape: nil)
        XCTAssertEqual(shape, .materializedSubqueryOrCTE)
    }

    /// Illustrative only: every scalar subquery in the real corpus is
    /// uncorrelated (see `scalar_subquery: 1, correlated_scalar_subquery: 0`
    /// in both checked-in plan evidence files). This exercises the
    /// parent-shape heuristic directly: a "SCALAR SUBQUERY" node nested
    /// under a row-looping parent (a table scan or index search) is
    /// classified as correlated; the same detail text under a non-looping
    /// parent (or no parent) is not.
    func testSyntheticCorrelatedScalarSubqueryUsesParentShapeHeuristic() {
        let (uncorrelated, _) = EQPPlanShapeClassifier.classifyDetail("SCALAR SUBQUERY 1", parentShape: nil)
        XCTAssertEqual(uncorrelated, .scalarSubquery)

        let (correlated, _) = EQPPlanShapeClassifier.classifyDetail(
            "SCALAR SUBQUERY 1",
            parentShape: .fullTableScan
        )
        XCTAssertEqual(correlated, .correlatedScalarSubquery)
    }

    /// Proves the fallback path itself: a detail string this classifier
    /// genuinely does not recognise must surface as `.unclassified` with the
    /// raw text preserved, never coerced into one of the named shapes.
    func testTrulyUnrecognisedDetailSurfacesAsUnclassified() {
        let nonsense = "BOGUS FUTURE SQLITE OPCODE #12345"
        let (shape, attributes) = EQPPlanShapeClassifier.classifyDetail(nonsense, parentShape: nil)
        XCTAssertEqual(shape, .unclassified)
        XCTAssertNil(attributes.table)

        let node = EQPPlanNode(detail: nonsense, shape: shape, attributes: attributes, children: [])
        XCTAssertEqual(node.detail, nonsense, "raw detail must be preserved even when unclassified")
    }

    func testUnrecognisedUsingClauseIsUnclassifiedNotCoerced() {
        let (shape, attributes) = EQPPlanShapeClassifier.classifyDetail(
            "SEARCH t0 USING SOME FUTURE ACCESS METHOD (x=?)",
            parentShape: nil
        )
        XCTAssertEqual(shape, .unclassified)
        XCTAssertEqual(attributes.table, "t0", "table is still captured for audit even when the access method is unrecognised")
    }
}


private func collectUnclassified(_ node: EQPPlanNode, into details: inout [String]) {
    if node.shape == .unclassified {
        details.append(node.detail)
    }
    for child in node.children {
        collectUnclassified(child, into: &details)
    }
}


private func allShapes(_ node: EQPPlanNode) -> [EQPPlanShapeKind] {
    [node.shape] + node.children.flatMap(allShapes)
}


private func allShapes(in plan: EQPPlan) -> [EQPPlanShapeKind] {
    plan.roots.flatMap(allShapes)
}


func loadCapture(_ name: String) throws -> EQPCaptureRun {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Evidence") else {
        throw EQPPlanShapeFixtureError.missingResource(name)
    }
    return try JSONDecoder().decode(EQPCaptureRun.self, from: Data(contentsOf: url))
}


enum EQPPlanShapeFixtureError: Error {
    case missingResource(String)
}
