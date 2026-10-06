import Foundation
import SwiftQL

// Issue #789: an operator does not compose an expression built from one
// dialect's columns with an expression built from another's. Each side is
// already composed, so neither is a column the error could name.
// Compiled with Support/DialectParameterisedSupport.swift,
// Support/DialectTypeParameterSupport.swift, and the second dialect's
// generated surface in Support/Generated/CompileFailSecondDialect.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where((person.name == "a") && (other.name == "b")) // expected-error
    }
}
