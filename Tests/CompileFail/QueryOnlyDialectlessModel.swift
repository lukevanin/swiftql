import Foundation
import SwiftQLQuery

// Issue #790: the model macros without a `dialect:` argument default to SQLite,
// so they are declared in SwiftQLSQLite. A file that imports SwiftQLQuery
// alone sees only the overload that names the dialect.
// Compiled with Support/QueryOnlySupport.swift and the query-only dialect's
// generated surface.
// expected-names: 'dialect'

@SQLTable // expected-error
struct QueryOnlyDialectlessPerson {
    var id: Int
}
