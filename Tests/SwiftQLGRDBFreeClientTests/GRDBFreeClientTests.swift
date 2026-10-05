//
//  GRDBFreeClientTests.swift
//  SwiftQL
//
//  Issue #702: a client opens a database, registers a function and a
//  collation, and runs queries with no GRDB import. This target depends on
//  SwiftQL alone, and the contract boundary check rejects a GRDB, CSQLite, or
//  Combine import in it, so it keeps proving that.
//

import Foundation
import SwiftQL
import XCTest


@SQLTable
struct GRDBFreePerson: Equatable {
    let name: String
    let age: Int
}


/// Doubles an integer. Registered on the builder, so every connection has it.
@SQLFunction(name: "grdbFreeDouble")
struct GRDBFreeDouble: XLCustomFunction {

    typealias T = Int

    private let value: any XLExpression<Int>

    init(_ value: any XLExpression<Int>) {
        self.value = value
    }

    static func execute(reader: XLColumnReader) throws -> Int {
        try reader.readInteger(at: 0) * 2
    }
}


final class GRDBFreeClientTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testClientOpensRegistersAndQueriesWithoutGRDB() throws {
        var configuration = GRDBDatabaseConfiguration()
        configuration.busyTimeout = 1
        configuration.maximumReaderCount = 2
        configuration.label = "GRDBFreeClientTests"
        var builder = try GRDBDatabaseBuilder(
            url: directory.appendingPathComponent("client.sqlite"),
            configuration: configuration,
            logger: nil
        )
        builder.addFunction(GRDBFreeDouble.self)
        // Reverse order, so the collation is visibly the one that sorted.
        builder.addCollation("reversed") { lhs, rhs in
            rhs.compare(lhs)
        }
        let database = try builder.build()

        try database.makeRequest(with: sqlCreate(GRDBFreePerson.self)).execute()
        try database.withTransaction { scope in
            try scope.makeRequest(with: sqlInsert(GRDBFreePerson(name: "Ada", age: 36))).execute()
            try scope.makeRequest(with: sqlInsert(GRDBFreePerson(name: "Grace", age: 85))).execute()
        }

        let doubledAges = try database.makeRequest(with: sql { schema in
            let person = schema.table(GRDBFreePerson.self)
            Select(GRDBFreeDouble(person.age))
            From(person)
            OrderBy(person.name.collate(XLCollation(rawValue: "reversed")).ascending())
        }).fetchAll()

        XCTAssertEqual(doubledAges, [170, 72])
    }

    func testDefaultConfigurationOpensAWritableDatabase() throws {
        let database = try GRDBDatabase(
            url: directory.appendingPathComponent("default.sqlite"),
            logger: nil
        )
        try database.makeRequest(with: sqlCreate(GRDBFreePerson.self)).execute()
        let result = try database.makeRequest(
            with: sqlInsert(GRDBFreePerson(name: "Ada", age: 36))
        ).execute()
        XCTAssertEqual(result.rowsAffected, 1)
    }

    func testReadOnlyConfigurationRejectsWritesWithAPortableError() throws {
        let url = directory.appendingPathComponent("readonly.sqlite")
        let writable = try GRDBDatabase(url: url, logger: nil)
        try writable.makeRequest(with: sqlCreate(GRDBFreePerson.self)).execute()

        let readOnly = try GRDBDatabase(
            url: url,
            configuration: GRDBDatabaseConfiguration(readonly: true),
            logger: nil
        )
        XCTAssertThrowsError(
            try readOnly.makeRequest(
                with: sqlInsert(GRDBFreePerson(name: "Ada", age: 36))
            ).execute()
        ) { error in
            XCTAssertEqual((error as? XLDatabaseError)?.code, .readOnly, "\(error)")
        }
    }
}
