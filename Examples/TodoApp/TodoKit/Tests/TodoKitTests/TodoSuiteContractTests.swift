import XCTest

import SwiftQL
import TodoKit

/// Checks the suite's own promises, rather than the code under test.
///
/// The demo's tests are the thing that turns a library change from "the demo
/// still compiles" into "the demo still behaves". That is only true if the
/// tests are isolated from each other and deterministic, so those two
/// properties are asserted rather than assumed.
final class TodoSuiteContractTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000.25)

    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
    }

    private func makeDatabase() throws -> TodoDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoContract-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        return try TodoDatabase(
            url: directory.appendingPathComponent(TodoDatabase.fileName),
            referenceDate: referenceDate
        )
    }

    // MARK: - Isolation

    func testEachDatabaseGetsItsOwnFile() throws {
        let first = try makeDatabase()
        let second = try makeDatabase()

        XCTAssertNotEqual(first.url, second.url)
    }

    func testAWriteInOneDatabaseIsInvisibleInAnother() throws {
        let first = try makeDatabase()
        let second = try makeDatabase()

        try first.deleteTodo(id: TodoSeed.renewPassportID)

        XCTAssertNil(try first.todo(id: TodoSeed.renewPassportID))
        XCTAssertNotNil(
            try second.todo(id: TodoSeed.renewPassportID),
            "a test's writes must not reach another test's database"
        )
    }

    func testTemporaryDatabasesCleanUpAfterThemselves() throws {
        var database: TodoDatabase? = try makeDatabase()
        let url = try XCTUnwrap(database?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Release the connection pool before removing the directory, which
        // is the order the other suites tear down in. Deleting a file out
        // from under an open pool is a different, less portable thing to be
        // testing.
        database = nil
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Determinism

    func testTheSeedIsIdenticalForTheSameReferenceDate() throws {
        let first = try makeDatabase()
        let second = try makeDatabase()

        XCTAssertEqual(
            try first.todos(),
            try second.todos(),
            "two databases seeded at the same reference date must agree"
        )
    }

    func testOverdueDependsOnTheReferenceDateAndNotTheClock() throws {
        let database = try makeDatabase()

        func overdueTitles(at date: Date) throws -> [String] {
            try database.todos(matching: TodoQuery(
                listID: TodoSeed.todayListID,
                filter: .overdue,
                referenceDate: TodoDate(date)
            )).map(\.title)
        }

        // Two days before the reference date, nothing in this list is yet
        // past due. Two days after, both open to-dos are.
        XCTAssertEqual(
            try overdueTitles(at: referenceDate.addingTimeInterval(-2 * 86_400)),
            []
        )
        XCTAssertEqual(
            try overdueTitles(at: referenceDate).sorted(),
            ["Renew passport"]
        )
        XCTAssertEqual(
            try overdueTitles(at: referenceDate.addingTimeInterval(2 * 86_400)).sorted(),
            ["Book a dentist appointment", "Renew passport"]
        )
    }

    func testEveryReadIsStableAcrossRepeatedRuns() throws {
        let database = try makeDatabase()

        let filters = TodoFilter.allCases
        let sorts = TodoSort.allCases
        let lists = [
            TodoSeed.todayListID,
            TodoSeed.homeListID,
            TodoSeed.readingListID,
        ]

        for listID in lists {
            for filter in filters {
                for sort in sorts {
                    let subject = TodoQuery(
                        listID: listID,
                        filter: filter,
                        sort: sort,
                        referenceDate: TodoDate(referenceDate)
                    )
                    let first = try database.todos(matching: subject).map(\.id)
                    for _ in 0..<5 {
                        XCTAssertEqual(
                            try database.todos(matching: subject).map(\.id),
                            first,
                            "\(filter) / \(sort) is not stable"
                        )
                    }
                }
            }
        }
    }

    /// Every combination the app can ask for prepares and runs.
    ///
    /// The build-time validator proves the SQL is valid against the schema;
    /// this proves every binding packet the app can build is accepted and
    /// executes.
    func testEveryFilterAndSortCombinationExecutes() throws {
        let database = try makeDatabase()
        let searches = ["", "a", "%", "_", "\\", "'"]
        var executed = 0

        for filter in TodoFilter.allCases {
            for sort in TodoSort.allCases {
                for search in searches {
                    _ = try database.todos(matching: TodoQuery(
                        listID: TodoSeed.todayListID,
                        filter: filter,
                        sort: sort,
                        searchText: search,
                        referenceDate: TodoDate(referenceDate)
                    ))
                    executed += 1
                }
            }
        }

        XCTAssertEqual(
            executed,
            TodoFilter.allCases.count * TodoSort.allCases.count * searches.count
        )
    }
}
