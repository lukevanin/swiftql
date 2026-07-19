import Foundation
import GRDB
import XCTest

@testable import SwiftQL


final class SchemaMigrationArchitecturePrototypeTests: XCTestCase {

    func testExplicitRebuildPreservesDataAndVerifiesTargetSchema() throws {
        let fixture = try PrototypeMigrationFixture()
        let fingerprints = try fixture.referenceFingerprints()
        try fixture.installVersionOne(expectedFingerprint: fingerprints.v1)

        let plan = fixture.versionTwoPlan(fingerprints: fingerprints)
        XCTAssertEqual(
            try fixture.executor.apply(plan),
            .applied(sequence: 2, migrationID: plan.migrationID)
        )

        try fixture.databaseQueue.read { database in
            XCTAssertNotNil(
                try String.fetchOne(database, sql: "SELECT sqlite_version()")
            )
            XCTAssertEqual(
                try PrototypeSchemaFingerprint.capture(
                    database,
                    catalog: plan.toCatalog
                ),
                fingerprints.v2
            )
            XCTAssertEqual(
                try PrototypeMemberV2.fetchAll(database),
                [
                    PrototypeMemberV2(
                        id: 1,
                        teamID: 1,
                        displayName: "Alice Adams",
                        nickname: "Al",
                        status: "active"
                    ),
                    PrototypeMemberV2(
                        id: 2,
                        teamID: 1,
                        displayName: "Bob Brown",
                        nickname: nil,
                        status: "inactive"
                    ),
                ]
            )
            XCTAssertEqual(
                try PrototypeAuditRow.fetchAll(database),
                [
                    PrototypeAuditRow(
                        memberID: 1,
                        oldName: "Alice",
                        newName: "Alice Adams"
                    )
                ]
            )
            XCTAssertEqual(
                try String.fetchAll(
                    database,
                    sql: "PRAGMA integrity_check"
                ),
                ["ok"]
            )
            XCTAssertTrue(
                try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty
            )
            XCTAssertEqual(
                try Int.fetchOne(database, sql: "PRAGMA foreign_keys"),
                1
            )

            let columns = try String.fetchAll(
                database,
                sql: "SELECT name FROM pragma_table_xinfo('members') ORDER BY cid"
            )
            XCTAssertEqual(
                columns,
                ["id", "team_id", "display_name", "nickname", "status"]
            )
            XCTAssertFalse(columns.contains("full_name"))
            XCTAssertFalse(columns.contains("legacy_code"))

            let schemaObjects = try PrototypeSchemaObject.fetchAll(
                database,
                sql: """
                    SELECT type, name, tbl_name, COALESCE(sql, '') AS sql
                    FROM sqlite_schema
                    WHERE tbl_name = 'members'
                    ORDER BY type, name
                    """
            )
            XCTAssertTrue(
                schemaObjects.contains {
                    $0.type == "index"
                        && $0.name == "members_team_display_name_idx"
                }
            )
            XCTAssertTrue(
                schemaObjects.contains {
                    $0.type == "trigger"
                        && $0.name == "members_display_name_audit"
                }
            )
        }

        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE members SET display_name = ? WHERE id = ?",
                arguments: ["Alice A.", 1]
            )
            XCTAssertEqual(
                try PrototypeAuditRow.fetchAll(database),
                [
                    PrototypeAuditRow(
                        memberID: 1,
                        oldName: "Alice",
                        newName: "Alice Adams"
                    ),
                    PrototypeAuditRow(
                        memberID: 1,
                        oldName: "Alice Adams",
                        newName: "Alice A."
                    ),
                ]
            )

