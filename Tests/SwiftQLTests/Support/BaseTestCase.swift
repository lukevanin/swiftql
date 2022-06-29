//
//  BaseTestCase.swift
//  
//
//  Created by Luke Van In on 2022/05/18.
//

import XCTest

@testable import SwiftQL

class BaseTestCase: XCTestCase {
    
    var database: DatabaseConnection<MyDatabase>!
    
    override func setUp() {
        SQLite.initialize()
    }
    
    override class func tearDown() {
    }

    func setupDatabase() throws {
        database = try makeDatabase()
    }
    
    func teardownDatabase() {
        database = nil
    }
    
    func withDatabase(block: (DatabaseConnection<MyDatabase>) throws -> Void) throws {
        try block(makeDatabase())
    }

    func makeDatabase() throws -> DatabaseConnection<MyDatabase> {
        let filename = UUID().uuidString
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = directory.appendingPathComponent(filename).appendingPathExtension("sqlite3")
        let resource = SQLite.Resource(fileURL: fileURL)
        let database = DatabaseConnection<MyDatabase>(
            provider: try resource.connect()
        )
        #warning("TODO: Create tables")
//        let transaction = Transaction {
//            Create(db.users)
//            Create(db.photos)
//            Create(db.samples)
//            Create(db.places)
//        }
//        database.execute(transaction)
        return database
    }
}
