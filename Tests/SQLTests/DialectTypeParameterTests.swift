//
//  DialectTypeParameterTests.swift
//  SwiftQL
//
//  Issue #789: the dialect is a type parameter of the query surface. A model
//  is declared for one dialect, its columns carry that dialect, and every
//  expression composed from them does too. The same query body is written
//  for SQLite and for a second dialect, and the universal parts render
//  identically. `FakeSecondDialect` (declared with the #687 tests) stands in
//  for a PostgreSQL dialect, which SwiftQL does not ship.
//
//  The refusals -- a SQLite-only operation on a second-dialect column or
//  composed expression, an operator across two dialects, a foreign model in a
//  schema -- are compile errors, so they are proven by
//  `scripts/ci/check-dialect-type-parameter-type-safety.sh`, which also pins
//  the text of the errors for three ordinary mistakes.
//

import Foundation
@_spi(GRDB) import SwiftQL
import XCTest


/// The SQLite declaration of the table.
@SQLTable(name: "person")
struct DialectSQLitePerson: Equatable {
    let id: Int
    let name: String
    let nickname: String?
}


/// The same table, declared for the second dialect.
@SQLTable(name: "person", dialect: FakeSecondDialect.self)
struct DialectSecondPerson: Equatable {
    let id: Int
    let name: String
    let nickname: String?
}


/// A result model declared for the second dialect.
@SQLResult(dialect: FakeSecondDialect.self)
struct DialectSecondName: Equatable {
    let name: String
}


final class DialectTypeParameterTests: XCTestCase {

    private func sqliteSQL(_ statement: any XLEncodable) throws -> String {
        try XLDialectEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(statement).sql
    }

    private func secondSQL(_ statement: any XLEncodable) throws -> String {
        try XLDialectEncoder(dialect: FakeSecondDialect()).makeValidatedSQL(statement).sql
    }

    /// Fails to compile, rather than at run time, if `expression` does not
    /// carry `Dialect`.
    private func assertDialect<T, Dialect>(
        _ expression: some XLExpression<T, Dialect>,
        _ dialect: Dialect.Type
    ) {
    }

    // MARK: - The model names the dialect

    func testAModelDeclaresItsDialect() {
        XCTAssertTrue(DialectSQLitePerson.Dialect.self == XLSQLiteDialect.self)
        XCTAssertTrue(DialectSecondPerson.Dialect.self == FakeSecondDialect.self)
        XCTAssertTrue(DialectSecondName.Dialect.self == FakeSecondDialect.self)
        XCTAssertTrue(DialectSecondPerson.MetaNamedResult.Dialect.self == FakeSecondDialect.self)
        XCTAssertTrue(DialectSecondPerson.MetaNullableNamedResult.Dialect.self == FakeSecondDialect.self)
        XCTAssertTrue(DialectSecondPerson.MetaWritableTable.Dialect.self == FakeSecondDialect.self)
    }

    func testEveryColumnAndComposedExpressionCarriesTheModelDialect() {
        let sqlite = XLSchema().table(DialectSQLitePerson.self)
        let second = XLSchema(dialect: FakeSecondDialect.self).table(DialectSecondPerson.self)

        assertDialect(sqlite.name, XLSQLiteDialect.self)
        assertDialect(second.name, FakeSecondDialect.self)
        // An operator and a function pass the dialect on, so a composed
        // expression carries it as its columns do.
        assertDialect(second.name + second.name, FakeSecondDialect.self)
        assertDialect(second.id + 1, FakeSecondDialect.self)
        assertDialect(second.nickname.coalesce("none"), FakeSecondDialect.self)
        assertDialect(second.nickname.isNull(), FakeSecondDialect.self)
        assertDialect((second.id > 1).iif(then: "a", else: "b"), FakeSecondDialect.self)
        assertDialect(second.name.like("a%"), FakeSecondDialect.self)
    }

    // MARK: - Values are universal

