import Foundation
import SwiftQL

// Issue #692: the NULL-safe comparison does not compose a column of one dialect
// with a column of another, as `==` does not (issue #789). The error names both
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
        Where(person.nickname.isNotDistinctFrom(other.nickname)) // expected-error
    }
}
