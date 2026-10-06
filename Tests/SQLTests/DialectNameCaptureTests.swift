//
//  DialectNameCaptureTests.swift
//  SwiftQL
//
//  Issue #789: the models' dialect is the associated type `XLModelDialect`.
//  Swift makes an inferred associated type a member type of the model, so a
//  plainer name such as `Dialect` would capture a type of the user's own with
//  that name inside the model and its generated code. These models compile
//  only because it does not.
//

import Foundation
import SwiftQL
import XCTest


/// A type of the user's own, at the top level, named `Dialect`.
enum Dialect: String, XLEnum {
    typealias T = Self

    case uk
    case us

    static func sqlDefault() -> Dialect {
        .uk
    }
}


/// A model whose property's type is the top-level `Dialect`.
@SQLTable(name: "word")
struct DialectNamedWord: Equatable {
    let id: Int
    let dialect: Dialect
}


/// A model that declares a nested type named `Dialect` and uses it.
@SQLTable(name: "phrase")
struct DialectNestedPhrase: Equatable {
    enum Dialect: String, XLEnum {
        typealias T = Self

        case formal
        case casual

        static func sqlDefault() -> Dialect {
            .formal
        }
    }

    let id: Int
    let register: Dialect
}


final class DialectNameCaptureTests: XCTestCase {

    private func sql(_ statement: any XLEncodable) throws -> String {
        try XLDialectEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(statement).sql
    }

    func testAPropertyOfTheUsersOwnDialectTypeKeepsItsType() throws {
        XCTAssertTrue(DialectNamedWord.XLModelDialect.self == XLSQLiteDialect.self)
        let statement = SwiftQL.sql { schema in
            let word = schema.table(DialectNamedWord.self)
            Select(word)
            From(word)
            Where(word.dialect == Dialect.us)
        }
        XCTAssertEqual(
            try sql(statement),
            #"SELECT "t0"."id" AS "id", "t0"."dialect" AS "dialect" FROM "word" AS "t0" WHERE ("t0"."dialect" == 'us')"#
        )
    }

    func testANestedTypeNamedDialectIsTheModelsOwn() throws {
        XCTAssertTrue(DialectNestedPhrase.XLModelDialect.self == XLSQLiteDialect.self)
        let statement = SwiftQL.sql { schema in
            let phrase = schema.table(DialectNestedPhrase.self)
            Select(phrase)
            From(phrase)
            Where(phrase.register == DialectNestedPhrase.Dialect.casual)
        }
        XCTAssertEqual(
            try sql(statement),
            #"SELECT "t0"."id" AS "id", "t0"."register" AS "register" FROM "phrase" AS "t0" WHERE ("t0"."register" == 'casual')"#
        )
    }
}
