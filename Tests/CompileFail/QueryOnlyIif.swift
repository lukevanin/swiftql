import Foundation
import SwiftQLQuery

// Issue #790: `iif` is SQLite's own, declared in SwiftQLSQLite, so a file that
// imports SwiftQLQuery alone cannot reach it.
// Compiled with Support/QueryOnlySupport.swift and the query-only dialect's
// generated surface.
// expected-names: iif

func refusal() -> any XLQueryStatement<QueryOnlyPerson> {
    sql(dialect: QueryOnlyDialect.self) { schema in
        let person = schema.table(QueryOnlyPerson.self)
        Select(person)
        From(person)
        Where(iif(person.id > 1, then: true, else: false)) // expected-error
    }
}
