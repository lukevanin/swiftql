import Foundation
import SwiftQL

// Issue #828: a nullable column's slot is read only as an optional-typed
// expression. Passing a force-unwrapped read to the generated
// `MetaInsert(...)` for a column that is NOT NULL is refused at the argument:
// the wrapped-type read's getter is unavailable.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: unavailable NULL optional-typed

func refusal() -> DialectPerson.MetaInsert {
    let person = XLSchema().into(DialectPerson.self)
    let read = DialectPerson.MetaUpdate(nickname: person.nickname)
    return DialectPerson.MetaInsert(
        id: 1,
        name: read.nickname!, // expected-error
        nickname: nil as String?,
        age: 2
    )
}
