//
//  SQLNilComparisonTests.swift
//
//  Issue #847: `expression == nil` and `expression != nil` test the expression
//  for NULL in SQL, as `isNull()` and `notNull()` do. Before, Swift's own
//  `Optional == nil` compared the expression value itself with `nil`, which is
//  a constant, so the clause rendered `WHERE 0` or `WHERE 1`.
//
//  The renderings are pinned for every operand shape, the results run against
//  real SQLite, and plain Swift comparisons of an optional with `nil` are
//  checked to stay Swift's own.
//

import Foundation
import XCTest
import GRDB
@_spi(GRDB) import SwiftQL


final class XLNilComparisonTests: XCTestCase {

    var databasePool: DatabasePool!
    var database: GRDBDatabase!
    var fileURL: URL!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
        if let fileURL {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
            }
        }
        fileURL = nil
    }

    private func encode(_ statement: any XLEncodable) throws -> String {
        try XLDialectEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(statement).sql
    }

    /// The `WHERE` clause SwiftQL renders for a predicate over the pair table.
    private func renderedPredicate(
        _ predicate: @escaping (OptionalEqualityPair.MetaNamedResult) -> any XLSQLiteExpression<Bool>
    ) throws -> String {
        let statement = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            Select(pair)
            From(pair)
            Where(predicate(pair))
        }
        return try encode(statement)
    }

    private func where_(_ sql: String) -> String {
        let marker = " WHERE "
        guard let range = sql.range(of: marker) else {
            return sql
        }
        return String(sql[range.upperBound...])
    }

    // MARK: - Rendering

    func testComparisonWithNilRendersANullTestOnAnOptionalColumn() throws {
        XCTAssertEqual(where_(try renderedPredicate { $0.left == nil }), #"("t0"."left" ISNULL)"#)
        XCTAssertEqual(where_(try renderedPredicate { $0.left != nil }), #"("t0"."left" NOTNULL)"#)
    }

    /// A named binding is its own expression type, so the test is pinned for
    /// it too: `:value ISNULL` asks whether the bound value is NULL.
    func testComparisonWithNilRendersANullTestOnANamedBinding() throws {
        let value = XLNamedBindingReference<Int?>(name: "value")
        XCTAssertEqual(where_(try renderedPredicate { _ in value == nil }), #"(:value ISNULL)"#)
        XCTAssertEqual(where_(try renderedPredicate { _ in nil != value }), #"(:value NOTNULL)"#)
    }

    func testComparisonWithNilOnTheLeftRendersTheSameNullTest() throws {
        XCTAssertEqual(where_(try renderedPredicate { nil == $0.left }), #"("t0"."left" ISNULL)"#)
        XCTAssertEqual(where_(try renderedPredicate { nil != $0.left }), #"("t0"."left" NOTNULL)"#)
    }

    /// A column that is not optional is tested too: SQLite evaluates the test,
    /// rather than Swift folding the comparison to a constant.
    func testComparisonWithNilRendersANullTestOnARequiredColumn() throws {
        XCTAssertEqual(where_(try renderedPredicate { $0.required == nil }), #"("t0"."required" ISNULL)"#)
        XCTAssertEqual(where_(try renderedPredicate { $0.required != nil }), #"("t0"."required" NOTNULL)"#)
    }

    func testComparisonWithNilRendersANullTestOnAComposedExpression() throws {
        XCTAssertEqual(
            where_(try renderedPredicate { ($0.left == $0.right) == nil }),
            #"(("t0"."left" == "t0"."right") ISNULL)"#
        )
        XCTAssertEqual(
            where_(try renderedPredicate { ($0.required + 1) != nil }),
            #"(("t0"."required" + 1) NOTNULL)"#
        )
    }

    /// The test written inline in a `Where` clause, as a client writes it, and
    /// inside an `&&` chain.
    func testComparisonWithNilInsideAWhereClauseAndAChain() throws {
        let inline = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            Select(pair)
            From(pair)
            Where(pair.left == nil)
        }
        XCTAssertEqual(where_(try encode(inline)), #"("t0"."left" ISNULL)"#)

        let chain = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            Select(pair)
            From(pair)
            Where(pair.left == nil && pair.right != nil && pair.required == 3)
        }
        XCTAssertEqual(
            where_(try encode(chain)),
            #"((("t0"."left" ISNULL) AND ("t0"."right" NOTNULL)) AND ("t0"."required" == 3))"#
        )
    }

    /// The comparison renders what `isNull()` and `notNull()` render.
    func testComparisonWithNilMatchesIsNullAndNotNull() throws {
        XCTAssertEqual(
            try renderedPredicate { $0.left == nil },
            try renderedPredicate { $0.left.isNull() }
        )
        XCTAssertEqual(
            try renderedPredicate { $0.left != nil },
            try renderedPredicate { $0.left.notNull() }
        )
    }

    /// A NULL test is never NULL, so it is typed `Bool`. Swift's `Bool` is an
    /// expression too, so the node's type is checked: a Swift `Bool` here
    /// would mean that Swift's own `Optional == nil` won.
    func testComparisonWithNilIsANullTestTypedBool() {
        let pair = XLSchema(dialect: XLSQLiteDialect.self).table(OptionalEqualityPair.self)
        XCTAssertTrue((pair.left == nil) is XLNullTestExpression<Bool>)
        XCTAssertTrue((pair.left != nil) is XLNullTestExpression<Bool>)
        XCTAssertTrue((nil == pair.required) is XLNullTestExpression<Bool>)
        XCTAssertTrue((nil != (pair.required + 1)) is XLNullTestExpression<Bool>)
    }

    #if compiler(>=6.3)
    /// The second dialect's overloads are generated from the same template
    /// with `@_disfavoredOverload`. From Swift 6.3 they still win over Swift's
    /// own `Optional == nil` for that dialect's columns. Swift 6.1 ranks a
    /// disfavored overload below Swift's own, so there the comparison is
    /// Swift's constant and the compiler warns. Only the test dialects are
    /// disfavored; SQLite's overloads are not.
    func testComparisonWithNilIsANullTestInADisfavoredDialect() {
        let gauge = XLSchema(dialect: FakeSecondDialect.self).table(FakeDialectGauge.self)
        XCTAssertTrue((gauge.label == nil) is XLNullTestExpression<Bool>)
        XCTAssertTrue((gauge.code != nil) is XLNullTestExpression<Bool>)
    }
    #endif

    // MARK: - Results

    private func createPairs() throws {
        try databasePool.write { db in
            try db.execute(sql: """
                CREATE TABLE OptionalEqualityPair (
                    id INTEGER PRIMARY KEY,
                    required INTEGER NOT NULL,
                    "left" INTEGER,
                    "right" INTEGER
                )
                """)
        }
        for pair in [
            OptionalEqualityPair(id: 1, required: 3, left: 3, right: 3),
            OptionalEqualityPair(id: 2, required: 3, left: 3, right: nil),
            OptionalEqualityPair(id: 3, required: 3, left: nil, right: 3),
            OptionalEqualityPair(id: 4, required: 3, left: nil, right: nil),
        ] {
            try database.makeRequest(with: sqlInsert(pair)).execute()
        }
    }

    private func ids(
        _ predicate: @escaping (OptionalEqualityPair.MetaNamedResult) -> any XLSQLiteExpression<Bool>
    ) throws -> [Int] {
        let statement = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            Select(pair)
            From(pair)
            Where(predicate(pair))
            OrderBy(pair.id.ascending())
        }
        return try database.makeRequest(with: statement).fetchAll().map(\.id)
    }

    func testComparisonWithNilSelectsTheNullRows() throws {
        try createPairs()
        XCTAssertEqual(try ids { $0.left == nil }, [3, 4])
        XCTAssertEqual(try ids { $0.left != nil }, [1, 2])
        XCTAssertEqual(try ids { nil == $0.right }, [2, 4])
        XCTAssertEqual(try ids { $0.left == nil && $0.right != nil }, [3])
        XCTAssertEqual(try ids { $0.required == nil }, [])
        XCTAssertEqual(try ids { $0.required != nil }, [1, 2, 3, 4])
        // The plain comparison of two columns is NULL when either is NULL.
        XCTAssertEqual(try ids { ($0.left == $0.right) == nil }, [2, 3, 4])
    }

    // MARK: - Swift values

    /// A Swift optional compared with `nil` stays Swift's own comparison, and
    /// yields a `Bool`, inside and outside a `sql { }` closure.
    func testComparisonOfASwiftOptionalWithNilStaysASwiftBool() throws {
        let missing: Int? = nil
        let present: String? = "a"

        let isMissing = missing == nil
        let isPresent = present != nil
        XCTAssertTrue(type(of: isMissing) == Bool.self)
        XCTAssertTrue(isMissing)
        XCTAssertTrue(isPresent)
        XCTAssertTrue(nil == missing)
        XCTAssertEqual([missing, 3].filter { $0 != nil }.count, 1)
        // A Swift value that is not optional is an expression too. In a
        // condition it is still Swift's own comparison.
        XCTAssertEqual([1, 2].filter { $0 != nil }.count, 2)
        guard present != nil else {
            return XCTFail("present is not nil")
        }

        let statement = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            let threshold = missing == nil ? 3 : 4
            let bound = present != nil ? 5 : 6
            Select(pair)
            From(pair)
            Where(pair.required == threshold && pair.id < bound)
        }
        XCTAssertEqual(
            where_(try encode(statement)),
            #"(("t0"."required" == 3) AND ("t0"."id" < 5))"#
        )
    }
}
