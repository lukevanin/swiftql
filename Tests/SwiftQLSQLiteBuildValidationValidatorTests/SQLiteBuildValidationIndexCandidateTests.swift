//
//  SQLiteBuildValidationIndexCandidateTests.swift
//
//  Issue #396: deterministic index candidates derived from the statements
//  behind remediable plan shapes. Proposals only — nothing here is a
//  recommendation, and nothing here touches a database.
//

import Foundation
import GRDB
import SwiftQLCore
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteBuildValidationManifest
import XCTest
@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationIndexPredicateExtractorTests: XCTestCase {
    typealias Extractor = SQLiteBuildValidationIndexPredicateExtractor

    func testEqualityAndRangeComparisonsAreDistinguished() {
        let comparisons = Extractor.whereComparisons(
            for: "o",
            in: "SELECT o.ShipCity FROM Orders o WHERE o.CustomerID = :customer AND o.Freight > 10"
        )

        XCTAssertEqual(comparisons.map(\.column), ["CustomerID", "Freight"])
        XCTAssertEqual(comparisons.map(\.kind), [.equality, .range])
    }

    func testTheQuotedParenthesisedStyleSwiftQLRendersIsRead() {
        let comparisons = Extractor.whereComparisons(
            for: "t0",
            in: """
                SELECT "t0"."ShipCity" FROM "Orders" AS "t0" \
                WHERE (("t0"."CustomerID" == :customer) AND ("t0"."Freight" >= 10))
                """
        )

        XCTAssertEqual(comparisons.map(\.column), ["CustomerID", "Freight"])
        XCTAssertEqual(comparisons.map(\.kind), [.equality, .range])
    }

    /// A disjunction does not constrain an index seek the way a conjunction
    /// does, and this extractor does not try to work out which `OR` matters.
    func testAWhereClauseContainingORYieldsNoComparisons() {
        XCTAssertTrue(
            Extractor.whereComparisons(
                for: "o",
                in: "SELECT o.ShipCity FROM Orders o WHERE o.CustomerID = :c OR o.EmployeeID = :e"
            ).isEmpty
        )
    }

    func testJoinKeysAreReadFromBothSidesOfTheCondition() {
        let sql = "SELECT c.CategoryName FROM Categories c LEFT JOIN Products p ON p.CategoryID = c.CategoryID"

        XCTAssertEqual(Extractor.joinKeys(for: "p", in: sql).map(\.column), ["CategoryID"])
        XCTAssertEqual(Extractor.joinKeys(for: "c", in: sql).map(\.column), ["CategoryID"])
    }

    func testOrderByTermsCarryDirectionAndCollation() {
        let ordering = Extractor.orderByTerms(
            for: "o",
            in: "SELECT o.ShipCity FROM Orders o ORDER BY o.ShipCity COLLATE NOCASE DESC, o.OrderDate ASC"
        )

        XCTAssertTrue(ordering.isComplete)
        XCTAssertEqual(ordering.terms.map(\.column), ["ShipCity", "OrderDate"])
        XCTAssertEqual(ordering.terms.map(\.direction), [.descending, .ascending])
        XCTAssertEqual(ordering.terms.map(\.collation), ["NOCASE", nil])
    }

    /// An index satisfies a sort only from the first term onwards, so a term
    /// this extractor cannot read ends the list rather than being skipped.
    func testAnUnreadableOrderByTermEndsTheListRatherThanBeingSkipped() {
        let ordering = Extractor.orderByTerms(
            for: "o",
            in: "SELECT o.ShipCity FROM Orders o ORDER BY o.ShipCity, LENGTH(o.ShipCity), o.OrderDate"
        )

        XCTAssertFalse(ordering.isComplete)
        XCTAssertEqual(ordering.terms.map(\.column), ["ShipCity"])
    }

    func testATermBelongingToAnotherTableEndsTheList() {
        let ordering = Extractor.orderByTerms(
            for: "o",
            in: "SELECT o.ShipCity FROM Orders o JOIN Customers c ON c.CustomerID = o.CustomerID ORDER BY c.CompanyName, o.ShipCity"
        )

        XCTAssertFalse(ordering.isComplete)
        XCTAssertTrue(ordering.terms.isEmpty)
    }
}


