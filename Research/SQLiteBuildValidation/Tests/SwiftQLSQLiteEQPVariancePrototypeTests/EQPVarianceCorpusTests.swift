import XCTest
import SwiftQLSQLiteEQPVariancePrototype


final class EQPVarianceCorpusTests: XCTestCase {
    func testCorpusAssemblyIsDeterministic() throws {
        let first = try EQPVarianceCorpus.assemble()
        let second = try EQPVarianceCorpus.assemble()
        XCTAssertEqual(first, second)
    }

    /// Pins the corpus size so an accidental #191 manifest regeneration or a
    /// dropped Northwind anchor is caught immediately, rather than silently
    /// shrinking the evidence this issue's "Done When" bullets depend on.
    func testCorpusCombinesCombinatorialCasesAndNorthwindAnchors() throws {
        let corpus = try EQPVarianceCorpus.assemble()
        let combinatorial = corpus.filter { $0.source == .combinatorial }
        let anchors = corpus.filter { $0.source == .northwindAnchor }

        XCTAssertEqual(combinatorial.count, 208)
        XCTAssertEqual(anchors.count, 6)
        XCTAssertEqual(corpus.count, 214)
        XCTAssertEqual(Set(corpus.map(\.id)).count, corpus.count, "statement ids must be unique")
    }

    func testCorpusIsSortedByID() throws {
        let corpus = try EQPVarianceCorpus.assemble()
        XCTAssertEqual(corpus.map(\.id), corpus.map(\.id).sorted())
    }

    func testNorthwindAnchorsCoverJoinCTEAndSubqueryShapes() {
        let anchorIDs = Set(
            EQPVarianceCorpus.northwindAnchorStatements()
                .flatMap(\.northwindAnchorCaseIDs)
        )
        // These are the exact case identities #254's fixture registry assigns
        // to the join/CTE/subquery/compound shapes this corpus reuses from
        // NorthwindSemanticCorpusTests, so the linkage in Required Approach
        // ("reusing stable feature/case identities") is checked, not assumed.
        XCTAssertEqual(anchorIDs, [
            "northwind.join.customer-order-employee-product",
            "northwind.join.left-null-manager",
            "northwind.aggregate.grouped-having",
            "northwind.subquery.products-above-average",
            "northwind.compound.customer-supplier-cities",
            "northwind.cte.order-subtotals",
        ])
    }
}
