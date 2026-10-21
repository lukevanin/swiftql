import Foundation
import SwiftQLTestSupport
import GRDB
import XCTest
@_spi(GRDB) @testable import SwiftQL


@SQLTable(name: "NumericCoercionRow")
private struct NumericCoercionRow: Equatable {
    let id: Int
    let ratio: Double
    let count: Int
}


@SQLTable(name: "NumericCoercionAffinity")
private struct NumericCoercionAffinity: Equatable {
    let id: Int
    let ratio: Double
    let name: String
    let payload: Data
    let note: String?
}


/// A column builder written before `column(name:nullable:storage:)` existed:
/// it implements only the two-argument requirement.
private struct TwoArgumentColumnBuilder: XLColumnDefinitionsBuilder {
    private var columns: [String] = []

    func build() -> String {
        columns.joined(separator: ", ")
    }

    mutating func column(name: XLName, nullable: Bool) {
        columns.append(nullable ? name.rawValue : "\(name.rawValue) NOT NULL")
    }
}


/// Names the storage of a column through a dialect known only as an
/// `XLSQLDialect`, as generated code in a generic context sees it.
private func columnStorage<Dialect>(
    of type: Any.Type,
    in dialect: Dialect.Type
) -> XLValueStorageIdentifier? where Dialect: XLSQLDialect {
    _xlColumnStorage(of: type, in: dialect)
}


/// Issue #690: the default fetch path and a static row layout read a number
/// by one rule. An INTEGER read as a `Double`, and a REAL that is exactly an
/// integer read as an `Int`, decode on both. A REAL that is not exactly an
/// integer throws on both, instead of truncating on one.
final class NumericCoercionGRDBTests: XCTestCase {

    /// A table with no declared column types, as an older SwiftQL created, so
    /// SQLite keeps each value in the storage class it was written with:
    /// row 1 has an INTEGER in `ratio` and a REAL in `count`.
    private func makeFixture() throws -> (
        fixture: TemporaryDatabaseFixture,
        database: GRDBDatabase
    ) {
        let fixture = try TemporaryDatabaseFixture.make(named: "numeric-coercion")
        try fixture.pool.write { db in
            try db.execute(sql: "CREATE TABLE NumericCoercionRow (id, ratio, count)")
            try db.execute(
                sql: """
                    INSERT INTO NumericCoercionRow (id, ratio, count)
                    VALUES (1, 3, 4.0), (2, 2.5, 42.75), (3, 1e30, 5), (4, 7, 1e30)
                    """
            )
        }
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        return (fixture, database)
    }

    private func selectRows(
        _ database: GRDBDatabase,
        id: Int
    ) throws -> [NumericCoercionRow] {
        let statement: any XLQueryStatement<NumericCoercionRow> = sql { schema in
            let table = schema.table(NumericCoercionRow.self)
            Select(table)
            From(table)
            Where(table.id == id)
        }
        return try database.makeRequest(with: statement).fetchAll()
    }

