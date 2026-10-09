import Foundation
import SwiftQL

// Issue #828: a nullable column's slot is read only as an optional-typed
// expression. Force-unwrapping a read, to assign it to a column that is NOT
// NULL in the fluent `set(_:)`, is refused: the wrapped-type read's getter is
// unavailable.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: unavailable NULL optional-typed

func refusal() -> any XLUpdateStatement {
    let person = XLSchema().into(DialectPerson.self)
    return update(person).set { row in
        row.nickname = "a"
        row.name = row.nickname! // expected-error
    }
}
