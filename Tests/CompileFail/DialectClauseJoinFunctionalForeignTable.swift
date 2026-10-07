import Foundation
import SwiftQL

// Issue #822: the functional form checks the dialect too. A select statement
// carries its dialect, and `innerJoin(_:on:)` takes only a table of it.
// The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let schema = XLSchema()
    let person = schema.table(DialectPerson.self)
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return select(person)
        .from(person)
        .innerJoin(other, on: person.id == 1) // expected-error
}
