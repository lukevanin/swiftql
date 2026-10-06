//
//  DialectTypeParameterTests.swift
//  SwiftQL
//
//  Issue #789: the dialect is a type parameter of the query surface. A model
//  is declared for one dialect, and its columns are expressions of that
//  dialect only. Each dialect has its own expression protocol, and its own
//  copy of every operator and function that composes expressions, generated
//  from one set of templates by scripts/dialect-surface/generate.py. The same
//  query body is written for SQLite and for a second dialect, and renders
//  identically. `FakeSecondDialect` (declared with the #687 tests) stands in
//  for a PostgreSQL dialect, which SwiftQL does not ship; its surface is
//  generated into Tests/SQLTests/Generated/FakeSecondDialect.
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


/// An enum. `XLEnum` makes it a SQLite expression; it is an expression of the
/// second dialect because it declares that dialect's protocol as well.
enum DialectMood: String, XLEnum, FakeSecondDialectExpression {
    typealias T = Self

    case calm
    case cross

    static func sqlDefault() -> DialectMood {
        .calm
    }
}


/// The table with an enum column, declared for the second dialect.
@SQLTable(name: "mood", dialect: FakeSecondDialect.self)
struct DialectSecondMood: Equatable {
    let id: Int
    let mood: DialectMood
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

    /// Fails to compile, rather than at run time, if `expression` is not a
    /// SQLite expression.
    private func assertSQLite<T>(_ expression: some XLSQLiteExpression<T>) {
    }

