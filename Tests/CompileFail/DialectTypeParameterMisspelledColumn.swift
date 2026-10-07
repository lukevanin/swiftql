import Foundation
import SwiftQL

// Issue #789: the error for a misspelled column is byte-identical to the error
// before the dialect parameter. The metadata type stays non-generic, so
// nothing in the message changes.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-message: value of type 'DialectPerson.MetaNamedResult' has no member 'nmae'

func mistake(name: String) -> any XLQueryStatement<DialectPerson> {
    sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(person.nmae == name) // expected-error
    }
}
