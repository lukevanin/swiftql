//
//  XLExecutionTests.swift
//
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


struct InsertTest {
    
    private static let idParameter = XLNamedBindingReference<String>(name: "id")

    private static let valueParameter = XLNamedBindingReference<Int>(name: "value")

    private static let statement: any XLInsertStatement<TestTable> = sqlInsert {
        let table = $0.table(TestTable.self)
        return insert(table).values(
            TestTable.MetaInsert(
                id: idParameter,
                value: valueParameter
            )
        )
    }
    
    private let request: XLWriteRequest
    
    init(database: XLDatabase) {
        request = database.makeRequest(with: Self.statement)
    }
    
    func execute(_ entity: TestTable) throws {
        var request = request
        request.set(Self.idParameter, entity.id)
        request.set(Self.valueParameter, entity.value)
        try request.execute()
    }
}


struct UpdateTest {
    
    private static let idParameter = XLNamedBindingReference<String>(name: "id")

    private static let valueParameter = XLNamedBindingReference<Int>(name: "value")

    private static let statement: any XLUpdateStatement<TestTable> = sqlUpdate {
        let table = $0.into(TestTable.self)
        return update(table, set: TestTable.MetaUpdate(
            value: valueParameter
        ))
        .where(table.id == idParameter)
    }
    
    private let request: XLWriteRequest
    
    init(database: XLDatabase) {
        request = database.makeRequest(with: Self.statement)
    }
    
    func execute(id: String, value: Int) throws {
        var request = request
        request.set(Self.idParameter, id)
        request.set(Self.valueParameter, value)
        try request.execute()
    }
}


final class XLPublisherTests: XCTestCase {
    
    var encoder: XLiteEncoder!
    var databasePool: DatabasePool!
    var database: GRDBDatabase!
    
    var insertTest: InsertTest!
    var updateTest: UpdateTest!
    
    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = directory.appending(path: filename, directoryHint: .notDirectory).appendingPathExtension("sqlite")
        print("Connecting to database \(fileURL.path)")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(databasePool: databasePool, formatter: formatter, logger: nil)
        insertTest = InsertTest(database: database)
        updateTest = UpdateTest(database: database)
    }
    
    override func tearDown() {
        insertTest = nil
        encoder = nil
        databasePool = nil
        database = nil
    }
    
    func testPublishExistingEntities() async throws {
        
        try createTestTable()
        try insertTest.execute(TestTable(id: "foo", value: 9000))
        try insertTest.execute(TestTable(id: "bar", value: 42))
        try insertTest.execute(TestTable(id: "baz", value: 100))
        
        let statement = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let resultsPublisher = database.makeRequest(with: statement).publish()
        var resultsIterator = resultsPublisher.values.makeAsyncIterator()
        let results = try await resultsIterator.next()
        
        XCTAssertEqual(results?.count, 3)
        XCTAssertEqual(results?[0], TestTable(id: "foo", value: 9000))
        XCTAssertEqual(results?[1], TestTable(id: "bar", value: 42))
        XCTAssertEqual(results?[2], TestTable(id: "baz", value: 100))
    }
    
    func testPublishNewEntity() async throws {
        
        try createTestTable()
        
        let statement = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let resultsPublisher = database.makeRequest(with: statement).publish()
        var resultsIterator = resultsPublisher.values.makeAsyncIterator()
        
        let initialResults = try await resultsIterator.next()
        XCTAssertEqual(initialResults?.count, 0)

        try insertTest.execute(TestTable(id: "foo", value: 9000))

        let finalResults = try await resultsIterator.next()
        XCTAssertEqual(finalResults?.count, 1)
        XCTAssertEqual(finalResults?.first, TestTable(id: "foo", value: 9000))
    }
    
    func testPublishUpdatedEntity() async throws {
        
        try createTestTable()
        try insertTest.execute(TestTable(id: "foo", value: 9000))
        
        let statement = sqlQuery { s in
            let t = s.table(TestTable.self)
            return select(t).from(t)
        }
        let resultsPublisher = database.makeRequest(with: statement).publish()
        var resultsIterator = resultsPublisher.values.makeAsyncIterator()
        
        let initialResults = try await resultsIterator.next()
        XCTAssertEqual(initialResults?.count, 1)
        XCTAssertEqual(initialResults?.first, TestTable(id: "foo", value: 9000))

        try updateTest.execute(id: "foo", value: 7)

        let finalResults = try await resultsIterator.next()
        XCTAssertEqual(finalResults?.count, 1)
        XCTAssertEqual(finalResults?.first, TestTable(id: "foo", value: 7))
    }
    
    // MARK: - Helpers
    
    private func createTestTable() throws {
        try databasePool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE Test (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    );
                """
            )
        }
    }
    
    
    private func createEmployeeTable() throws {
        try databasePool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE Employee (
                        id TEXT NOT NULL PRIMARY KEY,
                        name TEXT NOT NULL,
                        companyId TEXT NULL,
                        managerEmployeeId TEXT NULL
                    );
                """
            )
        }
    }

    
    private func insertEmployee(_ employee: EmployeeTable) throws {
        print("Insert: \(employee)")
        try databasePool.write { database in
            try database.execute(
                literal: """
                    INSERT INTO Employee
                        (id, name, companyId, managerEmployeeId)
                    VALUES
                        (\(employee.id), \(employee.name), \(employee.companyId), \(employee.managerEmployeeId));
                """
            )
        }
    }
}