            XCTAssertThrowsError(
                try database.execute(
                    sql: """
                        INSERT INTO members (
                            id, team_id, display_name, nickname, status
                        ) VALUES (3, 999, 'Invalid team', NULL, 'active')
                        """
                )
            ) { error in
                XCTAssertEqual(
                    (error as? DatabaseError)?.extendedResultCode,
                    .SQLITE_CONSTRAINT_FOREIGNKEY
                )
            }
            XCTAssertThrowsError(
                try database.execute(
                    sql: """
                        INSERT INTO members (
                            id, team_id, display_name, nickname, status
                        ) VALUES (3, 1, 'Invalid status', NULL, 'unknown')
                        """
                )
            ) { error in
                XCTAssertEqual(
                    (error as? DatabaseError)?.resultCode,
                    .SQLITE_CONSTRAINT
                )
            }
            XCTAssertThrowsError(
                try database.execute(
                    sql: """
                        INSERT INTO members (
                            id, team_id, display_name, nickname, status
                        ) VALUES (3, 1, '', NULL, 'active')
                        """
                )
            ) { error in
                XCTAssertEqual(
                    (error as? DatabaseError)?.resultCode,
                    .SQLITE_CONSTRAINT
                )
            }
        }

        XCTAssertEqual(
            try fixture.executor.apply(plan),
            .alreadyApplied(sequence: 2, migrationID: plan.migrationID)
        )
        XCTAssertEqual(try fixture.history(), [1, 2])
    }

    func testUnexpectedLiveSchemaIsRejectedBeforeMutation() throws {
        let fixture = try PrototypeMigrationFixture()
        let fingerprints = try fixture.referenceFingerprints()
        try fixture.installVersionOne(expectedFingerprint: fingerprints.v1)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "CREATE INDEX members_unexpected_idx ON members(nickname)"
            )
        }

        let plan = fixture.versionTwoPlan(fingerprints: fingerprints)
        XCTAssertThrowsError(try fixture.executor.apply(plan)) { error in
            guard case .schemaDivergence(
                stage: .before,
                expected: fingerprints.v1,
                actual: let actual
            )? = error as? PrototypeMigrationError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertNotEqual(actual, fingerprints.v1)
        }

        XCTAssertEqual(try fixture.history(), [1])
        try fixture.databaseQueue.read { database in
            XCTAssertTrue(try database.tableExists("members"))
            XCTAssertFalse(try database.tableExists("__swiftql_new_members"))
            XCTAssertEqual(
                try Int.fetchOne(database, sql: "PRAGMA foreign_keys"),
                1
            )
            XCTAssertTrue(
                try String.fetchAll(
                    database,
                    sql: """
                        SELECT name FROM sqlite_schema
                        WHERE type = 'index' AND tbl_name = 'members'
                        """
                ).contains("members_unexpected_idx")
            )
        }
    }

    func testCopyConstraintFailureRollsBackAndRestoresForeignKeys() throws {
        let fixture = try PrototypeMigrationFixture()
        let fingerprints = try fixture.referenceFingerprints()
        try fixture.installVersionOne(expectedFingerprint: fingerprints.v1)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE members SET full_name = '' WHERE id = 2"
            )
        }

        let plan = fixture.versionTwoPlan(fingerprints: fingerprints)
        XCTAssertThrowsError(try fixture.executor.apply(plan)) { error in
            XCTAssertEqual(
                (error as? DatabaseError)?.resultCode,
                .SQLITE_CONSTRAINT
            )
        }

        try assertVersionOneWasRestored(
            fixture,
            expectedFingerprint: fingerprints.v1
        )
    }

    func testFailureAfterRebuildValidationRollsBackBeforeJournalCommit() throws {
        let fixture = try PrototypeMigrationFixture()
        let fingerprints = try fixture.referenceFingerprints()
        try fixture.installVersionOne(expectedFingerprint: fingerprints.v1)

        var plan = fixture.versionTwoPlan(fingerprints: fingerprints)
        plan.injectFailureAfterValidation = true
        XCTAssertThrowsError(try fixture.executor.apply(plan)) { error in
            XCTAssertEqual(
                error as? PrototypeMigrationError,
                .simulatedInterruption
            )
        }

        try assertVersionOneWasRestored(
            fixture,
            expectedFingerprint: fingerprints.v1
        )
    }

    func testHistoryAndAmbiguousChangesFailExplicitly() throws {
        let fixture = try PrototypeMigrationFixture()
        let fingerprints = try fixture.referenceFingerprints()
        try fixture.installVersionOne(expectedFingerprint: fingerprints.v1)

        var driftedPlan = fixture.versionTwoPlan(fingerprints: fingerprints)
        driftedPlan.definitionFingerprint = "changed-after-release"
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO _swiftql_schema_migrations (
                        catalog_id,
                        sequence,
                        migration_id,
                        definition_fingerprint,
                        from_schema_fingerprint,
                        to_schema_fingerprint
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    driftedPlan.catalogID,
                    driftedPlan.sequence,
                    driftedPlan.migrationID,
                    "released-definition",
                    driftedPlan.fromFingerprint.rawValue,
                    driftedPlan.toFingerprint.rawValue,
                ]
            )
        }

        XCTAssertThrowsError(try fixture.executor.apply(driftedPlan)) { error in
            XCTAssertEqual(
                error as? PrototypeMigrationError,
                .historyDrift(sequence: 2, migrationID: driftedPlan.migrationID)
            )
        }

        XCTAssertThrowsError(
            try PrototypeProposalPolicy.requireUserIntent(
                .possibleRename(from: "full_name", to: "display_name")
            )
        ) { error in
            XCTAssertEqual(
                error as? PrototypeMigrationError,
                .userIntentRequired(
                    "Possible rename full_name -> display_name cannot be inferred."
                )
            )
        }
        XCTAssertThrowsError(
            try PrototypeProposalPolicy.requireUserIntent(
                .codecChange(
                    column: "status",
                    from: "status-text@1",
                    to: "status-int@1"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PrototypeMigrationError,
                .userIntentRequired(
                    "Codec change status-text@1 -> status-int@1 for status needs an explicit data transform."
                )
            )
        }
        XCTAssertThrowsError(
            try PrototypeProposalPolicy.requireUserIntent(
                .unsupportedDialect("postgresql")
            )
        ) { error in
            XCTAssertEqual(
                error as? PrototypeMigrationError,
                .unsupportedDialect("postgresql")
            )
        }
    }

    private func assertVersionOneWasRestored(
        _ fixture: PrototypeMigrationFixture,
        expectedFingerprint: PrototypeSchemaFingerprint
    ) throws {
        XCTAssertEqual(try fixture.history(), [1])
        try fixture.databaseQueue.read { database in
            XCTAssertEqual(
                try PrototypeSchemaFingerprint.capture(
                    database,
                    catalog: .versionOne
                ),
                expectedFingerprint
            )
            XCTAssertTrue(try database.tableExists("members"))
            XCTAssertFalse(try database.tableExists("__swiftql_new_members"))
            XCTAssertEqual(
                try String.fetchOne(
                    database,
                    sql: "SELECT full_name FROM members WHERE id = 1"
                ),
                "Alice Adams"
            )
            XCTAssertEqual(
                try Int.fetchOne(database, sql: "PRAGMA foreign_keys"),
                1
            )
            XCTAssertTrue(
                try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty
            )
        }
    }
}


