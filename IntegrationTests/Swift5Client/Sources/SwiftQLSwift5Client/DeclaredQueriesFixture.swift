import SwiftQL

// Downstream compatibility check for issues #18/#26: `@SQLQuery` (the direct
// peer form) and `@SQLQueries` (the container form) must expand and execute
// under the Swift 5 language-mode floor this fixture package pins to — the
// same floor `SwiftQLSwift5Client` validates for every other macro in this
// file.
//
// Only one `@SQLQueries` extension is supported per database type, and
// `SkillQuickStart.swift` owns it, because SKILL.md embeds that container
// verbatim. This file covers the peer form.

extension GRDBDatabase {

    @SQLQuery
    func skillPersonByName(name: String) -> SkillPerson? {
        sqlResult { schema in
            let person = schema.table(SkillPerson.self)
            Select(person)
            From(person)
            Where(person.name == name)
        }
    }
}


func validateDeclaredQueryMacros(database: GRDBDatabase) throws {
    let expected = SkillPerson(id: "ada", name: "Ada Lovelace")

    let direct = try database.fetchSkillPersonByName(name: "Ada Lovelace")
    guard direct == expected else {
        throw FixtureError.unexpectedDeclaredQueryResult(direct)
    }

    let container = try database.skillPeopleByName(name: "Ada Lovelace")
    guard container == [expected] else {
        throw FixtureError.unexpectedDeclaredQueriesResult(container)
    }
}