    /// Fails to compile, rather than at run time, if `expression` is not an
    /// expression of the second dialect.
    private func assertSecond<T>(_ expression: some FakeSecondDialectExpression<T>) {
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

    func testEveryColumnAndComposedExpressionIsOfTheModelDialect() {
        let sqlite = XLSchema().table(DialectSQLitePerson.self)
        let second = XLSchema(dialect: FakeSecondDialect.self).table(DialectSecondPerson.self)

        assertSQLite(sqlite.name)
        assertSecond(second.name)
        // A dialect's operators and functions return that dialect's
        // expressions, so a composed expression is of its columns' dialect.
        assertSecond(second.name + second.name)
        assertSecond(second.id + 1)
        assertSecond(second.nickname.coalesce("none"))
        assertSecond(second.nickname.isNull())
        assertSecond((second.id > 1) && (second.id < 9))
        assertSecond(second.name.like("a%"))
        assertSecond(switchCase(second.id).when(1, then: "one").else("other"))
        assertSecond(when(second.id > 1, then: "many").else("one"))
    }

    // MARK: - Values belong to every dialect

    func testValuesAndBindingsAreExpressionsOfEveryDialect() {
        let binding = XLNamedBindingReference<Int>(name: "id")
        assertSQLite(1)
        assertSecond(1)
        assertSQLite("a")
        assertSecond("a")
        assertSQLite(binding)
        assertSecond(binding)
        // A value composes with a column of either dialect, and the result is
        // of the column's dialect.
        let sqlite = XLSchema().table(DialectSQLitePerson.self)
        let second = XLSchema(dialect: FakeSecondDialect.self).table(DialectSecondPerson.self)
        assertSQLite(sqlite.id == binding)
        assertSecond(second.id == binding)
        assertSecond(binding == second.id)
        assertSecond(second.id == binding + 1)
    }

    // A function of a value alone has nothing to pick a dialect, so where two
    // dialects' surfaces are visible, as in this module, it takes the one not
    // marked disfavoured: SQLite's. Next to a column, the column's dialect
    // decides.
    func testAFunctionOfAValueTakesItsDialectFromTheOtherOperand() throws {
        let binding = XLNamedBindingReference<String?>(name: "nickname")
        let second = sql(dialect: FakeSecondDialect.self) { schema in
            let person = schema.table(DialectSecondPerson.self)
            Select(person.id)
            From(person)
            Where(person.name == binding.coalesce("none"))
        }
        XCTAssertEqual(
            try secondSQL(second),
            #"SELECT "t0"."id" FROM "person" AS "t0" WHERE ("t0"."name" == COALESCE(:nickname, 'none'))"#
        )
        assertSQLite(binding.coalesce("none"))
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

    // An enum is an expression of a dialect whose protocol it declares, so it
    // is an operand next to that dialect's column.
    func testAnEnumThatDeclaresTheSecondDialectIsAnOperandInIt() throws {
        let statement = sql(dialect: FakeSecondDialect.self) { schema in
            let row = schema.table(DialectSecondMood.self)
            Select(row.id)
            From(row)
            Where(row.mood == DialectMood.cross)
        }
        XCTAssertEqual(
            try secondSQL(statement),
            #"SELECT "t0"."id" FROM "mood" AS "t0" WHERE ("t0"."mood" == 'cross')"#
        )
        assertSQLite(DialectMood.calm)
        assertSecond(DialectMood.calm)
    }

    // A value is a SQLite expression, so SQLite's own functions take it
    // directly.
    func testSQLiteOperationsApplyToValues() throws {
        let date = "2026-07-19 12:30:45".datetime(.months(1))
        assertSQLite(date)
        XCTAssertEqual(
            try sqliteSQL(date),
            "datetime('2026-07-19 12:30:45', '+1 months')"
        )
        XCTAssertEqual(try sqliteSQL("abc".collate(.nocase)), "('abc' COLLATE NOCASE)")
    }

    // MARK: - Static row layouts

    // A static field's factory takes its expression erased, so the dialect is
    // checked when the field is built: a column of a model declared for
    // another dialect throws.
    func testAStaticFieldRefusesAColumnOfAnotherDialect() throws {
        let second = XLSchema(dialect: FakeSecondDialect.self).table(DialectSecondPerson.self)
        let identity = try XLQuerySlotIdentity(path: ["dialect", "name"])
        XCTAssertThrowsError(
            try XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
                selecting: second.name,
                identifiedBy: identity
            )
        ) { error in
            guard case XLStaticRowLayoutError.expressionDialectMismatch(
                let thrownIdentity,
                let expectedDialect,
                let foundDialect,
                _
            ) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(thrownIdentity, identity)
            XCTAssertEqual(expectedDialect, String(reflecting: XLSQLiteDialect.self))
            XCTAssertEqual(foundDialect, String(reflecting: FakeSecondDialect.self))
        }
        // A composed expression is refused too, wherever the column is in it,
        // and so is a CASE expression, which keeps its arms in closures.
        let composed: [any XLExpression<String>] = [
            second.name + "x",
            "x" + ("y" + ("z" + second.name)),
            when(second.id > 1, then: second.name).else("none"),
            switchCase(second.id).when(1, then: second.name).else("none"),
        ]
        for expression in composed {
            XCTAssertThrowsError(
                try XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
                    selecting: expression,
                    identifiedBy: identity
                )
            ) { error in
                guard case XLStaticRowLayoutError.expressionDialectMismatch = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
        let sqlite = XLSchema().table(DialectSQLitePerson.self)
        let field = try XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: sqlite.name,
            identifiedBy: identity
        )
        // The field's expression is of its dialect, so it composes with that
        // dialect's expressions.
        assertSQLite(field.expression == "a")
        // A composed expression of the field's own dialect is accepted.
        _ = try XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: sqlite.name + "x",
            identifiedBy: identity
        )
    }

    // The field wraps its expression, and a JSON function still recognises a
    // wrapped `jsonb` result as JSON rather than refusing it as a blob.
    func testAStaticFieldKeepsAJSONBResultRecognisable() throws {
        let document = XLNamedBindingReference<String>(name: "document")
        let field = try XLStaticSelectField<Data?, Data?, XLSQLiteDialect>.intrinsic(
            selecting: document.minifiedJSONB(),
            identifiedBy: try XLQuerySlotIdentity(path: ["dialect", "document"])
        )
        let encoder = XLDialectEncoder(dialect: XLSQLiteDialect())
        XCTAssertNil(encoder.makeSQL(jsonArray(field.expression)).valueEncodingError)
    }
}
