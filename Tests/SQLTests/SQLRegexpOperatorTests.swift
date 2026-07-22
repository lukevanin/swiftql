import Foundation
import GRDB
import SwiftQL
import XCTest


@SQLTable(name: "Phrase")
struct RegexpPhrase: Equatable {
    let id: String
    let text: String
}


///
/// Issue #78: the `REGEXP` operator. SQLite ships no implementation, so these
/// tests register one and also assert the unregistered failure.
///
final class XLRegexpOperatorTests: XCTestCase {

    private var database: GRDBDatabase!
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    override func tearDownWithError() throws {
        database = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    /// Registers `regexp/2` the way an application would, through a caller
    /// supplied configuration. `observedArgumentOrder` records what SQLite
    /// actually passes, which the operator's documentation claims is reversed.
    private func makeDatabase(
        observedArgumentOrder: (@Sendable (String, String) -> Void)? = nil,
        registerRegexp: Bool = true
    ) throws -> GRDBDatabase {
        var configuration = Configuration()
        if registerRegexp {
            configuration.prepareDatabase { db in
                db.add(function: DatabaseFunction("regexp", argumentCount: 2) { values in
                    guard
                        let pattern = String.fromDatabaseValue(values[0]),
                        let subject = String.fromDatabaseValue(values[1])
                    else {
                        return nil
                    }
                    observedArgumentOrder?(pattern, subject)
                    return subject.range(of: pattern, options: .regularExpression) != nil
                })
            }
        }
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: configuration,
            logger: nil
        )
        let database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexpPhrase.self)).execute()
        for phrase in [
            RegexpPhrase(id: "1", text: "alpha-123"),
            RegexpPhrase(id: "2", text: "beta"),
            RegexpPhrase(id: "3", text: "gamma-456"),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }
        return database
    }

    func testRegexpMatchesUsingTheRegisteredFunction() throws {
        database = try makeDatabase()
        let statement = sql { schema in
            let phrase = schema.table(RegexpPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("[0-9]+$"))
            OrderBy(phrase.id.ascending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: statement).fetchAll(),
            ["1", "3"]
        )
    }

    /// `X REGEXP Y` is a call to `regexp(Y, X)`. Getting this backwards would
    /// still compile and still return rows for a symmetric pattern, so the
    /// order is observed directly rather than inferred from a result.
    func testRegexpPassesPatternAsTheFirstFunctionArgument() throws {
        let observed = LockedPair()
        database = try makeDatabase(observedArgumentOrder: { pattern, subject in
            observed.record(pattern: pattern, subject: subject)
        })
        let statement = sql { schema in
            let phrase = schema.table(RegexpPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("^beta$"))
        }
        XCTAssertEqual(try database.makeRequest(with: statement).fetchAll(), ["2"])

        let seen = observed.value()
        XCTAssertEqual(seen?.pattern, "^beta$")
        XCTAssertTrue(
            ["alpha-123", "beta", "gamma-456"].contains(seen?.subject ?? ""),
            "subject should be a column value, got \(seen?.subject ?? "nil")"
        )
    }

    /// Without registration the statement fails at preparation. This is the
    /// behaviour the operator's documentation warns about.
    func testRegexpWithoutRegisteredFunctionFailsAtPreparation() throws {
        database = try makeDatabase(registerRegexp: false)
        let statement = sql { schema in
            let phrase = schema.table(RegexpPhrase.self)
            Select(phrase.id)
            From(phrase)
            Where(phrase.text.regexp("[0-9]+$"))
        }
        XCTAssertThrowsError(
            try database.makeRequest(with: statement).fetchAll()
        ) { error in
            XCTAssertTrue(
                "\(error)".lowercased().contains("no such function: regexp"),
                "unexpected error: \(error)"
            )
        }
    }
}


/// Minimal thread-safe box; the SQLite function runs on the database queue.
private final class LockedPair: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (pattern: String, subject: String)?

    func record(pattern: String, subject: String) {
        lock.lock()
        defer { lock.unlock() }
        if stored == nil {
            stored = (pattern, subject)
        }
    }

    func value() -> (pattern: String, subject: String)? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
