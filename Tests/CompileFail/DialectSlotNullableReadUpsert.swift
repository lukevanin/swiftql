import Foundation
import SwiftQL

// Issue #828: a nullable column's slot is read only as an optional-typed
// expression. Assigning the read to a column that is NOT NULL in an upsert's
// `onConflict(_:doUpdate:)` is refused at the assignment: the wrapped-type
// read's getter is unavailable.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: unavailable NULL optional-typed

func refusal() -> any XLEncodable {
    let schema = XLSchema()
    let person = schema.table(DialectPerson.self)
    let excluded = schema.excluded(DialectPerson.self)
    return insert(person)
        .values(DialectPerson.MetaInsert(id: 1, name: "a", nickname: nil as String?, age: 2))
        .onConflict("id", doUpdate: { row in
            row.nickname = excluded.nickname
            row.name = row.nickname // expected-error
        })
}
