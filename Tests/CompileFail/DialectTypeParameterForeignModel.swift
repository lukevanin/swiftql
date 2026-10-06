import Foundation
import SwiftQL

// Issue #789: a schema takes only models declared for its dialect. The error
// names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.

func refusal() -> any XLQueryStatement<SecondDialectPerson> {
    sql { schema in
        let person = schema.table(SecondDialectPerson.self) // expected-error
        Select(person)
        From(person)
    }
}
