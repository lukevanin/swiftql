// swiftql-skill-example-begin
import SwiftQL

@SQLTable(name: "SkillPerson")
struct SkillPerson: Equatable {
    let id: String
    let name: String
}

enum SkillQueryError: Error {
    case missingNameParameter
}

func fetchSkillPeople(
    named name: String,
    from database: GRDBDatabase
) throws -> [SkillPerson] {
    let nameParameter = XLNamedBindingReference<String>(name: "name")
    let query = sql { schema in
        let person = schema.table(SkillPerson.self)
        Select(person)
        From(person)
        Where(person.name == nameParameter)
    }
    let request = database.makeRequest(with: query)
    guard let nameSlot = request.parameterLayout.slot(for: .named("name")) else {
        throw SkillQueryError.missingNameParameter
    }
    let bindings = try XLInvocationBindings<XLSQLiteValue>(
        layout: request.parameterLayout,
        bindings: [
            try XLInvocationBinding(slot: nameSlot, value: .text(name)),
        ]
    ).validatingComplete()
    return try request.fetchAll(bindings: bindings)
}
// swiftql-skill-example-end
