import Foundation
import SwiftQLQuery

// Issue #790: a file that imports SwiftQLQuery alone builds a query in a
// dialect of its own. The dialect's generated surface, and a model's
// expansion, compile against the dialect-neutral module with no SQLite.
// Compiled with Support/QueryOnlySupport.swift and the query-only dialect's
// generated surface.

func queryOnlyStatement(name: String) -> any XLQueryStatement<QueryOnlyPerson> {
    sql(dialect: QueryOnlyDialect.self) { schema in
        let person = schema.table(QueryOnlyPerson.self)
        Select(person)
        From(person)
        Where(person.name == name && person.id > 1 && person.level == QueryOnlyLevel.senior)
        OrderBy(person.name.ascending())
    }
}

func queryOnlyUpdate() -> any XLUpdateStatement {
    sql(dialect: QueryOnlyDialect.self) { schema in
        let person = schema.into(QueryOnlyPerson.self)
        Update(person)
        Setting<QueryOnlyPerson> { row in
            row.name = "renamed"
        }
        Where(person.id == 1)
    }
}
