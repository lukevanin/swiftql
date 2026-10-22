//
//  SQLOptionalEqualityTests.swift
//
//  Issue #692: an optional `==` or `!=` renders SQL's equality, which yields
//  NULL when either operand is NULL, as the ordering operators do. The
//  NULL-safe comparison has its own names, `isNotDistinctFrom(_:)` and
//  `isDistinctFrom(_:)`, which SQLite spells `IS` and `IS NOT`.
//
//  The renderings are pinned for every operand shape, and the semantics run
//  against real SQLite, which is the only way to see the difference.
//

import Foundation
import XCTest
import GRDB
@_spi(GRDB) import SwiftQL


/// Two nullable columns, so every operand shape (required against optional,
/// optional against required, optional against optional) is available.
@SQLTable(name: "OptionalEqualityPair")
struct OptionalEqualityPair: Equatable {
    let id: Int
    let required: Int
    let left: Int?
    let right: Int?
}


/// What each comparison of `left` and `right` yields for one row.
@SQLResult
struct OptionalEqualityOutcome: Equatable {
    var id: Int
    var equal: Bool?
    var notEqual: Bool?
    var notDistinct: Bool
    var distinct: Bool
}


/// A ticket with an optional voucher. The tickets and redemptions are the
/// models of the join example in the Expressions guide.
@SQLTable(name: "OptionalEqualityTicket")
struct Ticket: Equatable {
    let id: String
    let voucher: String?
}


/// A redemption, which names the voucher it used, if any.
@SQLTable(name: "OptionalEqualityRedemption")
struct Redemption: Equatable {
    let id: String
    let voucher: String?
}


@SQLResult
struct TicketRedemption: Equatable {
    var ticket: String
    var redemption: String?
}


@SQLResult
struct TicketRedemptionInner: Equatable {
    var ticket: String
    var redemption: String
}


final class XLOptionalEqualityTests: XCTestCase {

