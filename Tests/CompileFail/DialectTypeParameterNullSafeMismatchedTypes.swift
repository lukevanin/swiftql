import Foundation
import SwiftQL

// Issue #692: the NULL-safe comparison takes operands of one type, with either
// side optional, as `==` does. An integer is not comparable with text.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: isNotDistinctFrom

func refusal() -> any XLQueryStatement<DialectPerson> {
    sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(person.age.isNotDistinctFrom(person.name)) // expected-error
    }
}