private struct PrototypeMigrationFixture {
    let databaseQueue: DatabaseQueue
    let executor: PrototypeSQLiteMigrationExecutor

    init() throws {
        let databaseQueue = try DatabaseQueue()
        self.databaseQueue = databaseQueue
        self.executor = PrototypeSQLiteMigrationExecutor(
            databaseQueue: databaseQueue
        )
    }

    func referenceFingerprints() throws -> (
        v1: PrototypeSchemaFingerprint,
        v2: PrototypeSchemaFingerprint
    ) {
        let versionOne = try DatabaseQueue()
        try versionOne.write { database in
            try createSharedSchema(database)
            try createVersionOneMembersSchema(database)
        }
        let versionTwo = try DatabaseQueue()
        try versionTwo.write { database in
            try createSharedSchema(database)
            try createVersionTwoMembersSchema(database, tableName: "members")
            try createVersionTwoDependents(database)
        }
        return (
            try versionOne.read {
                try PrototypeSchemaFingerprint.capture(
                    $0,
                    catalog: .versionOne
                )
            },
            try versionTwo.read {
                try PrototypeSchemaFingerprint.capture(
                    $0,
                    catalog: .versionTwo
                )
            }
        )
    }

    func installVersionOne(
        expectedFingerprint: PrototypeSchemaFingerprint
    ) throws {
        try databaseQueue.write { database in
            try createSharedSchema(database)
            try createVersionOneMembersSchema(database)
            try seedVersionOneData(database)
        }
        try executor.adoptBaseline(
            catalog: .versionOne,
            expectedFingerprint: expectedFingerprint
        )
    }

