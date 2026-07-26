//
//  SQLRowExecutionTests.swift
//
//
//  Real-SQLite coverage for the `#row` ad hoc row projection macro (#408,
//  follow-up to #20). Gated to Swift 6.0+ — see SQLRowMacro.swift and
//  COMPATIBILITY.md for why `#row`'s 2+-column shapes are unavailable on the
//  pinned Swift 5.9.2 compatibility cell.
//

#if compiler(>=6.0)
import Foundation
import XCTest
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import SwiftQL


final class SQLRowExecutionTests: XCTestCase {

    var databasePool: DatabasePool!
    var database: GRDBDatabase!
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        let formatter = XLiteFormatter(identifierFormattingOptions: .mysqlCompatible)
        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
    }

    override func tearDown() {
        cancellables.removeAll()
        database = nil
        databasePool = nil
    }

    private func makeTwoColumnStatement() -> any XLQueryStatement<SQLRow2<String, Int>> {
        sql { schema in
            let table = schema.table(TestTable.self)
            Select(#row(table.id, table.value))
            From(table)
            OrderBy(table.id.ascending())
        }
    }

    /// `#row`'s 2+-column shape (`SQLRow2`) decoding through `fetchAll()` is
    /// exactly the case that crashed swift-frontend on Swift 5.9.2 (#408):
    /// a 2-generic-parameter result type crossing GRDB's pooled read
    /// connection boundary.
    func testRowMacroDecodesTwoColumnsThroughFetchAll() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "bar", value: 42))).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "foo", value: 7))).execute()

        let rows = try database.makeRequest(with: makeTwoColumnStatement()).fetchAll()
        XCTAssertEqual(rows.map { $0._0 }, ["bar", "foo"])
        XCTAssertEqual(rows.map { $0._1 }, [42, 7])
    }

    func testRowMacroDecodesTwoColumnsThroughFetchOne() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "bar", value: 42))).execute()

        let row = try database.makeRequest(with: makeTwoColumnStatement()).fetchOne()
        XCTAssertEqual(row?._0, "bar")
        XCTAssertEqual(row?._1, 42)
    }

    func testRowMacroDecodesTwoColumnsThroughPublish() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "bar", value: 42))).execute()

        let expectation = expectation(description: "published rows")
        database.makeRequest(with: makeTwoColumnStatement()).publish()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected publisher failure: \(error)")
                    }
                },
                receiveValue: { rows in
                    guard rows.map({ $0._0 }) == ["bar"] else { return }
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 2)
    }

    func testRowMacroDecodesOneColumnThroughScalarResult() throws {
        try database.makeRequest(with: sqlCreate(TestTable.self)).execute()
        try database.makeRequest(with: sqlInsert(TestTable(id: "bar", value: 42))).execute()

        let statement = sql { schema in
            let table = schema.table(TestTable.self)
            Select(#row(table.value))
            From(table)
        }
        let row = try database.makeRequest(with: statement).fetchOne()
        XCTAssertEqual(row?.scalarValue, 42)
    }
}
#endif
