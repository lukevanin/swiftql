import XCTest
import GRDB
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteEQPVariancePrototype


final class EQPVarianceCaptureTests: XCTestCase {
    func testArgumentsThrowsRatherThanDroppingAMissingNamedKey() {
        // A malformed named binding with no key_name: silently dropping it
        // would bind fewer values than the rendered SQL expects.
        let malformed = SQLiteCombinatorialBinding(
            logicalIndex: 0,
            keyKind: .named,
            keyName: nil,
            keyIndex: nil,
            storage: .integer,
            taggedValue: .integer(1),
            repeatCount: 1
        )
        XCTAssertThrowsError(
            try EQPVarianceCapture.arguments(for: [malformed], statementID: "s1")
        ) { error in
            guard case EQPVarianceCaptureError.invalidBinding(let statementID, _) = error else {
                return XCTFail("expected invalidBinding, got \(error)")
            }
            XCTAssertEqual(statementID, "s1")
        }
    }

    func testArgumentsThrowsOnMixedNamedAndIndexedBindings() {
        let named = SQLiteCombinatorialBinding(
            logicalIndex: 0,
            keyKind: .named,
            keyName: "a",
            keyIndex: nil,
            storage: .integer,
            taggedValue: .integer(1),
            repeatCount: 1
        )
        let indexed = SQLiteCombinatorialBinding(
            logicalIndex: 1,
            keyKind: .indexed,
            keyName: nil,
            keyIndex: 2,
            storage: .integer,
            taggedValue: .integer(2),
            repeatCount: 1
        )
        XCTAssertThrowsError(
            try EQPVarianceCapture.arguments(for: [named, indexed], statementID: "s2")
        ) { error in
            guard case EQPVarianceCaptureError.invalidBinding(let statementID, _) = error else {
                return XCTFail("expected invalidBinding, got \(error)")
            }
            XCTAssertEqual(statementID, "s2")
        }
    }

    func testArgumentsThrowsRatherThanOverwritingADuplicateNamedKey() {
        let first = SQLiteCombinatorialBinding(
            logicalIndex: 0,
            keyKind: .named,
            keyName: "a",
            keyIndex: nil,
            storage: .integer,
            taggedValue: .integer(1),
            repeatCount: 1
        )
        let duplicate = SQLiteCombinatorialBinding(
            logicalIndex: 1,
            keyKind: .named,
            keyName: "a",
            keyIndex: nil,
            storage: .integer,
            taggedValue: .integer(2),
            repeatCount: 1
        )
        XCTAssertThrowsError(
            try EQPVarianceCapture.arguments(for: [first, duplicate], statementID: "s3")
        ) { error in
            guard case EQPVarianceCaptureError.invalidBinding(let statementID, _) = error else {
                return XCTFail("expected invalidBinding, got \(error)")
            }
            XCTAssertEqual(statementID, "s3")
        }
    }


    func testCaptureIsByteIdenticalAcrossRepeatedRunsInProcess() throws {
        let corpus = try EQPVarianceCorpus.assemble()
        let pool = try NorthwindFixture.validatedReadOnlyPool()

        let first = try pool.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: corpus, label: "reproducibility-check")
        }
        let second = try pool.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: corpus, label: "reproducibility-check")
        }

        XCTAssertEqual(
            try EQPVarianceCanonicalJSON.encode(first),
            try EQPVarianceCanonicalJSON.encode(second)
        )
    }

    func testCaptureCoversEveryCorpusStatementWithAtLeastOneRow() throws {
        let corpus = try EQPVarianceCorpus.assemble()
        let pool = try NorthwindFixture.validatedReadOnlyPool()

        let run = try pool.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: corpus, label: "coverage-check")
        }

        XCTAssertEqual(run.statements.count, corpus.count)
        for statement in run.statements {
            XCTAssertFalse(statement.rows.isEmpty, "\(statement.statementID) produced no EQP rows")
        }
    }

    func testCaptureNeverMutatesThePinnedNorthwindSnapshot() throws {
        let before = try NorthwindFixture.validateCanonical()
        let corpus = try EQPVarianceCorpus.assemble()
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        _ = try pool.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: corpus, label: "mutation-check")
        }
        let after = try NorthwindFixture.validateCanonical()
        XCTAssertEqual(before.databaseSHA256, after.databaseSHA256)
    }

    /// Guards the checked-in `apple-system` evidence against silent drift
    /// from a corpus/schema change, but only when this host's linked SQLite
    /// is the exact build the evidence was captured on. A mismatch is
    /// exactly the variance #390 measures, not a test failure — SQLite does
    /// not guarantee a stable EQP output across versions, and Apple ships a
    /// different SQLite per OS release, so asserting byte-identity
    /// unconditionally would make this test fail on most CI legs by design.
    func testCheckedInAppleSystemEvidenceMatchesWhenRuntimeIsIdentical() throws {
        let pinnedURL = try pinnedEvidenceURL(named: "capture_apple-system-3.51.0.json")
        let pinnedRun = try JSONDecoder().decode(
            EQPCaptureRun.self,
            from: Data(contentsOf: pinnedURL)
        )

        let corpus = try EQPVarianceCorpus.assemble()
        let pool = try NorthwindFixture.validatedReadOnlyPool()
        let freshRun = try pool.read { database in
            try EQPVarianceCapture.capture(from: database, corpus: corpus, label: pinnedRun.label)
        }

        guard freshRun.runtimeMetadata.sqliteVersion == pinnedRun.runtimeMetadata.sqliteVersion,
              freshRun.runtimeMetadata.sqliteSourceID == pinnedRun.runtimeMetadata.sqliteSourceID
        else {
            throw XCTSkip(
                "Pinned evidence was captured on SQLite \(pinnedRun.runtimeMetadata.sqliteVersion) "
                    + "(\(pinnedRun.runtimeMetadata.sqliteSourceID)); this host links "
                    + "\(freshRun.runtimeMetadata.sqliteVersion) (\(freshRun.runtimeMetadata.sqliteSourceID))."
            )
        }

        XCTAssertEqual(
            try EQPVarianceCanonicalJSON.encode(freshRun),
            try EQPVarianceCanonicalJSON.encode(pinnedRun)
        )
    }
}


func pinnedEvidenceURL(named name: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Evidence") else {
        throw EvidenceFixtureError.missingResource(name)
    }
    return url
}


enum EvidenceFixtureError: Error {
    case missingResource(String)
}
