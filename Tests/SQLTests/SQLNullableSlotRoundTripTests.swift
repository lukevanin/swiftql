//
//  SQLNullableSlotRoundTripTests.swift
//
//  Issue #828: reading a nullable column's `Setting` slot and assigning it
//  back keeps the value, against real SQLite. A nullable column is read only
//  as an optional-typed expression, so the read is what was assigned; the
//  read of a column never assigned, assigned to a nullable column, sets it
//  to that column's current value, which the `SET` clause names. That a possibly-`NULL` read cannot be
//  assigned to a NOT NULL column is proved by
//  scripts/ci/check-dialect-type-parameter-type-safety.sh.
//

import Foundation
import XCTest
import GRDB
@_spi(GRDB) import SwiftQL


@SQLTable(name: "SlotRoundTripPerson")
struct SlotRoundTripPerson: Equatable {
    let id: String
    let name: String
    let nickname: String?
    let alias: String?
}


/// Another model with a nullable column of the same name and type.
@SQLTable(name: "SlotRoundTripPet")
struct SlotRoundTripPet: Equatable {
    let id: String
    let nickname: String?
}


/// A model with a nullable column of a type whose storage form differs from
/// its expression form: `Date` is stored as text and read through
/// `julianday`, and written back through `strftime` (SQLExampleTests.swift).
@SQLTable(name: "SlotRoundTripEvent")
struct SlotRoundTripEvent: Equatable {
    let id: String
    let at: Date?
}


final class XLNullableSlotRoundTripTests: XCTestCase {

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

    /// Creates the table with a key, for the upsert, and stores one row with
    /// non-`NULL` nullable columns and one with `NULL` ones.
    private func createRows() throws {
        try databasePool.write { db in
            try db.execute(sql: """
                CREATE TABLE SlotRoundTripPerson (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    nickname TEXT,
                    alias TEXT
                )
                """)
        }
        try database.makeRequest(with: sqlInsert(SlotRoundTripPerson(id: "a", name: "a", nickname: "A", alias: "Al"))).execute()
        try database.makeRequest(with: sqlInsert(SlotRoundTripPerson(id: "b", name: "b", nickname: nil, alias: nil))).execute()
    }

    private func allRows() throws -> [SlotRoundTripPerson] {
        let statement = sql { schema in
            let person = schema.table(SlotRoundTripPerson.self)
            Select(person)
            From(person)
            OrderBy(person.id.ascending())
        }
        return try database.makeRequest(with: statement).fetchAll()
    }

    private func encode(_ statement: any XLEncodable) throws -> String {
        try XLDialectEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(statement).sql
    }

    // MARK: - A column never assigned

    func testAnUnassignedNullableColumnAssignedToItselfKeepsTheStoredValue() throws {
        try createRows()
        let statement = sql { schema in
            let person = schema.into(SlotRoundTripPerson.self)
            Update(person)
            Setting<SlotRoundTripPerson> { row in
                row.nickname = row.nickname
            }
        }
        // The read names the column, its current value, rather than `NULL`.
        XCTAssertEqual(
            try encode(statement),
            #"UPDATE "SlotRoundTripPerson" AS "t0" SET "nickname" = "nickname""#
        )
        try database.makeRequest(with: statement).execute()
        XCTAssertEqual(try allRows(), [
            SlotRoundTripPerson(id: "a", name: "a", nickname: "A", alias: "Al"),
            SlotRoundTripPerson(id: "b", name: "b", nickname: nil, alias: nil),
        ])
    }

    func testAnUnassignedNullableColumnCopiesItsStoredValue() throws {
        try createRows()
        // To another nullable column, replacing an earlier assignment to it.
        try applyUpdate { _, row in
            row.alias = "x"
            row.alias = row.nickname
        }
        XCTAssertEqual(try allRows().map(\.alias), ["A", nil])
        // Through a read held in a variable, and through a second slot.
        try applyUpdate { _, row in
            let read: any XLSQLiteExpression<String?> = row.alias
            row.nickname = read
            row.nickname = row.nickname
        }
        XCTAssertEqual(try allRows().map(\.nickname), ["A", nil])
    }