    func testValuesAndBindingsAreUniversal() {
        let binding = XLNamedBindingReference<Int>(name: "id")
        assertDialect(1, XLUniversalDialect.self)
        assertDialect("a", XLUniversalDialect.self)
        assertDialect(binding, XLUniversalDialect.self)
        assertDialect(binding + 1, XLUniversalDialect.self)
        // A universal operand takes the other operand's dialect.
        let second = XLSchema(dialect: FakeSecondDialect.self).table(DialectSecondPerson.self)
        assertDialect(second.id == binding, FakeSecondDialect.self)
        assertDialect(binding == second.id, FakeSecondDialect.self)
        assertDialect(second.id == binding + 1, FakeSecondDialect.self)
    }

    // MARK: - One query body, two dialects

    func testTheSameQueryBodyRendersForBothDialects() throws {
        let sqlite = sql { schema in
            let person = schema.table(DialectSQLitePerson.self)
            Select(person)
            From(person)
            Where(person.name == "a" && person.id > 1 && person.nickname.isNull())
            OrderBy(person.id.ascending())
            Limit(10)
        }
        let second = sql(dialect: FakeSecondDialect.self) { schema in
            let person = schema.table(DialectSecondPerson.self)
            Select(person)
            From(person)
            Where(person.name == "a" && person.id > 1 && person.nickname.isNull())
            OrderBy(person.id.ascending())
            Limit(10)
        }

        let expected = #"SELECT "t0"."id" AS "id", "t0"."name" AS "name", "t0"."nickname" AS "nickname" FROM "person" AS "t0" WHERE ((("t0"."name" == 'a') AND ("t0"."id" > 1)) AND ("t0"."nickname" ISNULL)) ORDER BY "t0"."id" ASC LIMIT 10"#
        XCTAssertEqual(try sqliteSQL(sqlite), expected)
        XCTAssertEqual(try secondSQL(second), expected)
    }

    func testASecondDialectResultModelProjectsSecondDialectColumns() throws {
        let statement = sql(dialect: FakeSecondDialect.self) { schema in
            let person = schema.table(DialectSecondPerson.self)
            Select(DialectSecondName.columns(name: person.name))
            From(person)
        }
        XCTAssertEqual(
            try secondSQL(statement),
            #"SELECT "t0"."name" AS "name" FROM "person" AS "t0""#
        )
    }

    func testASecondDialectSubqueryTakesTheSchemaDialect() throws {
        let statement = sql(dialect: FakeSecondDialect.self) { schema in
            let person = schema.table(DialectSecondPerson.self)
            let maximum = schema.subqueryExpression { schema in
                let inner = schema.table(DialectSecondPerson.self)
                Select(inner.id.maxOrNull())
                From(inner)
            }
            Select(person)
            From(person)
            Where(person.id == maximum)
        }
        XCTAssertEqual(
            try secondSQL(statement),
            #"SELECT "t0"."id" AS "id", "t0"."name" AS "name", "t0"."nickname" AS "nickname" FROM "person" AS "t0" WHERE ("t0"."id" IS (SELECT MAX("t1"."id") FROM "person" AS "t1"))"#
        )
    }

    // MARK: - SQLite's own surface

    func testSQLiteOperationsApplyToSQLiteColumnsAndComposedExpressions() throws {
        let statement = sql { schema in
            let person = schema.table(DialectSQLitePerson.self)
            Select(person)
            From(person)
            Where((person.name + "x").collate(.nocase) == "ax")
        }
        XCTAssertTrue(try sqliteSQL(statement).contains(#"WHERE ((("t0"."name" || 'x') COLLATE NOCASE) == 'ax')"#))
    }

    func testAValueIsLiftedIntoSQLiteForSQLiteOperations() throws {
        let lifted = "2026-07-19 12:30:45".sqlite.datetime(.months(1))
        assertDialect(lifted, XLSQLiteDialect.self)
        XCTAssertEqual(
            try sqliteSQL(lifted),
            "datetime('2026-07-19 12:30:45', '+1 months')"
        )
        let explicit = "abc".expression(in: XLSQLiteDialect.self).collate(.nocase)
        XCTAssertEqual(try sqliteSQL(explicit), "('abc' COLLATE NOCASE)")
    }

    // A value lifted into a dialect renders exactly as the value does.
    func testLiftingAValueIntoADialectRendersTheValue() throws {
        let binding = XLNamedBindingReference<Int?>(name: "id")
        XCTAssertEqual(
            try secondSQL(binding.expression(in: FakeSecondDialect.self).isNull()),
            try secondSQL(binding.isNull())
        )
    }
}