final class SQLiteBuildValidationIndexCandidateTests: XCTestCase {
    typealias Support = SQLiteBuildValidationValidatorTestSupport
    typealias Generator = SQLiteBuildValidationIndexCandidateGenerator

    // MARK: - Column ordering

    /// The settled rule: equality-style columns (a `WHERE` equality and a
    /// join key alike) lead, then at most one range column, then the sort.
    func testColumnOrderPutsEqualityThenOneRangeThenOrderBy() {
        let (columns, isComplete) = Generator.candidateColumns(
            for: "o",
            in: """
                SELECT o.ShipCity FROM Orders o \
                WHERE o.CustomerID = 'ALFKI' AND o.Freight > 10 AND o.ShipVia < 3 \
                ORDER BY o.OrderDate DESC
                """
        )

        XCTAssertTrue(isComplete)
        XCTAssertEqual(columns.map(\.name), ["CustomerID", "Freight", "OrderDate"])
        XCTAssertEqual(columns.map(\.direction), [nil, nil, .descending])
    }

    /// A composite index can only be seeded by an equality prefix, and a join
    /// key is an equality constraint, so it must precede the range column.
    func testAJoinKeyPrecedesARangeColumn() {
        let (columns, _) = Generator.candidateColumns(
            for: "p",
            in: """
                SELECT c.CategoryName, p.ProductName \
                FROM Categories c LEFT JOIN Products p ON p.CategoryID = c.CategoryID \
                WHERE p.UnitPrice > 20
                """
        )

        XCTAssertEqual(columns.map(\.name), ["CategoryID", "UnitPrice"])
    }

    func testOnlyOneRangeColumnIsEverProposed() {
        let (columns, _) = Generator.candidateColumns(
            for: "o",
            in: "SELECT o.ShipCity FROM Orders o WHERE o.Freight > 10 AND o.ShipVia < 3"
        )

        XCTAssertEqual(columns.map(\.name), ["Freight"])
    }

    // MARK: - DDL rendering

    func testDDLQuotesSpacedAndUnicodeIdentifiers() {
        let candidate = SQLiteBuildValidationIndexCandidate(
            table: "Order Details",
            columns: [
                SQLiteBuildValidationIndexCandidateColumn(name: "OrderID"),
                SQLiteBuildValidationIndexCandidateColumn(
                    name: "Bestellmenge",
                    direction: .descending,
                    collation: "NOCASE"
                ),
            ],
            sourceQueryIDs: ["q"],
            sourceDescriptorIdentities: ["d"],
            representativeQueryID: "q",
            representativeAlias: "od"
        )

        XCTAssertTrue(candidate.ddl.contains("ON \"Order Details\""))
        XCTAssertTrue(candidate.ddl.contains("\"OrderID\""))
        XCTAssertTrue(candidate.ddl.contains("\"Bestellmenge\" COLLATE \"NOCASE\" DESC"))
    }

    /// A name folded from identifiers that differ only in punctuation would
    /// otherwise collide with another candidate on the same table.
    func testALossyFoldedIndexNameCarriesADigestSoItStaysUnique() {
        func candidate(column: String) -> SQLiteBuildValidationIndexCandidate {
            SQLiteBuildValidationIndexCandidate(
                table: "T",
                columns: [SQLiteBuildValidationIndexCandidateColumn(name: column)],
                sourceQueryIDs: ["q"],
                sourceDescriptorIdentities: ["d"],
                representativeQueryID: "q",
                representativeAlias: "t"
            )
        }

        XCTAssertNotEqual(
            candidate(column: "a b").indexName,
            candidate(column: "a_b").indexName
        )
        // An ordinary name stays readable, with no digest appended.
        XCTAssertEqual(candidate(column: "OrderID").indexName, "ix_advisor_t_orderid")
    }

    // MARK: - Generation over real plans