    func versionTwoPlan(
        fingerprints: (
            v1: PrototypeSchemaFingerprint,
            v2: PrototypeSchemaFingerprint
        )
    ) -> PrototypeSQLiteMigrationPlan {
        let definitionComponents = [
            "library@2",
            createVersionTwoMembersSQL(tableName: "__swiftql_new_members"),
            copyVersionTwoMembersSQL,
            "DROP TABLE members",
            "ALTER TABLE __swiftql_new_members RENAME TO members",
            createVersionTwoIndexSQL,
            createVersionTwoTriggerSQL,
            "copy-validation:row-id-values-status",
            "foreign-key-check:all",
            "integrity-check",
        ]
        return PrototypeSQLiteMigrationPlan(
            catalogID: PrototypeCatalog.versionTwo.id,
            sequence: 2,
            migrationID: "members-v2-rebuild",
            previousMigrationID: "adopt-library-v1",
            definitionFingerprint: PrototypeStableFingerprint.make(
                definitionComponents
            ),
            fromCatalog: .versionOne,
            toCatalog: .versionTwo,
            fromFingerprint: fingerprints.v1,
            toFingerprint: fingerprints.v2,
            foreignKeyPolicy: .deferredFullCheck,
            migrate: rebuildMembersToVersionTwo
        )
    }

    func history() throws -> [Int] {
        try databaseQueue.read { database in
            try Int.fetchAll(
                database,
                sql: """
                    SELECT sequence
                    FROM _swiftql_schema_migrations
                    WHERE catalog_id = ?
                    ORDER BY sequence
                    """,
                arguments: [PrototypeCatalog.versionOne.id]
            )
        }
    }
}


private enum PrototypeMigrationOutcome: Equatable {
    case applied(sequence: Int, migrationID: String)
    case alreadyApplied(sequence: Int, migrationID: String)
}


private enum PrototypeMigrationStage: String, Equatable {
    case before
    case after
}


private enum PrototypeMigrationError: Error, Equatable {
    case baselineAlreadyAdopted
    case schemaDivergence(
        stage: PrototypeMigrationStage,
        expected: PrototypeSchemaFingerprint,
        actual: PrototypeSchemaFingerprint
    )
    case historyGap(expectedPreviousSequence: Int, actual: Int?)
    case historyDrift(sequence: Int, migrationID: String)
    case copiedDataMismatch
    case integrityCheckFailed([String])
    case simulatedInterruption
    case userIntentRequired(String)
    case unsupportedDialect(String)
}


private enum PrototypeForeignKeyPolicy: Equatable {
    case immediate
    case deferredFullCheck
}


private struct PrototypeSQLiteMigrationPlan {
    let catalogID: String
    let sequence: Int
    let migrationID: String
    let previousMigrationID: String
    var definitionFingerprint: String
    let fromCatalog: PrototypeCatalog
    let toCatalog: PrototypeCatalog
    let fromFingerprint: PrototypeSchemaFingerprint
    let toFingerprint: PrototypeSchemaFingerprint
    let foreignKeyPolicy: PrototypeForeignKeyPolicy
    var injectFailureAfterValidation = false
    let migrate: (Database) throws -> Void
}


private struct PrototypeSQLiteMigrationExecutor {
    let databaseQueue: DatabaseQueue

    func adoptBaseline(
        catalog: PrototypeCatalog,
        expectedFingerprint: PrototypeSchemaFingerprint
    ) throws {
        try databaseQueue.writeWithoutTransaction { database in
            try createHistoryTable(database)
            try database.inTransaction(.immediate) {
                let existingCount = try Int.fetchOne(
                    database,
                    sql: """
                        SELECT COUNT(*)
                        FROM _swiftql_schema_migrations
                        WHERE catalog_id = ?
                        """,
                    arguments: [catalog.id]
                ) ?? 0
                guard existingCount == 0 else {
                    throw PrototypeMigrationError.baselineAlreadyAdopted
                }
                let actual = try PrototypeSchemaFingerprint.capture(
                    database,
                    catalog: catalog
                )
                guard actual == expectedFingerprint else {
                    throw PrototypeMigrationError.schemaDivergence(
                        stage: .before,
                        expected: expectedFingerprint,
                        actual: actual
                    )
                }
                try database.execute(
                    sql: """
                        INSERT INTO _swiftql_schema_migrations (
                            catalog_id,
                            sequence,
                            migration_id,
                            definition_fingerprint,
                            from_schema_fingerprint,
                            to_schema_fingerprint
                        ) VALUES (?, 1, ?, ?, ?, ?)
                        """,
                    arguments: [
                        catalog.id,
                        "adopt-library-v1",
                        PrototypeStableFingerprint.make([
                            "explicit-baseline-adoption",
                            expectedFingerprint.rawValue,
                        ]),
                        "unmanaged",
                        expectedFingerprint.rawValue,
                    ]
                )
                return .commit
            }
        }
    }

