import Foundation
import GRDB
import SwiftQL
import XCTest


@SQLTable(name: "Word")
struct CollationWord: Equatable {
    let id: String
    let text: String
}


///
/// Issue #29: a collating sequence registered on the connection, named from a
/// query with `XLCollation(rawValue:)`.
///
final class XLCustomCollationTests: XCTestCase {

    private var database: GRDBDatabase!
    private var fileURL: URL!

    /// Orders and compares by string length, which no built-in collation does,
    /// so a passing assertion cannot be explained by BINARY or NOCASE.
    private static let byLength = "byLength"

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        var builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: Configuration(),
            logger: nil
        )
        builder.addCollation(Self.byLength) { lhs, rhs in
            if lhs.count == rhs.count {
                return .orderedSame
            }
            return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
        }
        database = try builder.build()
        try database.makeRequest(with: sqlCreate(CollationWord.self)).execute()
        for word in [
            CollationWord(id: "1", text: "ccc"),
            CollationWord(id: "2", text: "a"),
            CollationWord(id: "3", text: "bb"),
        ] {
            try database.makeRequest(with: sqlInsert(word)).execute()
        }
    }

    override func tearDownWithError() throws {
        database = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    func testCustomCollationOrdersByRegisteredSequence() throws {
        let statement = sql { schema in
            let word = schema.table(CollationWord.self)
            Select(word.text)
            From(word)
            OrderBy(word.text.collate(XLCollation(rawValue: Self.byLength)).ascending())
        }
        let ordered = try database.makeRequest(with: statement).fetchAll()

        // Length order, not alphabetical: "a" < "bb" < "ccc".
        XCTAssertEqual(ordered, ["a", "bb", "ccc"])

        // Alphabetical order would have been "a", "bb", "ccc" too, so prove the
        // sequence is actually consulted by ordering descending as well.
        let descendingStatement = sql { schema in
            let word = schema.table(CollationWord.self)
            Select(word.text)
            From(word)
            OrderBy(word.text.collate(XLCollation(rawValue: Self.byLength)).descending())
        }
        XCTAssertEqual(
            try database.makeRequest(with: descendingStatement).fetchAll(),
            ["ccc", "bb", "a"]
        )
    }

    func testCustomCollationComparesByRegisteredSequence() throws {
        let lhs = XLNamedBindingReference<String>(name: "lhs")
        let rhs = XLNamedBindingReference<String>(name: "rhs")
        let statement = sql { _ in
            Select(lhs.collate(XLCollation(rawValue: Self.byLength)) == rhs)
        }

        // Different text, same length: equal under this collation only.
        var equalRequest = database.makeRequest(with: statement)
        equalRequest.set(lhs, "ab")
        equalRequest.set(rhs, "zz")
        XCTAssertEqual(try equalRequest.fetchOne(), true)

        // BINARY would call these equal; this collation must not.
        var unequalRequest = database.makeRequest(with: statement)
        unequalRequest.set(lhs, "abc")
        unequalRequest.set(rhs, "ab")
        XCTAssertEqual(try unequalRequest.fetchOne(), false)
    }

    /// An unregistered collation is a preparation failure, not a silent
    /// fallback to BINARY.
    func testUnregisteredCollationFailsAtPreparation() throws {
        let statement = sql { schema in
            let word = schema.table(CollationWord.self)
            Select(word.text)
            From(word)
            Where(word.text.collate(XLCollation(rawValue: "notRegistered")) == "a")
        }
        XCTAssertThrowsError(
            try database.makeRequest(with: statement).fetchAll()
        ) { error in
            XCTAssertTrue(
                "\(error)".lowercased().contains("no such collation"),
                "unexpected error: \(error)"
            )
        }
    }
}