    func testAnUnassignedColumnOfACustomTypeKeepsItsStoredValue() throws {
        try database.makeRequest(with: sqlCreate(SlotRoundTripEvent.self)).execute()
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        try database.makeRequest(with: sqlInsert(SlotRoundTripEvent(id: "a", at: date))).execute()
        try database.makeRequest(with: sqlInsert(SlotRoundTripEvent(id: "b", at: nil))).execute()
        let statement = sql { schema in
            let event = schema.into(SlotRoundTripEvent.self)
            Update(event)
            Setting<SlotRoundTripEvent> { row in
                row.at = row.at
            }
        }
        // The column is read through `julianday`, as a column reference is,
        // so `strftime` writes back the text it was.
        XCTAssertEqual(
            try encode(statement),
            #"UPDATE "SlotRoundTripEvent" AS "t0" SET "at" = strftime('%Y-%m-%dT%H:%M:%f', julianday("at"))"#
        )
        let before: [String?] = try databasePool.read { db in
            try String?.fetchAll(db, sql: "SELECT at FROM SlotRoundTripEvent ORDER BY id")
        }
        try database.makeRequest(with: statement).execute()
        let after: [String?] = try databasePool.read { db in
            try String?.fetchAll(db, sql: "SELECT at FROM SlotRoundTripEvent ORDER BY id")
        }
        XCTAssertEqual(after, before)
        XCTAssertNotNil(after.first ?? nil)
        XCTAssertNil(after.last ?? nil)
    }

    func testAnUnassignedReadOfAnotherModelIsNull() throws {
        // A read of another model's column never assigned does not name
        // this table's column of the same name; it is `NULL`, as before.
        let pet = SlotRoundTripPet.MetaUpdate()
        let statement = sql { schema in
            let person = schema.into(SlotRoundTripPerson.self)
            Update(person)
            Setting<SlotRoundTripPerson> { row in
                row.nickname = pet.nickname
                row.alias = SlotRoundTripPerson.MetaUpdate().nickname
            }
        }
        // A read of the same model, from another `MetaUpdate`, is the row's
        // column.
        XCTAssertEqual(
            try encode(statement),
            #"UPDATE "SlotRoundTripPerson" AS "t0" SET "nickname" = NULL,"alias" = "nickname""#
        )
    }

    func testAnUnassignedReadOutsideTheSetClauseIsNull() throws {
        try createRows()
        // Composed, the read renders `NULL`, as before, rather than a bare
        // column name that another table's column could capture.
        let composed = sql { schema in
            let person = schema.into(SlotRoundTripPerson.self)
            Update(person)
            Setting<SlotRoundTripPerson> { row in
                row.alias = row.nickname.coalesce("none")
            }
        }
        XCTAssertEqual(
            try encode(composed),
            #"UPDATE "SlotRoundTripPerson" AS "t0" SET "alias" = COALESCE(NULL, 'none')"#
        )
        // As a value to insert, it is `NULL`, not a name that SQLite would
        // read as a string.
        let unassigned = SlotRoundTripPerson.MetaUpdate()
        let insertion = sql { schema in
            Insert(schema.table(SlotRoundTripPerson.self))
            Values(SlotRoundTripPerson.MetaInsert(id: "c", name: "c", nickname: unassigned.nickname, alias: nil as String?))
        }
        try database.makeRequest(with: insertion).execute()
        XCTAssertEqual(try allRows().last, SlotRoundTripPerson(id: "c", name: "c", nickname: nil, alias: nil))
    }

    // MARK: - A column assigned

    func testAnAssignedNullableColumnAssignedToItselfKeepsTheAssignedValue() throws {
        try createRows()
        // A value of the wrapped type, through the wrapped-type overload.
        try applyUpdate { person, row in
            row.nickname = "Z"
            row.nickname = row.nickname
        }
        XCTAssertEqual(try allRows().map(\.nickname), ["Z", "Z"])
        // An optional-typed expression: another nullable column, `NULL` in
        // one row and not in the other.
        try applyUpdate { person, row in
            row.nickname = person.alias
            row.nickname = row.nickname
        }
        XCTAssertEqual(try allRows().map(\.nickname), ["Al", nil])
        // A composed expression of the wrapped type.
        try applyUpdate { person, row in
            row.nickname = person.name + "?"
            row.nickname = row.nickname
        }
        XCTAssertEqual(try allRows().map(\.nickname), ["a?", "b?"])
        // `NULL`.
        try applyUpdate { person, row in
            row.nickname = nil
            row.nickname = row.nickname
        }
        XCTAssertEqual(try allRows().map(\.nickname), [nil, nil])
    }

