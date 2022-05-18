//
//  BaseTestCase.swift
//  
//
//  Created by Luke Van In on 2022/05/18.
//

import XCTest

@testable import SwiftQL

class BaseTestCase: XCTestCase {
    
    var connection: DatabaseConnection!
    var database: MyDatabase!

    func setupDatabase() throws {
        let filename = UUID().uuidString
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = directory.appendingPathComponent(filename).appendingPathExtension("sqlite3")
        let resource = SQLite.Resource(fileURL: fileURL)
        connection = DatabaseConnection(connection: try resource.connect())
        database = MyDatabase(connection: connection)
        try database.query { db in Create(db.users()) }.execute()
        try database.query { db in Create(db.photos()) }.execute()
        try database.query { db in Create(db.samples()) }.execute()
        try database.query { db in Create(db.places()) }.execute()
    }
    
    func teardownDatabase() {
        database = nil
        connection = nil
    }

}
