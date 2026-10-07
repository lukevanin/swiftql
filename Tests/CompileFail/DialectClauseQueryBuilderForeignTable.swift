import Foundation
import SwiftQL

// Issue #822: `QueryBuilder` builds SQLite queries, and takes only SQLite
// tables and expressions. A second-dialect table is refused. The error names
// both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> QueryBuilder<DialectPerson> {
    let person = XLSchema().table(DialectPerson.self)
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return QueryBuilder(select: person)
        .from(other) // expected-error
}
