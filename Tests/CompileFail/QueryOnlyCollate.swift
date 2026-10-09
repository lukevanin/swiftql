import Foundation
import SwiftQLQuery

// Issue #790: `COLLATE` is SQLite's own, declared in SwiftQLSQLite, so a file
// that imports SwiftQLQuery alone cannot reach it.
// Compiled with Support/QueryOnlySupport.swift and the query-only dialect's
// generated surface.
// expected-names: 'collate'

func refusal(name: String) -> any XLQueryStatement<QueryOnlyPerson> {
    sql(dialect: QueryOnlyDialect.self) { schema in
        let person = schema.table(QueryOnlyPerson.self)
        Select(person)
        From(person)
        Where(person.name.collate(.nocase) == name) // expected-error
    }
}
