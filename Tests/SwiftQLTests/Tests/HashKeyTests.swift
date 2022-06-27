//
//  EqualityTests.swift
//  
//
//  Created by Luke Van In on 2022/05/18.
//

import XCTest

@testable import SwiftQL

//final class HashKeyTests: XCTestCase {
    
    /*
    struct Sample1 {
        var id: String
        var value: Int
        var unit: String
    }
    
    struct Sample2 {
        var id: Int
        var value: Int
        var unit: String
    }

    final class Schema: DatabaseSchema {

        final class Sample1Schema: BaseTableSchema, TableSchema {
            lazy var id = PrimaryKeyField<String>(name: "id", table: self)
            lazy var value = Field<Int>(name: "value", table: self)
            lazy var unit = Field<String>(name: "unit", table: self)

            static let tableName = SQLIdentifier(stringLiteral: "samples1")

            var tableFields: [AnyField] {
                return [id, value, unit]
            }
            
            func entity(from row: SQLRow) -> Sample1 {
                Sample1(
                    id: row.field(id),
                    value: row.field(value),
                    unit: row.field(unit)
                )
            }
            
            func values(entity: Sample1) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: StringLiteral(entity.id),
                    value.name: IntegerLiteral(entity.value),
                    unit.name: StringLiteral(entity.unit)
                ]
            }
        }

        final class Sample2Schema: BaseTableSchema, TableSchema {
            lazy var id = PrimaryKeyField<Int>(name: "id", table: self)
            lazy var value = Field<Int>(name: "value", table: self)
            lazy var unit = Field<String>(name: "unit", table: self)

            static let tableName = SQLIdentifier(stringLiteral: "samples2")

            var tableFields: [AnyField] {
                return [id, value, unit]
            }
            
            func entity(from row: SQLRow) -> Sample2 {
                Sample2(
                    id: row.field(id),
                    value: row.field(value),
                    unit: row.field(unit)
                )
            }
            
            func values(entity: Sample2) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: IntegerLiteral(entity.id),
                    value.name: IntegerLiteral(entity.value),
                    unit.name: StringLiteral(entity.unit)
                ]
            }
        }
        
        func samples1() -> Sample1Schema {
            schema(table: Sample1Schema.self)
        }
        
        func samples2() -> Sample2Schema {
            schema(table: Sample2Schema.self)
        }
    }

    var connection: DatabaseConnection!
    var database: MyDatabase!

    override func setUpWithError() throws {
        let filename = UUID().uuidString
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = directory.appendingPathComponent(filename).appendingPathExtension("sqlite3")
        let resource = SQLite.Resource(fileURL: fileURL)
        connection = DatabaseConnection(provider: try resource.connect())
        database = MyDatabase(connection: connection)
        try database.query { db in Create(db.users()) }.execute()
        try database.query { db in Create(db.photos()) }.execute()
        try database.query { db in Create(db.samples()) }.execute()
        try database.query { db in Create(db.places()) }.execute()
    }
    
    override func tearDownWithError() throws {
        database = nil
        connection = nil
    }

    // Create
    
    func testCreate_shouldEqual_givenSameSchema() {
        let s0 = Create(Schema().samples1())
        let s1 = Create(Schema().samples1())
        XCTAssertEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)

    }
    
    func testCreate_shouldNotEqual_givenDifferentSchema() {
        let s0 = Create(Schema().samples1())
        let s1 = Create(Schema().samples2())
        XCTAssertNotEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)

    }
    
    // TODO: Insert

    // TODO: Update

    // Select
    
    func testSelect_shouldEqual_givenSameSchema() {
        let s0 = Select(Schema().samples1())
        let s1 = Select(Schema().samples2())
        XCTAssertEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }

    func testSelect_shouldEqual_givenSameFieldOfSameSchema() {
        let s0 = Select() { $0.field(Schema().samples1().id) }
        let s1 = Select() { $0.field(Schema().samples1().id) }
        XCTAssertEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }


    func testSelect_shouldNotEqual_givenDifferentFieldOfSameSchema() {
        let s0 = Select() { $0.field(Schema().samples1().id) }
        let s1 = Select() { $0.field(Schema().samples1().value) }
        XCTAssertNotEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }

    func testSelect_shouldEqual_givenSameFieldOfDifferentSchemas() {
        let s0 = Select() { $0.field(Schema().samples1().id) }
        let s1 = Select() { $0.field(Schema().samples2().id) }
        XCTAssertEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }

    func testSelect_shouldEqual_givenSameFields() {
        let t0 = Schema().samples1()
        let t1 = Schema().samples1()
        let s0 = Select() {
            (
                id: $0.field(t0.id),
                value: $0.field(t0.value)
            )
        }
        let s1 = Select() {
            (
                id: $0.field(t1.id),
                value: $0.field(t1.value)
            )
        }
        XCTAssertEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }

    func testSelect_shouldEqual_givenSameFieldsOfDifferentSchemas() {
        let t0 = Schema().samples1()
        let t1 = Schema().samples2()
        let s0 = Select() {
            (
                id: $0.field(t0.id),
                value: $0.field(t0.value)
            )
        }
        let s1 = Select() {
            (
                id: $0.field(t1.id),
                value: $0.field(t1.value)
            )
        }
        XCTAssertEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }

    func testSelect_shouldEqual_givenDifferentFieldsOfDifferentSchemas() {
        let t0 = Schema().samples1()
        let t1 = Schema().samples2()
        let s0 = Select() {
            (
                id: $0.field(t0.id),
                value: $0.field(t0.value)
            )
        }
        let s1 = Select() {
            (
                id: $0.field(t1.id),
                unit: $0.field(t1.unit)
            )
        }
        XCTAssertNotEqual(s0.hashKey.rawValue, s1.hashKey.rawValue)
    }
    
    // TODO: Join
    
    // TODO: Where
    
    // TODO: Order by
    */
    
//}
