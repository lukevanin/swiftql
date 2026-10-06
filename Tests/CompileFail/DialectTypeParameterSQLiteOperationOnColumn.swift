import Foundation
import SwiftQL

// Issue #789: a SQLite-only operation is absent from a second-dialect query. The
// error is at the call site and names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.

func refusal(name: String) -> any XLQueryStatement<SecondDialectPerson> {
    sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.table(SecondDialectPerson.self)
        Select(person)
        From(person)
        Where(person.name.collate(.nocase) == name) // expected-error
    }
}