    func apply(
        _ plan: PrototypeSQLiteMigrationPlan
    ) throws -> PrototypeMigrationOutcome {
        var outcome: PrototypeMigrationOutcome?
        try databaseQueue.writeWithoutTransaction { database in
            try createHistoryTable(database)
            try withForeignKeyPolicy(plan.foreignKeyPolicy, database: database) {
                try database.inTransaction(.immediate) {
                    if let existing = try historyRow(
                        plan.sequence,
                        catalogID: plan.catalogID,
                        database: database
                    ) {
                        guard existing.migrationID == plan.migrationID,
                              existing.definitionFingerprint
                                == plan.definitionFingerprint,
                              existing.fromSchemaFingerprint
                                == plan.fromFingerprint.rawValue,
                              existing.toSchemaFingerprint
                                == plan.toFingerprint.rawValue else {
                            throw PrototypeMigrationError.historyDrift(
                                sequence: plan.sequence,
                                migrationID: plan.migrationID
                            )
                        }
                        let actual = try PrototypeSchemaFingerprint.capture(
                            database,
                            catalog: plan.toCatalog
                        )
                        guard actual == plan.toFingerprint else {
                            throw PrototypeMigrationError.schemaDivergence(
                                stage: .after,
                                expected: plan.toFingerprint,
                                actual: actual
                            )
                        }
                        outcome = .alreadyApplied(
                            sequence: plan.sequence,
                            migrationID: plan.migrationID
                        )
                        return .commit
                    }

                    let previous = try lastHistoryRow(
                        catalogID: plan.catalogID,
                        database: database
                    )
                    guard previous?.sequence == plan.sequence - 1,
                          previous?.migrationID == plan.previousMigrationID,
                          previous?.toSchemaFingerprint
                            == plan.fromFingerprint.rawValue else {
                        throw PrototypeMigrationError.historyGap(
                            expectedPreviousSequence: plan.sequence - 1,
                            actual: previous?.sequence
                        )
                    }

                    let before = try PrototypeSchemaFingerprint.capture(
                        database,
                        catalog: plan.fromCatalog
                    )
                    guard before == plan.fromFingerprint else {
                        throw PrototypeMigrationError.schemaDivergence(
                            stage: .before,
                            expected: plan.fromFingerprint,
                            actual: before
                        )
                    }

                    try plan.migrate(database)
                    if case .deferredFullCheck = plan.foreignKeyPolicy {
                        try database.checkForeignKeys()
                    }
                    let integrity = try String.fetchAll(
                        database,
                        sql: "PRAGMA integrity_check"
                    )
                    guard integrity == ["ok"] else {
                        throw PrototypeMigrationError.integrityCheckFailed(
                            integrity
                        )
                    }
                    let after = try PrototypeSchemaFingerprint.capture(
                        database,
                        catalog: plan.toCatalog
                    )
                    guard after == plan.toFingerprint else {
                        throw PrototypeMigrationError.schemaDivergence(
                            stage: .after,
                            expected: plan.toFingerprint,
                            actual: after
                        )
                    }
                    if plan.injectFailureAfterValidation {
                        throw PrototypeMigrationError.simulatedInterruption
                    }

                    try database.execute(
                        sql: """
                            INSERT INTO _swiftql_schema_migrations (
                                catalog_id,
                                sequence,
                                migration_id,
                                definition_fingerprint,
                                from_schema_fingerprint,
                                to_schema_fingerprint
                            ) VALUES (?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            plan.catalogID,
                            plan.sequence,
                            plan.migrationID,
                            plan.definitionFingerprint,
                            plan.fromFingerprint.rawValue,
                            plan.toFingerprint.rawValue,
                        ]
                    )
                    outcome = .applied(
                        sequence: plan.sequence,
                        migrationID: plan.migrationID
                    )
                    return .commit
                }
            }
        }
        return try XCTUnwrap(outcome)
    }

    private func withForeignKeyPolicy(
        _ policy: PrototypeForeignKeyPolicy,
        database: Database,
        operation: () throws -> Void
    ) throws {
        let foreignKeysWereEnabled = try Bool.fetchOne(
            database,
            sql: "PRAGMA foreign_keys"
        ) ?? false
        let shouldDisable = foreignKeysWereEnabled
            && policy == .deferredFullCheck
        if shouldDisable {
            try database.execute(sql: "PRAGMA foreign_keys = OFF")
        }

        var operationError: Error?
        do {
            try operation()
        }
        catch {
            operationError = error
        }

        var restorationError: Error?
        if shouldDisable {
            do {
                try database.execute(sql: "PRAGMA foreign_keys = ON")
            }
            catch {
                restorationError = error
            }
        }
        if let operationError {
            throw operationError
        }
        if let restorationError {
            throw restorationError
        }
    }

    private func createHistoryTable(_ database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE IF NOT EXISTS _swiftql_schema_migrations (
                    catalog_id TEXT NOT NULL,
                    sequence INTEGER NOT NULL CHECK (sequence > 0),
                    migration_id TEXT NOT NULL,
                    definition_fingerprint TEXT NOT NULL,
                    from_schema_fingerprint TEXT NOT NULL,
                    to_schema_fingerprint TEXT NOT NULL,
                    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (catalog_id, sequence),
                    UNIQUE (catalog_id, migration_id)
                )
                """
        )
    }

    private func historyRow(
        _ sequence: Int,
        catalogID: String,
        database: Database
    ) throws -> PrototypeHistoryRow? {
        try PrototypeHistoryRow.fetchOne(
            database,
            sql: """
                SELECT
                    sequence,
                    migration_id,
                    definition_fingerprint,
                    from_schema_fingerprint,
                    to_schema_fingerprint
                FROM _swiftql_schema_migrations
                WHERE catalog_id = ? AND sequence = ?
                """,
            arguments: [catalogID, sequence]
        )
    }

    private func lastHistoryRow(
        catalogID: String,
        database: Database
    ) throws -> PrototypeHistoryRow? {
        try PrototypeHistoryRow.fetchOne(
            database,
            sql: """
                SELECT
                    sequence,
                    migration_id,
                    definition_fingerprint,
                    from_schema_fingerprint,
                    to_schema_fingerprint
                FROM _swiftql_schema_migrations
                WHERE catalog_id = ?
                ORDER BY sequence DESC
                LIMIT 1
                """,
            arguments: [catalogID]
        )
    }
}


private struct PrototypeHistoryRow: FetchableRecord, Decodable {
    let sequence: Int
    let migrationID: String
    let definitionFingerprint: String
    let fromSchemaFingerprint: String
    let toSchemaFingerprint: String

    enum CodingKeys: String, CodingKey {
        case sequence
        case migrationID = "migration_id"
        case definitionFingerprint = "definition_fingerprint"
        case fromSchemaFingerprint = "from_schema_fingerprint"
        case toSchemaFingerprint = "to_schema_fingerprint"
    }
}


private struct PrototypeSchemaFingerprint:
    RawRepresentable,
    Equatable,
    CustomStringConvertible
{
    let rawValue: String

    var description: String {
        rawValue
    }

    static func capture(
        _ database: Database,
        catalog: PrototypeCatalog
    ) throws -> Self {
        let names = catalog.ownedSchemaNames
        let placeholders = Array(repeating: "?", count: names.count).joined(
            separator: ", "
        )
        let objects = try PrototypeSchemaObject.fetchAll(
            database,
            sql: """
                SELECT type, name, tbl_name, COALESCE(sql, '') AS sql
                FROM sqlite_schema
                WHERE name IN (\(placeholders))
                   OR tbl_name IN (\(placeholders))
                ORDER BY type, name, tbl_name
                """,
            arguments: StatementArguments(names + names)
        )
        let components = objects.map(\.stableComponent)
            + catalog.semanticComponents.sorted()
        return Self(rawValue: PrototypeStableFingerprint.make(components))
    }
}


private struct PrototypeSchemaObject: FetchableRecord, Decodable {
    let type: String
    let name: String
    let tableName: String
    let sql: String

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case tableName = "tbl_name"
        case sql
    }

    var stableComponent: String {
        [
            type,
            name,
            tableName,
            canonicalSQL,
        ]
            .joined(separator: "\u{1f}")
    }

    /// SQLite adds identifier quotes when a rebuilt table is renamed. The
    /// schema remains semantically equivalent, so the prototype canonicalizes
    /// quotes around the object's own stable names before fingerprinting.
    private var canonicalSQL: String {
        var result = sql.split(whereSeparator: \.isWhitespace).joined(
            separator: " "
        )
        for identifier in Set([name, tableName]) {
            result = result.replacingOccurrences(
                of: "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\"",
                with: identifier
            )
        }
        return result
    }
}


private struct PrototypeCatalog {
    let id: String
    let ownedSchemaNames: [String]
    let semanticComponents: [String]

    static let versionOne = PrototypeCatalog(
        id: "library",
        ownedSchemaNames: ["teams", "members", "member_audit"],
        semanticComponents: [
            "catalog:library@1",
            "members.id:swift.int@1:sqlite:integer:primary-key",
            "members.team_id:swift.int@1:sqlite:integer:required",
            "members.full_name:swift.string@1:sqlite:text:required",
            "members.nickname:swift.optional-string@1:sqlite:text:nullable",
            "members.legacy_code:legacy-code-text@1:sqlite:text:required",
        ]
    )

    static let versionTwo = PrototypeCatalog(
        id: "library",
        ownedSchemaNames: ["teams", "members", "member_audit"],
        semanticComponents: [
            "catalog:library@2",
            "members.id:swift.int@1:sqlite:integer:primary-key",
            "members.team_id:swift.int@1:sqlite:integer:required",
            "members.display_name:swift.string@1:sqlite:text:required",
            "members.nickname:swift.optional-string@1:sqlite:text:nullable",
            "members.status:status-text@1:sqlite:text:required",
        ]
    )
}


private enum PrototypeStableFingerprint {
    static func make(_ components: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in components.joined(separator: "\u{1e}").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}


private enum PrototypeSchemaChange {
    case possibleRename(from: String, to: String)
    case codecChange(column: String, from: String, to: String)
    case unsupportedDialect(String)
}


private enum PrototypeProposalPolicy {
    static func requireUserIntent(_ change: PrototypeSchemaChange) throws {
        switch change {
        case .possibleRename(let from, let to):
            throw PrototypeMigrationError.userIntentRequired(
                "Possible rename \(from) -> \(to) cannot be inferred."
            )
        case .codecChange(let column, let from, let to):
            throw PrototypeMigrationError.userIntentRequired(
                "Codec change \(from) -> \(to) for \(column) needs an explicit data transform."
            )
        case .unsupportedDialect(let dialect):
            throw PrototypeMigrationError.unsupportedDialect(dialect)
        }
    }
}


private struct PrototypeMemberV1: FetchableRecord, Decodable, Equatable {
    let id: Int
    let teamID: Int
    let fullName: String
    let nickname: String?
    let legacyCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case fullName = "full_name"
        case nickname
        case legacyCode = "legacy_code"
    }

    static func fetchAll(_ database: Database) throws -> [Self] {
        try Self.fetchAll(
            database,
            sql: """
                SELECT id, team_id, full_name, nickname, legacy_code
                FROM members
                ORDER BY id
                """
        )
    }
}


private struct PrototypeMemberV2: FetchableRecord, Decodable, Equatable {
    let id: Int
    let teamID: Int
    let displayName: String
    let nickname: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case displayName = "display_name"
        case nickname
        case status
    }

    static func fetchAll(_ database: Database) throws -> [Self] {
        try Self.fetchAll(
            database,
            sql: """
                SELECT id, team_id, display_name, nickname, status
                FROM members
                ORDER BY id
                """
        )
    }
}


private struct PrototypeAuditRow: FetchableRecord, Decodable, Equatable {
    let memberID: Int
    let oldName: String
    let newName: String

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case oldName = "old_name"
        case newName = "new_name"
    }

