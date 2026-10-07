import Foundation
import SwiftQL

// Issue #822: a compound select's branches are statements of one dialect. A
// second-dialect branch of a SQLite union is refused. The error names both
// dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<Int> {
    let person = XLSchema().table(DialectPerson.self)
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    let branch = select(other.age).from(other)
    return select(person.age).from(person).union { branch } // expected-error
}
