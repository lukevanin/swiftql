import Foundation
import SwiftQL

// Issue #828: a nullable column's slot is read only as an optional-typed
// expression. Passing the read to the generated `MetaUpdate(...)` for a
// column that is NOT NULL is refused at the argument: the wrapped-type read's
// getter is unavailable.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: unavailable NULL optional-typed

func refusal() -> DialectPerson.MetaUpdate {
    let person = XLSchema().into(DialectPerson.self)
    let read = DialectPerson.MetaUpdate(nickname: person.nickname)
    return DialectPerson.MetaUpdate(
        name: read.nickname // expected-error
    )
}