    static func fetchAll(_ database: Database) throws -> [Self] {
        try Self.fetchAll(
            database,
            sql: """
                SELECT member_id, old_name, new_name
                FROM member_audit
                ORDER BY rowid
                """
        )
    }
}


private func createSharedSchema(_ database: Database) throws {
    try database.execute(
        sql: """
            CREATE TABLE teams (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE
            );
            CREATE TABLE member_audit (
                member_id INTEGER NOT NULL,
                old_name TEXT NOT NULL,
                new_name TEXT NOT NULL
            );
            """
    )
}


private func createVersionOneMembersSchema(_ database: Database) throws {
    try database.execute(
        sql: """
            CREATE TABLE members (
                id INTEGER PRIMARY KEY,
                team_id INTEGER NOT NULL
                    REFERENCES teams(id) ON DELETE CASCADE,
                full_name TEXT NOT NULL,
                nickname TEXT,
                legacy_code TEXT NOT NULL
            );
            CREATE INDEX members_team_name_idx
                ON members(team_id, full_name);
            CREATE TRIGGER members_name_audit
            AFTER UPDATE OF full_name ON members
            BEGIN
                INSERT INTO member_audit(member_id, old_name, new_name)
                VALUES (OLD.id, OLD.full_name, NEW.full_name);
            END;
            """
    )
}