    private func staticRows(
        _ database: GRDBDatabase,
        id: Int
    ) throws -> [NumericCoercionRow] {
        let table = XLSchema().table(NumericCoercionRow.self, as: "reading")
        let layout = try NumericCoercionRow.staticRowLayout(
            using: XLSQLiteDialect.self,
            id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
                selecting: table.id,
                identifiedBy: XLQuerySlotIdentity(path: ["numeric-coercion", "id"])
            ),
            ratio: XLStaticSelectField<Double, Double, XLSQLiteDialect>.intrinsic(
                selecting: table.ratio,
                identifiedBy: XLQuerySlotIdentity(path: ["numeric-coercion", "ratio"])
            ),
            count: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
                selecting: table.count,
                identifiedBy: XLQuerySlotIdentity(path: ["numeric-coercion", "count"])
            )
        )
        let statement = sql { _ in
            Select(layout)
            From(table)
            Where(table.id == id)
        }
        let encoding = try XLiteEncoder(dialect: database.dialect)
            .makeValidatedSQL(statement)
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "numeric-coercion", "row"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: layout.metadata.results,
            cardinality: .many
        )
        let prepared = try database.prepareInvocation(
            with: XLTypedStaticQueryDescriptor(
                descriptor: descriptor,
                layout: layout
            )
        )
        return try prepared.fetchAll(bindings: prepared.makeInvocationBindings())
    }

    func testIntegerInADoubleAndRealInAnIntReadIdenticallyOnBothPaths() throws {
        let (fixture, database) = try makeFixture()
        defer { fixture.tearDown() }

        // The fixture holds the shape the issue describes: the `Double`
        // column's value is an INTEGER and the `Int` column's value is a REAL.
        let storage = try XCTUnwrap(
            try fixture.pool.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT typeof(ratio) AS ratio, typeof(count) AS count FROM NumericCoercionRow WHERE id = 1"
                )
            }
        )
        XCTAssertEqual(storage["ratio"] as String, "integer")
        XCTAssertEqual(storage["count"] as String, "real")

        let expected = [NumericCoercionRow(id: 1, ratio: 3.0, count: 4)]
        XCTAssertEqual(try selectRows(database, id: 1), expected)
        XCTAssertEqual(try staticRows(database, id: 1), expected)
    }

    func testARealThatIsNotExactlyAnIntegerThrowsOnBothPaths() throws {
        let (fixture, database) = try makeFixture()
        defer { fixture.tearDown() }

        // Row 2 holds 42.75 in the `Int` column, which one path used to
        // truncate to 42. Row 4 holds 1e30, which is outside `Int`'s range.
        for id in [2, 4] {
            XCTAssertThrowsError(try selectRows(database, id: id), "select, row \(id)") { error in
                XCTAssertTrue(error is XLColumnReadError, "Expected a column read error, got \(error)")
            }
            XCTAssertThrowsError(try staticRows(database, id: id), "static layout, row \(id)") { error in
                guard case .resultStorageMismatch(_, let slot, let actual)? =
                    error as? XLStaticQueryInvocationError else {
                    return XCTFail("Expected a result storage mismatch, got \(error)")
                }
                XCTAssertEqual(slot.identity.path.last, "count")
                XCTAssertEqual(actual, XLValueStorageIdentifier(rawValue: "real"))
            }
        }
    }

    func testARealOutsideIntRangeInADoubleColumnStillReads() throws {
        let (fixture, database) = try makeFixture()
        defer { fixture.tearDown() }

        // Row 3: 1e30 is a valid `Double`, in the `ratio` column.
        let expected = [NumericCoercionRow(id: 3, ratio: 1e30, count: 5)]
        XCTAssertEqual(try selectRows(database, id: 3), expected)
        XCTAssertEqual(try staticRows(database, id: 3), expected)
    }

    func testStaticLayoutDecodesNumbersByTheSameRuleWithoutADatabase() throws {
        let table = XLSchema().table(NumericCoercionRow.self, as: "reading")
        let layout = try NumericCoercionRow.staticRowLayout(
            using: XLSQLiteDialect.self,
            id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
                selecting: table.id,
                identifiedBy: XLQuerySlotIdentity(path: ["numeric-coercion", "id"])
            ),
            ratio: XLStaticSelectField<Double, Double, XLSQLiteDialect>.intrinsic(
                selecting: table.ratio,
                identifiedBy: XLQuerySlotIdentity(path: ["numeric-coercion", "ratio"])
            ),
            count: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
                selecting: table.count,
                identifiedBy: XLQuerySlotIdentity(path: ["numeric-coercion", "count"])
            )
        )

        XCTAssertEqual(
            try layout.decode([.integer(1), .integer(3), .real(4.0)]),
            NumericCoercionRow(id: 1, ratio: 3.0, count: 4)
        )
        XCTAssertThrowsError(
            try layout.decode([.integer(2), .real(2.5), .real(42.75)])
        ) { error in
            guard case .storageMismatch(let field, let actual)? =
                error as? XLStaticRowLayoutError else {
                return XCTFail("Expected a storage mismatch, got \(error)")
            }
            XCTAssertEqual(field.alias, "count")
            XCTAssertEqual(actual, XLValueStorageIdentifier(rawValue: "real"))
        }
        // Only a number converts to a number.
        XCTAssertThrowsError(
            try layout.decode([.integer(1), .text("3"), .integer(4)])
        ) { error in
            guard case .storageMismatch(let field, let actual)? =
                error as? XLStaticRowLayoutError else {
                return XCTFail("Expected a storage mismatch, got \(error)")
            }
            XCTAssertEqual(field.alias, "ratio")
            XCTAssertEqual(actual, XLValueStorageIdentifier(rawValue: "text"))
        }
        // Encoding writes each value in the storage of its own type.
        XCTAssertEqual(
            try layout.encode(NumericCoercionRow(id: 1, ratio: 3.0, count: 4)),
            [.integer(1), .real(3.0), .integer(4)]
        )
    }

    func testGeneratedCreateTableDeclaresTheColumnAffinities() throws {
        let fixture = try TemporaryDatabaseFixture.make(named: "numeric-affinity")
        defer { fixture.tearDown() }
        let database = try GRDBDatabase(
            databasePool: fixture.pool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try database.makeRequest(with: sqlCreate(NumericCoercionAffinity.self)).execute()

        let columns = try fixture.pool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(NumericCoercionAffinity)")
        }
        XCTAssertEqual(
            columns.map { $0["name"] as String },
            ["id", "ratio", "name", "payload", "note"]
        )
        XCTAssertEqual(
            columns.map { $0["type"] as String },
            ["INTEGER", "REAL", "TEXT", "BLOB", "TEXT"]
        )
        XCTAssertEqual(
            columns.map { $0["notnull"] as Int },
            [1, 1, 1, 1, 0]
        )

        // SQLite now normalises storage on write: the integer written to the
        // `Double` column is stored as a REAL.
        try fixture.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO NumericCoercionAffinity (id, ratio, name, payload, note)
                    VALUES (1, 3, 'a', X'00', NULL)
                    """
            )
        }
        let storedType = try fixture.pool.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(ratio) FROM NumericCoercionAffinity")
        }
        XCTAssertEqual(storedType, "real")

        let statement: any XLQueryStatement<NumericCoercionAffinity> = sql { schema in
            let table = schema.table(NumericCoercionAffinity.self)
            Select(table)
            From(table)
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            [
                NumericCoercionAffinity(
                    id: 1,
                    ratio: 3.0,
                    name: "a",
                    payload: Data([0]),
                    note: nil
                ),
            ]
        )
    }

    func testABuilderWithoutStorageSupportKeepsCompilingAndDeclaresNoType() {
        var builder = TwoArgumentColumnBuilder()
        builder.column(name: XLName("a"), nullable: false)
        builder.column(
            name: XLName("b"),
            nullable: true,
            storage: XLValueStorageIdentifier(rawValue: "integer")
        )

        XCTAssertEqual(builder.build(), "a NOT NULL, b")
    }

    func testAColumnsStorageComesFromTheDialectEvenInAGenericContext() {
        let integer = XLValueStorageIdentifier(rawValue: "integer")

        XCTAssertEqual(columnStorage(of: Int.self, in: XLSQLiteDialect.self), integer)
        XCTAssertEqual(columnStorage(of: Bool?.self, in: XLSQLiteDialect.self), integer)
        XCTAssertEqual(
            columnStorage(of: Double.self, in: XLSQLiteDialect.self),
            XLValueStorageIdentifier(rawValue: "real")
        )
        XCTAssertNil(columnStorage(of: Date.self, in: XLSQLiteDialect.self))
    }
}
