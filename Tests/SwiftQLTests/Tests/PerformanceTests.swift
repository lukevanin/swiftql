//
//  PerformanceTests.swift
//  
//
//  Created by Luke Van In on 2022/05/17.
//

import XCTest

@testable import SwiftQL

final class PerformanceTests: BaseTestCase {
    
    
    func testInsertUncached() {
        let samples = (0 ..< 5_000).map { i in
            Sample(id: "\(i)", value: i)
        }
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(options: options) {
            try! setupDatabase()
            startMeasuring()
            for sample in samples {
                try! database.execute(cached: false) { db in
                    Insert(db.samples(), sample)
                }
            }
            stopMeasuring()
            teardownDatabase()
        }
    }
    
    func testInsertCached() {
        let samples = (0 ..< 5_000).map { i in
            Sample(id: "\(i)", value: i)
        }
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(options: options) {
            try! setupDatabase()
            startMeasuring()
            for sample in samples {
                try! database.execute(cached: true) { db in
                    Insert(db.samples(), sample)
                }
            }
            stopMeasuring()
            teardownDatabase()
        }
    }
}
