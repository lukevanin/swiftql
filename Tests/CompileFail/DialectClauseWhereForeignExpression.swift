import Foundation
import SwiftQL

// Issue #822: a `Where` clause takes only its statement's dialect. A condition
// composed from another dialect's columns, passed to a SQLite query's clause
// directly, is refused at the clause. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(other.nickname.isNull()) // expected-error
    }
}
