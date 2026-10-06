import Foundation
import SwiftQL

// Issue #789: the error for comparing a column with a value of the wrong type keeps
// the wording and the column of the error before the dialect parameter.
// Only the printed column type gains its dialect argument.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-message: cannot convert value of type 'XLColumnReference<String, XLSQLiteDialect>' to expected argument type 'Bool'

func mistake(flag: Bool) -> any XLQueryStatement<DialectPerson> {
    sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(person.name == flag) // expected-error
    }
}