private func seedVersionOneData(_ database: Database) throws {
    try database.execute(
        sql: """
            INSERT INTO teams(id, name) VALUES (1, 'Core');
            INSERT INTO members(
                id, team_id, full_name, nickname, legacy_code
            ) VALUES
                (1, 1, 'Alice', 'Al', 'enabled'),
                (2, 1, 'Bob Brown', NULL, 'disabled');
            UPDATE members SET full_name = 'Alice Adams' WHERE id = 1;
            """
    )
}


private func createVersionTwoMembersSchema(
    _ database: Database,
    tableName: String
) throws {
    try database.execute(sql: createVersionTwoMembersSQL(tableName: tableName))
}


private func createVersionTwoDependents(_ database: Database) throws {
    try database.execute(
        sql: "\(createVersionTwoIndexSQL);\n\(createVersionTwoTriggerSQL);"
    )
}


private func rebuildMembersToVersionTwo(_ database: Database) throws {
    let before = try PrototypeMemberV1.fetchAll(database)
    try createVersionTwoMembersSchema(
        database,
        tableName: "__swiftql_new_members"
    )
    try database.execute(sql: copyVersionTwoMembersSQL)

    let copied = try PrototypeMemberV2.fetchAll(
        database,
        sql: """
            SELECT id, team_id, display_name, nickname, status
            FROM __swiftql_new_members
            ORDER BY id
            """
    )
    let expected = before.map {
        PrototypeMemberV2(
            id: $0.id,
            teamID: $0.teamID,
            displayName: $0.fullName,
            nickname: $0.nickname,
            status: $0.legacyCode == "disabled" ? "inactive" : "active"
        )
    }
    guard copied == expected else {
        throw PrototypeMigrationError.copiedDataMismatch
    }

    try database.execute(sql: "DROP TABLE members")
    try database.execute(
        sql: "ALTER TABLE __swiftql_new_members RENAME TO members"
    )
    try createVersionTwoDependents(database)

    guard try PrototypeMemberV2.fetchAll(database) == expected else {
        throw PrototypeMigrationError.copiedDataMismatch
    }
}