    var databasePool: DatabasePool!
    var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }

    private func encode(_ statement: any XLEncodable) throws -> String {
        try XLDialectEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(statement).sql
    }

    /// The `WHERE` clause SwiftQL renders for a predicate over the pair table.
    private func renderedPredicate(
        _ predicate: @escaping (OptionalEqualityPair.MetaNamedResult) -> any XLSQLiteExpression<Optional<Bool>>
    ) throws -> String {
        let statement = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            Select(pair)
            From(pair)
            Where(predicate(pair))
        }
        return try encode(statement)
    }

    private func renderedNullSafePredicate(
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

    // MARK: - Optional equality renders SQL's equality

    func testOptionalEqualityRendersEqualityForEveryOperandShape() throws {
        // A required column against an optional one, an optional column
        // against a required one, and two optional columns.
        XCTAssertEqual(
            where_(try renderedPredicate { $0.required == $0.left }),
            #"("t0"."required" == "t0"."left")"#
        )
        XCTAssertEqual(
            where_(try renderedPredicate { $0.left == $0.required }),
            #"("t0"."left" == "t0"."required")"#
        )
        XCTAssertEqual(
            where_(try renderedPredicate { $0.left == $0.right }),
            #"("t0"."left" == "t0"."right")"#
        )
    }

    func testOptionalInequalityRendersInequalityForEveryOperandShape() throws {
        XCTAssertEqual(
            where_(try renderedPredicate { $0.required != $0.left }),
            #"("t0"."required" != "t0"."left")"#
        )
        XCTAssertEqual(
            where_(try renderedPredicate { $0.left != $0.required }),
            #"("t0"."left" != "t0"."required")"#
        )
        XCTAssertEqual(
            where_(try renderedPredicate { $0.left != $0.right }),
            #"("t0"."left" != "t0"."right")"#
        )
    }

    func testOptionalEqualityAgainstALiteralRendersEquality() throws {
        XCTAssertEqual(
            where_(try renderedPredicate { $0.left == 5 }),
            #"("t0"."left" == 5)"#
        )
        XCTAssertEqual(
            where_(try renderedPredicate { $0.left != 5 }),
            #"("t0"."left" != 5)"#
        )
    }

    func testRequiredEqualityIsUnchanged() throws {
        let statement = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            Select(pair)
            From(pair)
            Where(pair.required == pair.id)
        }
        XCTAssertEqual(
            where_(try encode(statement)),
            #"("t0"."required" == "t0"."id")"#
        )
    }

    /// The result type of an optional comparison is `Optional<Bool>`, like the
    /// ordering operators on the same operands, and that now matches the SQL.
    func testOptionalEqualityIsTypedOptionalBool() {
        let _ = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            let _: any XLSQLiteExpression<Optional<Bool>> = pair.left == pair.right
            let _: any XLSQLiteExpression<Optional<Bool>> = pair.left != pair.right
            let _: any XLSQLiteExpression<Optional<Bool>> = pair.left < pair.right
            let _: any XLSQLiteExpression<Bool> = pair.required == pair.id
            Select(pair)
            From(pair)
        }
    }

    // MARK: - The NULL-safe comparison has its own name

    func testNullSafeComparisonRendersIsForEveryOperandShape() throws {
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.required.isNotDistinctFrom($0.left) }),
            #"("t0"."required" IS "t0"."left")"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isNotDistinctFrom($0.required) }),
            #"("t0"."left" IS "t0"."required")"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isNotDistinctFrom($0.right) }),
            #"("t0"."left" IS "t0"."right")"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.required.isNotDistinctFrom($0.id) }),
            #"("t0"."required" IS "t0"."id")"#
        )
    }

    func testNullSafeInequalityRendersIsNotForEveryOperandShape() throws {
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.required.isDistinctFrom($0.left) }),
            #"("t0"."required" IS NOT "t0"."left")"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isDistinctFrom($0.required) }),
            #"("t0"."left" IS NOT "t0"."required")"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isDistinctFrom($0.right) }),
            #"("t0"."left" IS NOT "t0"."right")"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.required.isDistinctFrom($0.id) }),
            #"("t0"."required" IS NOT "t0"."id")"#
        )
    }

    func testNullSafeComparisonAgainstALiteral() throws {
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isNotDistinctFrom(5) }),
            #"("t0"."left" IS 5)"#
        )
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isDistinctFrom(5) }),
            #"("t0"."left" IS NOT 5)"#
        )
        // A NULL operand is a value to the NULL-safe comparison, which is how
        // it asks for a NULL, where `== nil` is Swift's own comparison.
        XCTAssertEqual(
            where_(try renderedNullSafePredicate { $0.left.isNotDistinctFrom(Optional<Int>.none) }),
            #"("t0"."left" IS NULL)"#
        )
    }

    /// Unlike the plain comparison, the NULL-safe one is never NULL, so it is
    /// typed `Bool`.
    func testNullSafeComparisonIsTypedBool() {
        let _ = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            let _: any XLSQLiteExpression<Bool> = pair.left.isNotDistinctFrom(pair.right)
            let _: any XLSQLiteExpression<Bool> = pair.left.isDistinctFrom(pair.right)
            Select(pair)
            From(pair)
        }
    }

    // MARK: - Semantics against SQLite

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
            OptionalEqualityPair(id: 2, required: 3, left: 3, right: 4),
            OptionalEqualityPair(id: 3, required: 3, left: nil, right: 3),
            OptionalEqualityPair(id: 4, required: 3, left: nil, right: nil),
        ] {
            try database.makeRequest(with: sqlInsert(pair)).execute()
        }
    }

    /// Every comparison of two nullable columns, one row for each combination
    /// of equal, different, one NULL and both NULL.
    func testEachComparisonOfTwoNullableColumnsYieldsTheOutcomeSQLDefines() throws {
        try createPairs()
        let statement = sql { schema in
            let pair = schema.table(OptionalEqualityPair.self)
            let outcome = OptionalEqualityOutcome.columns(
                id: pair.id,
                equal: pair.left == pair.right,
                notEqual: pair.left != pair.right,
                notDistinct: pair.left.isNotDistinctFrom(pair.right),
                distinct: pair.left.isDistinctFrom(pair.right)
            )
            Select(outcome)
            From(pair)
            OrderBy(pair.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            [
                // 3 and 3.
                OptionalEqualityOutcome(id: 1, equal: true, notEqual: false, notDistinct: true, distinct: false),
                // 3 and 4.
                OptionalEqualityOutcome(id: 2, equal: false, notEqual: true, notDistinct: false, distinct: true),
                // NULL and 3: the plain comparisons are NULL, the NULL-safe ones are not.
                OptionalEqualityOutcome(id: 3, equal: nil, notEqual: nil, notDistinct: false, distinct: true),
                // NULL and NULL: only the NULL-safe comparison calls them equal.
                OptionalEqualityOutcome(id: 4, equal: nil, notEqual: nil, notDistinct: true, distinct: false),
            ]
        )
    }

    /// A `Where` on a plain comparison excludes the NULL rows, as it does for
    /// every other NULL predicate; the NULL-safe one keeps them.
    func testWhereOnAPlainComparisonExcludesNullRows() throws {
        try createPairs()
        func ids(_ predicate: @escaping (OptionalEqualityPair.MetaNamedResult) -> any XLSQLiteExpression<Optional<Bool>>) throws -> [Int] {
            let statement = sql { schema in
                let pair = schema.table(OptionalEqualityPair.self)
                Select(pair)
                From(pair)
                Where(predicate(pair))
                OrderBy(pair.id.ascending())
            }
            return try database.makeRequest(with: statement).fetchAll().map(\.id)
        }
        func nullSafeIDs(_ predicate: @escaping (OptionalEqualityPair.MetaNamedResult) -> any XLSQLiteExpression<Bool>) throws -> [Int] {
            let statement = sql { schema in
                let pair = schema.table(OptionalEqualityPair.self)
                Select(pair)
                From(pair)
                Where(predicate(pair))
                OrderBy(pair.id.ascending())
            }
            return try database.makeRequest(with: statement).fetchAll().map(\.id)
        }

        // No row has a value other than 3, and the NULL rows are neither equal
        // to 3 nor different from it, so the plain comparison selects none of
        // them while the NULL-safe one counts them as different.
        XCTAssertEqual(try ids { $0.left != 3 }, [])
        XCTAssertEqual(try ids { $0.left != 4 }, [1, 2])
        XCTAssertEqual(try nullSafeIDs { $0.left.isDistinctFrom(4) }, [1, 2, 3, 4])
        XCTAssertEqual(try nullSafeIDs { $0.left.isDistinctFrom(3) }, [3, 4])

        XCTAssertEqual(try ids { $0.left == 3 }, [1, 2])
        XCTAssertEqual(try nullSafeIDs { $0.left.isNotDistinctFrom(3) }, [1, 2])

        // Two NULLs are equal only to the NULL-safe comparison.
        XCTAssertEqual(try ids { $0.left == $0.right }, [1])
        XCTAssertEqual(try nullSafeIDs { $0.left.isNotDistinctFrom($0.right) }, [1, 4])
        XCTAssertEqual(try ids { $0.left != $0.right }, [2])
        XCTAssertEqual(try nullSafeIDs { $0.left.isDistinctFrom($0.right) }, [2, 3])
    }

    // MARK: - A join on two nullable columns

    /// Three tickets and three redemptions. One voucher matches, and two
    /// tickets and two redemptions have none.
    private func createTicketsAndRedemptions() throws {
        try databasePool.write { db in
            try db.execute(sql: """
                CREATE TABLE OptionalEqualityTicket (
                    id TEXT PRIMARY KEY,
                    voucher TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE OptionalEqualityRedemption (
                    id TEXT PRIMARY KEY,
                    voucher TEXT
                )
                """)
        }
        for ticket in [
            Ticket(id: "tk1", voucher: "V-1"),
            Ticket(id: "tk2", voucher: nil),
            Ticket(id: "tk3", voucher: nil),
        ] {
            try database.makeRequest(with: sqlInsert(ticket)).execute()
        }
        for redemption in [
            Redemption(id: "r1", voucher: "V-1"),
            Redemption(id: "r2", voucher: nil),
            Redemption(id: "r3", voucher: nil),
        ] {
            try database.makeRequest(with: sqlInsert(redemption)).execute()
        }
    }

    func testALeftJoinOnTwoNullableColumnsNoLongerMatchesNullToNull() throws {
        try createTicketsAndRedemptions()
        let statement = sql { schema in
            let ticket = schema.table(Ticket.self)
            let redemption = schema.nullableTable(Redemption.self)
            let match = TicketRedemption.columns(
                ticket: ticket.id,
                redemption: redemption.id
            )
            Select(match)
            From(ticket)
            Join.Left(redemption, on: ticket.voucher == redemption.voucher)
            OrderBy(ticket.id.ascending())
        }
        XCTAssertEqual(
            try encode(statement),
            #"SELECT "t0"."id" AS "ticket", "t1"."id" AS "redemption" FROM "OptionalEqualityTicket" AS "t0" LEFT JOIN "OptionalEqualityRedemption" AS "t1" ON ("t0"."voucher" == "t1"."voucher") ORDER BY "t0"."id" ASC"#
        )
        // The tickets with no voucher match no redemption, so each
        // appears once, with no redemption. Before this change, `IS` joined each
        // of them to both redemptions that also had none.
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            [
                TicketRedemption(ticket: "tk1", redemption: "r1"),
                TicketRedemption(ticket: "tk2", redemption: nil),
                TicketRedemption(ticket: "tk3", redemption: nil),
            ]
        )
    }

    func testAnInnerJoinOnTwoNullableColumnsMatchesOnlyTheSharedValue() throws {
        try createTicketsAndRedemptions()
        let statement = sql { schema in
            let ticket = schema.table(Ticket.self)
            let redemption = schema.table(Redemption.self)
            let match = TicketRedemptionInner.columns(
                ticket: ticket.id,
                redemption: redemption.id
            )
            Select(match)
            From(ticket)
            Join.Inner(redemption, on: ticket.voucher == redemption.voucher)
            OrderBy(ticket.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            [TicketRedemptionInner(ticket: "tk1", redemption: "r1")]
        )
    }

    /// The NULL-safe form is how a join says that two NULLs match, and it
    /// matches every pair, as `IS` did.
    func testAJoinOnTheNullSafeComparisonMatchesNullToNull() throws {
        try createTicketsAndRedemptions()
        let statement = sql { schema in
            let ticket = schema.table(Ticket.self)
            let redemption = schema.nullableTable(Redemption.self)
            let match = TicketRedemption.columns(
                ticket: ticket.id,
                redemption: redemption.id
            )
            Select(match)
            From(ticket)
            Join.Left(redemption, on: ticket.voucher.isNotDistinctFrom(redemption.voucher))
            OrderBy(ticket.id.ascending(), redemption.id.ascending())
        }
        XCTAssertEqual(
            try encode(statement),
            #"SELECT "t0"."id" AS "ticket", "t1"."id" AS "redemption" FROM "OptionalEqualityTicket" AS "t0" LEFT JOIN "OptionalEqualityRedemption" AS "t1" ON ("t0"."voucher" IS "t1"."voucher") ORDER BY "t0"."id" ASC, "t1"."id" ASC"#
        )
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            [
                TicketRedemption(ticket: "tk1", redemption: "r1"),
                TicketRedemption(ticket: "tk2", redemption: "r2"),
                TicketRedemption(ticket: "tk2", redemption: "r3"),
                TicketRedemption(ticket: "tk3", redemption: "r2"),
                TicketRedemption(ticket: "tk3", redemption: "r3"),
            ]
        )
    }
}
