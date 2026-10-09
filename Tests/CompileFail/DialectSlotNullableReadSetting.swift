import Foundation
import SwiftQL

// Issue #828: a nullable column's slot is read only as an optional-typed
// expression, because its value can be NULL. Assigning the read to a column
// that is NOT NULL in `Setting { row in ... }` is refused at the assignment:
// the wrapped-type read's getter is unavailable.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: unavailable NULL optional-typed

func refusal() -> any XLUpdateStatement {
    sql { schema in
        let person = schema.into(DialectPerson.self)
        Update(person)
        Setting<DialectPerson> { row in
            row.nickname = person.nickname
            row.name = row.nickname // expected-error
        }
    }
}
