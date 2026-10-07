import Foundation
import SwiftQL

// Issue #822: `RETURNING` projects a result of the statement's dialect. A
// second-dialect table's projection on a SQLite delete is refused. The error
// names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLReturningStatement<SecondDialectPerson> {
    let schema = XLSchema()
    let target = schema.into(DialectPerson.self)
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return delete(target).returning(other) // expected-error
}