    private func candidateSet(
        queries: [SQLiteBuildValidationQueryEntry],
        limits: SQLiteBuildValidationIndexCandidateLimits = .init()
    ) throws -> SQLiteBuildValidationIndexCandidateSet {
        try Support.withValidatorOwnedNorthwindURL { url in
            try XCTUnwrap(
                try SQLiteBuildValidator.run(
                    manifest: Support.manifest(queries: queries),
                    againstDatabaseAt: url,
                    capturesPlans: true,
                    planDiagnosticSettings: SQLiteBuildValidationPlanDiagnosticSettings(
                        candidateLimits: limits
                    )
                ).planReport
            ).indexCandidates
        }
    }

    private static func query(
        _ id: String,
        _ sql: String
    ) -> SQLiteBuildValidationQueryEntry {
        Support.query(
            id: id,
            sql: sql,
            results: [
                Support.result(
                    identity: "result/value",
                    declaredAlias: "value",
                    valueTypeIdentifier: "swift.string",
                    valueTypeName: "Swift.String",
                    nullability: "nullable",
                    storageIdentifier: "text"
                ),
            ]
        )
    }

    func testARepresentativeNorthwindStatementProducesTheExpectedCandidate() throws {
        let set = try candidateSet(queries: [
            Self.query(
                "orders.by-customer-and-employee",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI' AND o.EmployeeID = 5"
            ),
        ])

        XCTAssertEqual(set.candidates.count, 1)
        let candidate = try XCTUnwrap(set.candidates.first)
        XCTAssertEqual(candidate.table, "Orders")
        XCTAssertEqual(candidate.columns.map(\.name), ["CustomerID", "EmployeeID"])
        XCTAssertEqual(
            candidate.ddl,
            "CREATE INDEX \"ix_advisor_orders_customerid_employeeid\" ON \"Orders\" (\"CustomerID\", \"EmployeeID\")"
        )
        XCTAssertEqual(candidate.sourceQueryIDs, ["orders.by-customer-and-employee"])
    }

    func testACandidateSharedByTwoStatementsIsVisiblyShared() throws {
        let set = try candidateSet(queries: [
            Self.query(
                "a.ship-city",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI'"
            ),
            Self.query(
                "b.ship-name",
                "SELECT o.ShipName AS value FROM Orders o WHERE o.CustomerID = 'ALFKI'"
            ),
        ])

        XCTAssertEqual(set.candidates.count, 1)
        XCTAssertEqual(
            set.candidates.first?.sourceQueryIDs,
            ["a.ship-city", "b.ship-name"]
        )
        XCTAssertEqual(set.candidates.first?.sourceDescriptorIdentities.count, 2)
    }

    /// A wider index already serves every query the narrower prefix would, so
    /// keeping both is redundant — and the prefix's statements must still be
    /// attributed to the index that now serves them.
    func testAPrefixCandidateCollapsesIntoTheWiderOneAndKeepsItsAttribution() throws {
        let set = try candidateSet(queries: [
            Self.query(
                "a.narrow",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI'"
            ),
            Self.query(
                "b.wide",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI' AND o.EmployeeID = 5"
            ),
        ])

        XCTAssertEqual(set.candidates.count, 1)
        let candidate = try XCTUnwrap(set.candidates.first)
        XCTAssertEqual(candidate.columns.map(\.name), ["CustomerID", "EmployeeID"])
        XCTAssertEqual(candidate.sourceQueryIDs, ["a.narrow", "b.wide"])
    }

    func testEverySpaceContainingIdentifierRendersDDLRealSQLiteCanPrepare() throws {
        let set = try candidateSet(queries: [
            Self.query(
                "order-details.by-product",
                """
                SELECT od.Quantity AS value FROM "Order Details" od \
                WHERE od.ProductID = 11 ORDER BY od.UnitPrice DESC
                """
            ),
            Self.query(
                "orders.by-customer",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI'"
            ),
        ])

        XCTAssertTrue(set.candidates.contains { $0.table == "Order Details" })
        try NorthwindFixture.withTemporaryCopy { copy in
            try copy.databasePool.read { database in
                for candidate in set.candidates {
                    // Preparing proves the DDL is well formed against the real
                    // schema. It creates nothing: verification, and the only
                    // place an index is ever created, is #397's.
                    XCTAssertNoThrow(
                        try database.makeStatement(sql: candidate.ddl),
                        candidate.ddl
                    )
                }
            }
        }
    }

