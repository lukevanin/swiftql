import Foundation
import SwiftQL

// Issue #822: `From` takes only a table of its statement's dialect. A table
// taken from another dialect's schema is refused at the clause. The error
// names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(other) // expected-error
    }
}