    func testAnAssignedNullableColumnCopiesToAnotherNullableColumn() throws {
        try createRows()
        try applyUpdate { person, row in
            row.nickname = person.alias
            row.alias = row.nickname
        }
        XCTAssertEqual(try allRows(), [
            SlotRoundTripPerson(id: "a", name: "a", nickname: "Al", alias: "Al"),
            SlotRoundTripPerson(id: "b", name: "b", nickname: nil, alias: nil),
        ])
        try applyUpdate { person, row in
            row.nickname = "N"
            row.alias = row.nickname
            row.alias = row.alias
        }
        XCTAssertEqual(try allRows().map(\.alias), ["N", "N"])
    }

    /// Updates every row with the values `assign` sets.
    private func applyUpdate(_ assign: (SlotRoundTripPerson.MetaWritableTable, inout SlotRoundTripPerson.MetaUpdate) -> Void) throws {
        let person = XLSchema().into(SlotRoundTripPerson.self)
        var values = SlotRoundTripPerson.MetaUpdate()
        assign(person, &values)
        try database.makeRequest(with: update(person, set: values)).execute()
    }

    // MARK: - The other slots

    func testTheFluentSetClauseKeepsAnUnassignedNullableColumn() throws {
        try createRows()
        let schema = XLSchema()
        let person = schema.into(SlotRoundTripPerson.self)
        let statement = update(person)
            .set { row in
                row.name = "n"
                row.nickname = row.nickname
            }
        try database.makeRequest(with: statement).execute()
        XCTAssertEqual(try allRows(), [
            SlotRoundTripPerson(id: "a", name: "n", nickname: "A", alias: "Al"),
            SlotRoundTripPerson(id: "b", name: "n", nickname: nil, alias: nil),
        ])
    }

    func testAnUpsertKeepsAnUnassignedNullableColumn() throws {
        try createRows()
        for id in ["a", "b"] {
            let schema = XLSchema()
            let person = schema.table(SlotRoundTripPerson.self)
            let excluded = schema.excluded(SlotRoundTripPerson.self)
            let statement = insert(person)
                .values(SlotRoundTripPerson.MetaInsert(SlotRoundTripPerson(id: id, name: "u", nickname: "X", alias: "X")))
                .onConflict("id", doUpdate: { row in
                    row.name = excluded.name
                    row.nickname = row.nickname
                    row.alias = excluded.alias
                    row.alias = row.alias
                })
            try database.makeRequest(with: statement).execute()
        }
        XCTAssertEqual(try allRows(), [
            SlotRoundTripPerson(id: "a", name: "u", nickname: "A", alias: "X"),
            SlotRoundTripPerson(id: "b", name: "u", nickname: nil, alias: "X"),
        ])
    }

    func testTheGeneratedInitializerTakesARead() throws {
        try createRows()
        let schema = XLSchema()
        let person = schema.into(SlotRoundTripPerson.self)
        let unassigned = SlotRoundTripPerson.MetaUpdate()
        var assigned = SlotRoundTripPerson.MetaUpdate()
        assigned.alias = person.nickname
        let statement = update(
            person,
            set: SlotRoundTripPerson.MetaUpdate(
                name: "m",
                nickname: unassigned.nickname,
                alias: assigned.alias
            )
        )
        XCTAssertEqual(
            try encode(statement),
            #"UPDATE "SlotRoundTripPerson" AS "t0" SET "name" = 'm',"nickname" = "nickname","alias" = "t0"."nickname""#
        )
        try database.makeRequest(with: statement).execute()
        XCTAssertEqual(try allRows(), [
            SlotRoundTripPerson(id: "a", name: "m", nickname: "A", alias: "A"),
            SlotRoundTripPerson(id: "b", name: "m", nickname: nil, alias: nil),
        ])
    }
}
