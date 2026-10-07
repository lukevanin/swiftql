import Foundation
import SwiftQL

// Issue #822: a condition built from Swift values alone takes the dialect of
// the query's builder, so a SQLite-only operation on values is refused in a
// second-dialect query's `Where`. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<SecondDialectPerson> {
    sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.table(SecondDialectPerson.self)
        Select(person)
        From(person)
        Where("abc".regexp("a.c")) // expected-error
    }
}
