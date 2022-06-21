//
//  PerformanceTests.swift
//  
//
//  Created by Luke Van In on 2022/05/17.
//

import XCTest

@testable import SwiftQL

final class PerformanceTests: BaseTestCase {
    
    /*
    func testInsertUncached() {
        let samples = (0 ..< 500).map { i in
            Sample(id: PrimaryKey(), value: i)
        }
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(options: options) {
            try! withDatabase { database in
                startMeasuring()
                for sample in samples {
                    try! database.execute(cached: false) { db in
                        Insert(db.samples(), values: sample)
                    }
                }
                stopMeasuring()
            }
        }
    }
    
    func testInsertCached() {
        let samples = (0 ..< 500).map { i in
            Sample(id: PrimaryKey(), value: i)
        }
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(options: options) {
            try! withDatabase { database in
                startMeasuring()
                for sample in samples {
                    try! database.execute(cached: true) { db in
                        Insert(db.samples(), values: sample)
                    }
                }
                stopMeasuring()
            }
        }
    }
    
    func testInsertUncachedTransaction() {
        let samples = (0 ..< 10_000).map { i in
            Sample(id: PrimaryKey(), value: i)
        }
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(options: options) {
            try! withDatabase { database in
                startMeasuring()
                sync {
                    try! await database.transaction { database, transaction in
                        for sample in samples {
                            try! database.execute(cached: false) { db in
                                Insert(db.samples(), values: sample)
                            }
                        }
                    }
                }
                stopMeasuring()
            }
        }
    }

    func testInsertCachedTransaction() {
        let samples = (0 ..< 10_000).map { i in
            Sample(id: PrimaryKey(), value: i)
        }
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(options: options) {
            try! withDatabase { database in
                startMeasuring()
                sync {
                    try! await database.transaction { database, transaction in
                        for sample in samples {
                            try! database.execute(cached: true) { db in
                                Insert(db.samples(), values: sample)
                            }
                        }
                    }
                }
                stopMeasuring()
            }
        }
    }
        
    func sync(timeout: TimeInterval = 0.5, block: @escaping () async throws -> Void) -> Void {
        let e = expectation(description: "sync")
        Task {
            do {
                try await block()
            }
            catch {
                XCTFail(error.localizedDescription)
            }
            e.fulfill()
        }
        wait(for: [e], timeout: timeout)
    }
     */
}
