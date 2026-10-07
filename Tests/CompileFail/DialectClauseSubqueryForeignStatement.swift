import Foundation
import SwiftQL

// Issue #822: a scalar subquery takes a statement of its query's dialect. The
// schema-less `subquery { }` is SQLite's, so a second-dialect statement in it
// is refused. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let other = sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.table(SecondDialectPerson.self)
        Select(person.age)
        From(person)
    }
    return sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(person.age == subquery { other }) // expected-error
    }
}
