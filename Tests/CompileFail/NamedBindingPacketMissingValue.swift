import SwiftQL

@SQLTable struct BindingPacketPerson {
    var id: String
    var name: String
    var age: Int
}

@SQLBindings
struct PersonSearchBindings {
    var name: String
    var minimumAge: Int
}

func people(
    in database: GRDBDatabase,
    named name: String,
    minimumAge: Int
) throws -> [BindingPacketPerson] {
    let statement = sql { schema in
        let person = schema.table(BindingPacketPerson.self)
        Select(person)
        From(person)
        Where(person.name == PersonSearchBindings.name && person.age >= PersonSearchBindings.minimumAge)
    }
    let request = database.makeRequest(with: statement)
    let packet = try PersonSearchBindings(name: name) // expected-error
        .bindings(for: request)
    return try request.fetchAll(bindings: packet)
}
