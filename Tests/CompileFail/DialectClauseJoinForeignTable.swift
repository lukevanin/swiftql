import Foundation
import SwiftQL

// Issue #822: a join takes only a table of its statement's dialect, and its
// `ON` condition only that dialect's expressions. Joining a table taken from
// another dialect's schema is refused at the join. The error names both
// dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Join.Cross(other) // expected-error
    }
}
