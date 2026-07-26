import XCTest
import GRDB
import SwiftQLNorthwindFixtures
import SwiftQLSQLiteEQPVariancePrototype


final class EQPVarianceCaptureTests: XCTestCase {
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
