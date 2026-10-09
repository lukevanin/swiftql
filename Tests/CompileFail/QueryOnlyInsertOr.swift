import Foundation
import SwiftQLQuery

// Issue #790: `INSERT OR` is SQLite's own, declared in SwiftQLSQLite, so a
// file that imports SwiftQLQuery alone has only the plain `Insert`.
// Compiled with Support/QueryOnlySupport.swift and the query-only dialect's
// generated surface.
// expected-names: 'or'

func refusal() -> any XLInsertStatement {
    sql(dialect: QueryOnlyDialect.self) { schema in
        let person = schema.into(QueryOnlyPerson.self)
        Insert(person, or: .ignore) // expected-error
        Values(QueryOnlyPerson.MetaInsert(QueryOnlyPerson(id: 1, name: "a", level: .junior)))
    }
}
