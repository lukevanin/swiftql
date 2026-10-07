import Foundation
import SwiftQL

// Issue #789: the error for comparing two columns of different types keeps the
// wording and the column of the error before the dialect parameter. Only
// the printed column types gain their dialect argument.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-message: binary operator '==' cannot be applied to operands of type 'XLColumnReference<String, XLSQLiteDialect>' and 'XLColumnReference<Int, XLSQLiteDialect>'

func mistake() -> any XLQueryStatement<DialectPerson> {
    sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(person.name == person.age) // expected-error
    }
}
