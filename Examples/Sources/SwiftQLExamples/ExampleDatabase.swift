import Foundation
import SwiftQL

/// Helpers that give a playground page a database to work against without
/// repeating the same setup on every page.
public enum ExampleDatabase {

    /// Creates an empty SQLite database in the system temporary directory and
    /// creates the example schema in it.
    ///
    /// Each call uses a fresh file, so a page that runs twice starts from the
    /// same state both times. Nothing here is playground-specific — it is the
    /// `GRDBDatabase` plus `sqlCreate` sequence from the Getting Started
    /// guide, collected into one call.
    public static func makeEmpty() throws -> GRDBDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftql-examples-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let database = try GRDBDatabase(url: url, logger: nil)
        try database.makeRequest(with: sqlCreate(Person.self)).execute()
        try database.makeRequest(with: sqlCreate(Occupation.self)).execute()
        return database
    }

    /// Creates an empty database and inserts a small, fixed cast of people and
    /// occupations.
    ///
    /// The rows are the same on every run, so a page can print results and
    /// compare them against the output the surrounding prose promises.
    public static func makeSeeded() throws -> GRDBDatabase {
        let database = try makeEmpty()
        for occupation in seedOccupations {
            try database.makeRequest(with: sqlInsert(occupation)).execute()
        }
        for person in seedPeople {
            try database.makeRequest(with: sqlInsert(person)).execute()
        }
        return database
    }

    /// The occupations inserted by ``makeSeeded()``.
    public static let seedOccupations: [Occupation] = [
        Occupation(id: "eng", title: "Engineer"),
        Occupation(id: "chef", title: "Chef"),
    ]

    /// The people inserted by ``makeSeeded()``, in insertion order.
    public static let seedPeople: [Person] = [
        Person(id: "fred", occupationId: "eng", name: "Fred", age: 31),
        Person(id: "grace", occupationId: "eng", name: "Grace", age: 29),
        Person(id: "harold", occupationId: "chef", name: "Harold", age: 45),
        Person(id: "ida", occupationId: nil, name: "Ida", age: 68),
    ]
}

public extension Person {

    /// A short, stable description used when a playground page prints rows.
    ///
    /// `print(person)` would emit the compiler-synthesized description, which
    /// is accurate but noisy in a playground's results sidebar.
    var exampleSummary: String {
        "\(name) (\(age))"
    }
}