private func createVersionTwoMembersSQL(tableName: String) -> String {
    """
    CREATE TABLE \(tableName) (
        id INTEGER PRIMARY KEY,
        team_id INTEGER NOT NULL
            REFERENCES teams(id) ON DELETE CASCADE,
        display_name TEXT NOT NULL CHECK (length(display_name) > 0),
        nickname TEXT,
        status TEXT NOT NULL DEFAULT 'active'
            CHECK (status IN ('active', 'inactive'))
    )
    """
}


private let copyVersionTwoMembersSQL = """
    INSERT INTO __swiftql_new_members (
        id, team_id, display_name, nickname, status
    )
    SELECT
        id,
        team_id,
        full_name,
        nickname,
        CASE legacy_code
            WHEN 'disabled' THEN 'inactive'
            ELSE 'active'
        END
    FROM members
    """


private let createVersionTwoIndexSQL = """
    CREATE INDEX members_team_display_name_idx
        ON members(team_id, display_name)
    """


private let createVersionTwoTriggerSQL = """
    CREATE TRIGGER members_display_name_audit
    AFTER UPDATE OF display_name ON members
    BEGIN
        INSERT INTO member_audit(member_id, old_name, new_name)
        VALUES (OLD.id, OLD.display_name, NEW.display_name);
    END
    """
