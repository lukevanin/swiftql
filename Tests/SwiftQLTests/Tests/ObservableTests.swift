//
//  ObservableTests.swift
//  
//
//  Created by Luke Van In on 2022/05/18.
//

import XCTest

@testable import SwiftQL

final class ObservableTests: BaseTestCase {

    override func setUpWithError() throws {
        try setupDatabase()
    }
    
    override func tearDownWithError() throws {
        teardownDatabase()
    }
    
    func testObservePrepopulated() async throws {
        
        let expectedValue = Sample(id: "a", value: 7)
        try database.execute(cached: true) { db in
            Insert(db.samples(), expectedValue)
        }
        
        try await Task.sleep(nanoseconds: 1_000_000)

        let subject = try database
            .query(cached: true) { db in
                let sample = db.samples()
                Select(sample)
                From(sample)
                OrderBy { sample.value.ascending }
            }
            .observe()
        var values = subject.values.makeAsyncIterator()
        
        try await Task.sleep(nanoseconds: 1_000_000)

        print("final result")
        let finalResult = try await values.next()?.get()
        XCTAssertEqual(finalResult, [expectedValue])
    }

    func testObserveInsert() async throws {
        let subject = try database
            .query(cached: true) { db in
                let sample = db.samples()
                Select(sample)
                From(sample)
                OrderBy { sample.value.ascending }
            }
            .observe()
        var values = subject.values.makeAsyncIterator()
        
        print("initial result")
        let initialResult = try await values.next()?.get()
        XCTAssertEqual(initialResult, [])
        
        print("insert")
        let expectedValue = Sample(id: "a", value: 7)
        try await database.transaction { database, transaction in
            try database.execute(cached: true) { db in
                Insert(db.samples(), expectedValue)
            }
        }

        try await Task.sleep(nanoseconds: 1_000_000)

        print("final result")
        let finalResult = try await values.next()?.get()
        XCTAssertEqual(finalResult, [expectedValue])
    }
}