    // MARK: - Bounds, declines, and shapes

    func testExceedingTheColumnLimitTruncatesAndSaysSo() throws {
        let set = try candidateSet(
            queries: [
                Self.query(
                    "wide",
                    """
                    SELECT o.ShipCity AS value FROM Orders o \
                    WHERE o.CustomerID = 'ALFKI' AND o.EmployeeID = 5 AND o.ShipVia = 3
                    """
                ),
            ],
            limits: SQLiteBuildValidationIndexCandidateLimits(maximumColumns: 2)
        )

        XCTAssertEqual(set.candidates.first?.columns.count, 2)
        XCTAssertEqual(set.truncations.count, 1)
        XCTAssertEqual(set.truncations.first?.kind, .columns)
        XCTAssertEqual(set.truncations.first?.limit, 2)
        XCTAssertEqual(set.truncations.first?.observed, 3)
    }

    func testAStatementWithNothingToIndexIsDeclinedWithAReason() throws {
        let set = try candidateSet(queries: [
            Self.query("plain-scan", "SELECT o.ShipCity AS value FROM Orders o"),
        ])

        XCTAssertTrue(set.candidates.isEmpty)
        XCTAssertEqual(set.declines.count, 1)
        XCTAssertEqual(set.declines.first?.table, "Orders")
        XCTAssertTrue(
            try XCTUnwrap(set.declines.first?.reason).contains("nothing to index")
        )
    }

    func testAnUnreadableOrderingIsDeclinedRatherThanPartiallyProposed() throws {
        let set = try candidateSet(queries: [
            Self.query(
                "expression-order",
                "SELECT o.ShipCity AS value FROM Orders o ORDER BY LENGTH(o.ShipCity)"
            ),
        ])

        XCTAssertTrue(set.candidates.isEmpty)
        XCTAssertEqual(set.declines.count, 1)
        XCTAssertTrue(
            try XCTUnwrap(set.declines.first?.reason).contains("ORDER BY")
        )
    }

    /// Only a shape the classifier recognised as remediable can motivate a
    /// candidate.
    func testNoCandidateComesFromAnUnrecognisedShape() {
        let unclassified = SQLiteBuildValidationPlanNode(
            detail: "SCAN o USING SOMETHING SQLITE HAS NOT SHIPPED YET",
            shape: .unclassified,
            attributes: SQLiteBuildValidationPlanAttributes(table: "o"),
            children: []
        )
        let query = Self.query(
            "unclassified",
            "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI'"
        )
        let set = Generator.generate(
            queries: [query],
            planRoots: [query.id: [unclassified]]
        )

        XCTAssertTrue(set.candidates.isEmpty)
        XCTAssertTrue(set.declines.isEmpty)
        XCTAssertFalse(Generator.remediableShapes.contains(.unclassified))
    }

    // MARK: - Determinism

    func testCandidateSetsAreIndependentOfManifestOrdering() throws {
        let queries = [
            Self.query(
                "a.narrow",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI'"
            ),
            Self.query(
                "b.wide",
                "SELECT o.ShipCity AS value FROM Orders o WHERE o.CustomerID = 'ALFKI' AND o.EmployeeID = 5"
            ),
            Self.query(
                "c.details",
                "SELECT od.Quantity AS value FROM \"Order Details\" od WHERE od.ProductID = 11"
            ),
        ]
        let forward = try candidateSet(queries: queries)
        let reversed = try candidateSet(queries: queries.reversed())

        XCTAssertEqual(
            try JSONEncoder.canonical.encode(forward),
            try JSONEncoder.canonical.encode(reversed)
        )
        XCTAssertEqual(
            forward.candidates.map(\.representativeQueryID),
            reversed.candidates.map(\.representativeQueryID)
        )
    }
}


extension JSONEncoder {
    /// The same deterministic encoding the sidecar itself uses, so two
    /// candidate sets can be compared as bytes.
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
