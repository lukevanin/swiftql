//
//  GRDBDatabaseConfigurationTests.swift
//  SwiftQL
//
//  `GRDBDatabaseConfiguration` is SwiftQL's own value for the options a GRDB
//  pool opens with (issue #702). These tests pin how each option reaches
//  GRDB, and that a database opened with one honours it.
//

import Foundation
import GRDB
import XCTest
@_spi(GRDB) @testable import SwiftQL


final class GRDBDatabaseConfigurationTests: XCTestCase {

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

    func testDefaultsAreGRDBDefaults() {
        let swiftQL = GRDBDatabaseConfiguration().grdbConfiguration
        let grdb = GRDB.Configuration()
        XCTAssertEqual(swiftQL.readonly, grdb.readonly)
        XCTAssertEqual(swiftQL.foreignKeysEnabled, grdb.foreignKeysEnabled)
        XCTAssertEqual(swiftQL.maximumReaderCount, grdb.maximumReaderCount)
        XCTAssertEqual(swiftQL.label, grdb.label)
        guard case .immediateError = swiftQL.busyMode else {
            return XCTFail("The default busy mode must fail at once, as GRDB's does.")
        }
    }

    func testEveryOptionReachesTheGRDBConfiguration() {
        let configuration = GRDBDatabaseConfiguration(
            readonly: true,
            foreignKeysEnabled: false,
            busyTimeout: 2.5,
            maximumReaderCount: 3,
            label: "configured"
        ).grdbConfiguration
        XCTAssertTrue(configuration.readonly)
        XCTAssertFalse(configuration.foreignKeysEnabled)
        XCTAssertEqual(configuration.maximumReaderCount, 3)
        XCTAssertEqual(configuration.label, "configured")
        guard case .timeout(let timeout) = configuration.busyMode else {
            return XCTFail("A busy timeout must become GRDB's timeout busy mode.")
        }
        XCTAssertEqual(timeout, 2.5)
    }

    func testOpenedPoolUsesTheConfiguration() throws {
        let database = try GRDBDatabase(
            url: directory.appendingPathComponent("configured.sqlite"),
            configuration: GRDBDatabaseConfiguration(
                foreignKeysEnabled: false,
                maximumReaderCount: 2,
                label: "configured"
            ),
            logger: nil
        )
        defer { try? database.databasePool.close() }
        XCTAssertEqual(database.databasePool.configuration.maximumReaderCount, 2)
        XCTAssertEqual(database.databasePool.configuration.label, "configured")
        let foreignKeys = try database.databasePool.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        XCTAssertEqual(foreignKeys, 0)
    }

    func testBuilderUsesTheConfiguration() throws {
        var builder = try GRDBDatabaseBuilder(
            url: directory.appendingPathComponent("built.sqlite"),
            codingConfiguration: XLValueCodingConfiguration(),
            configuration: GRDBDatabaseConfiguration(maximumReaderCount: 1),
            logger: nil
        )
        builder.addCollation("reversed") { lhs, rhs in rhs.compare(lhs) }
        let database = try builder.build()
        defer { try? database.databasePool.close() }
        XCTAssertEqual(database.databasePool.configuration.maximumReaderCount, 1)
        let foreignKeys = try database.databasePool.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        XCTAssertEqual(foreignKeys, 1)
    }

    /// GRDB stops the process for a pool with no readers, so SwiftQL checks
    /// first and throws.
    func testNoReadersThrowsAMisuseErrorInsteadOfTrapping() throws {
        for maximumReaderCount in [0, -1] {
            XCTAssertThrowsError(
                try GRDBDatabase(
                    url: directory.appendingPathComponent("no-readers.sqlite"),
                    configuration: GRDBDatabaseConfiguration(
                        maximumReaderCount: maximumReaderCount
                    ),
                    logger: nil
                )
            ) { error in
                let databaseError = error as? XLDatabaseError
                XCTAssertEqual(databaseError?.code, .misuse, "\(error)")
                XCTAssertEqual(
                    databaseError?.message,
                    "maximumReaderCount must be at least 1; it is \(maximumReaderCount)"
                )
            }
        }
        var grdbConfiguration = GRDB.Configuration()
        grdbConfiguration.maximumReaderCount = 0
        XCTAssertThrowsError(
            try GRDBDatabaseBuilder(
                url: directory.appendingPathComponent("no-readers.sqlite"),
                grdbConfiguration: grdbConfiguration,
                logger: nil
            ).build()
        ) { error in
            XCTAssertEqual((error as? XLDatabaseError)?.code, .misuse, "\(error)")
        }
    }

    /// GRDB converts a busy timeout to whole milliseconds and stops the
    /// process for one that does not fit, so SwiftQL checks first and throws.
    func testUnrepresentableBusyTimeoutThrowsAMisuseErrorInsteadOfTrapping() throws {
        for busyTimeout in [TimeInterval.infinity, .nan, 3_000_000] {
            XCTAssertThrowsError(
                try GRDBDatabase(
                    url: directory.appendingPathComponent("busy.sqlite"),
                    configuration: GRDBDatabaseConfiguration(busyTimeout: busyTimeout),
                    logger: nil
                )
            ) { error in
                XCTAssertEqual((error as? XLDatabaseError)?.code, .misuse, "\(busyTimeout): \(error)")
            }
        }
        let database = try GRDBDatabase(
            url: directory.appendingPathComponent("busy.sqlite"),
            configuration: GRDBDatabaseConfiguration(busyTimeout: 2_000_000),
            logger: nil
        )
        try database.databasePool.close()
    }

    /// The escape hatch keeps a GRDB configuration's own hooks, and the
    /// builder's registrations still reach every connection.
    func testGRDBConfigurationEscapeHatchKeepsItsHooks() throws {
        var grdbConfiguration = GRDB.Configuration()
        grdbConfiguration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA cache_size = -1234")
        }
        var builder = try GRDBDatabaseBuilder(
            url: directory.appendingPathComponent("escape-hatch.sqlite"),
            grdbConfiguration: grdbConfiguration,
            logger: nil
        )
        builder.addCollation("reversed") { lhs, rhs in rhs.compare(lhs) }
        let database = try builder.build()
        defer { try? database.databasePool.close() }
        let (cacheSize, ordered) = try database.databasePool.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA cache_size"),
                try String.fetchAll(
                    db,
                    sql: "SELECT value FROM (SELECT 'a' AS value UNION ALL SELECT 'b') ORDER BY value COLLATE reversed"
                )
            )
        }
        XCTAssertEqual(cacheSize, -1234)
        XCTAssertEqual(ordered, ["b", "a"])
    }
}
