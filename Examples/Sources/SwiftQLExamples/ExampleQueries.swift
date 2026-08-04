import SwiftQL

// Declared queries for the Getting Started playground.
//
// `@SQLQuery` is an attached macro, so — like `@SQLTable` — it is expanded
// here during the package build. The playground calls the generated
// `fetch…` executors and never expands a macro itself.
//
// Each function below is a *specification*: `@SQLQuery` reads its signature
// and emits a peer executor named `fetch` plus the capitalized specification
// name, so `peopleNamed(name:)` here produces `fetchPeopleNamed(name:)`. The
// executor is the one to call. See <doc:DeclaredQueries> for the full
// encoding.
//
// The peer form is used here rather than the `@SQLQueries` container form
// because `@SQLQueries` propagates its extension's access level onto every
// generated member, which means a `public extension` — the only way to expose
// the executors outside this module — expands to `public func` members inside
// an already-public extension and warns that the modifier is redundant. This
// package builds first-party targets with a warnings-as-errors gate, so that
// expansion cannot ship. `@SQLQuery` takes its modifiers from the
// specification function instead, which carries the access level without the
// redundancy.

extension GRDBDatabase {

    /// Specification for ``fetchPeopleNamed(name:)`` — every person with the
    /// given name.
    ///
    /// - Important: This is the query specification, not the query. Calling it
    ///   directly traps. Call `fetchPeopleNamed(name:)` instead.
    @SQLQuery
    public func peopleNamed(name: String) -> [Person] {
        sqlResult { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.name == name)
        }
    }

    /// Specification for ``fetchPersonByID(id:)`` — the person with the given
    /// identifier, or `nil` when no row matches.
    ///
    /// - Important: This is the query specification, not the query. Calling it
    ///   directly traps. Call `fetchPersonByID(id:)` instead.
    @SQLQuery
    public func personByID(id: String) -> Person? {
        sqlResult { schema in
            let person = schema.table(Person.self)
            Select(person)
            From(person)
            Where(person.id == id)
        }
    }
}
