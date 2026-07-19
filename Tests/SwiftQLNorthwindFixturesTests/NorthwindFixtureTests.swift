import Dispatch
import Foundation
import GRDB
@testable import SwiftQLNorthwindFixtures
import XCTest


final class NorthwindFixtureContractTests: XCTestCase {

    func testPortableSHA256MatchesPublishedVectors() {
        XCTAssertEqual(
            PortableSHA256.hexDigest(of: Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            PortableSHA256.hexDigest(of: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            PortableSHA256.hexDigest(
                of: Data("The quick brown fox jumps over the lazy dog".utf8)
            ),
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        )
    }

    func testPinnedFixtureChecksumIntegrityCatalogAndRowSentinels() throws {
        let metadata = NorthwindFixture.metadata
        let validation = try NorthwindFixture.validateCanonical()

        XCTAssertEqual(validation.databaseURL, try NorthwindFixture.canonicalURL)
        XCTAssertEqual(validation.databaseSHA256, metadata.databaseSHA256)
        XCTAssertEqual(validation.databaseByteCount, metadata.databaseByteCount)
        XCTAssertEqual(validation.integrityCheck, ["ok"])
        XCTAssertEqual(validation.applicationTables, metadata.applicationTables)
        XCTAssertEqual(validation.views, metadata.views)
        XCTAssertEqual(validation.rowCounts, metadata.rowCounts)
        XCTAssertFalse(validation.sqliteVersion.isEmpty)
        XCTAssertFalse(validation.sqliteSourceID.isEmpty)
        XCTAssertEqual(validation.applicationTables.count, 13)
        XCTAssertEqual(validation.views.count, 17)
        XCTAssertEqual(validation.rowCounts["Customers"], 93)
        XCTAssertEqual(validation.rowCounts["Orders"], 830)
        XCTAssertEqual(validation.rowCounts["Order Details"], 2_155)
        XCTAssertEqual(validation.rowCounts["Products"], 77)
        XCTAssertEqual(validation.sentinelOrderID, metadata.sentinelOrderID)
        XCTAssertEqual(
            validation.sentinelOrderDetailCount,
            metadata.sentinelOrderDetailCount
        )
        XCTAssertEqual(validation.sentinelOrderSubtotal, metadata.sentinelOrderSubtotal)
        XCTAssertEqual(validation.sentinelOrderID, 10_248)
        XCTAssertEqual(validation.sentinelOrderDetailCount, 3)
        XCTAssertEqual(validation.sentinelOrderSubtotal, 440.0)

        let licenseData = try Data(contentsOf: NorthwindFixture.licenseURL)
        XCTAssertEqual(
            PortableSHA256.hexDigest(of: licenseData),
            metadata.licenseSHA256
        )
        let license = try String(contentsOf: NorthwindFixture.licenseURL, encoding: .utf8)
        XCTAssertTrue(license.contains("The MIT License (MIT)"))
        XCTAssertTrue(license.contains("Copyright (c) 2016 JP White"))

        let provenanceData = try Data(contentsOf: NorthwindFixture.provenanceURL)
        let provenance = try XCTUnwrap(
            JSONSerialization.jsonObject(with: provenanceData) as? [String: Any]
        )
        let upstream = try XCTUnwrap(provenance["upstream"] as? [String: Any])
        let artifact = try XCTUnwrap(provenance["artifact"] as? [String: Any])
        let expected = try XCTUnwrap(provenance["expected"] as? [String: Any])
        let policy = try XCTUnwrap(provenance["policy"] as? [String: Any])

        XCTAssertEqual(
            Set(provenance.keys),
            ["schema_version", "upstream", "artifact", "expected", "policy"]
        )
        XCTAssertEqual(provenance["schema_version"] as? Int, metadata.provenanceSchemaVersion)
        XCTAssertEqual(
            Set(upstream.keys),
            [
                "repository",
                "commit",
                "path",
                "url",
                "license_spdx",
                "license_path",
                "license_git_blob_sha",
            ]
        )
        XCTAssertEqual(upstream["repository"] as? String, metadata.upstreamRepository)
        XCTAssertEqual(upstream["commit"] as? String, metadata.upstreamCommit)
        XCTAssertEqual(upstream["path"] as? String, metadata.upstreamPath)
        XCTAssertEqual(upstream["url"] as? String, metadata.upstreamURL)
        XCTAssertEqual(upstream["license_spdx"] as? String, metadata.licenseSPDX)
        XCTAssertEqual(upstream["license_path"] as? String, metadata.upstreamLicensePath)
        XCTAssertEqual(
            upstream["license_git_blob_sha"] as? String,
            metadata.upstreamLicenseGitBlobSHA
        )

        XCTAssertEqual(
            Set(artifact.keys),
            [
                "path",
                "sha256",
                "byte_count",
                "license_notice_path",
                "license_notice_sha256",
            ]
        )
        XCTAssertEqual(artifact["path"] as? String, metadata.databaseResourcePath)
        XCTAssertEqual(artifact["sha256"] as? String, metadata.databaseSHA256)
        XCTAssertEqual(artifact["byte_count"] as? Int, metadata.databaseByteCount)
        XCTAssertEqual(artifact["license_notice_path"] as? String, metadata.licenseNoticePath)
        XCTAssertEqual(artifact["license_notice_sha256"] as? String, metadata.licenseSHA256)

        let sentinelKey = "order_\(metadata.sentinelOrderID)"
        XCTAssertEqual(
            Set(expected.keys),
            ["application_tables", "views", "row_counts", sentinelKey]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(expected["application_tables"] as? [String])),
            metadata.applicationTables
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(expected["views"] as? [String])),
            metadata.views
        )
        XCTAssertEqual(
            try XCTUnwrap(expected["row_counts"] as? [String: Int]),
            metadata.rowCounts
        )
        let sentinel = try XCTUnwrap(expected[sentinelKey] as? [String: Any])
        XCTAssertEqual(Set(sentinel.keys), ["detail_count", "total"])
        XCTAssertEqual(
            sentinel["detail_count"] as? Int,
            metadata.sentinelOrderDetailCount
        )
        XCTAssertEqual(sentinel["total"] as? Double, metadata.sentinelOrderSubtotal)

        XCTAssertEqual(
            Set(policy.keys),
            [
                "canonical_access",
                "mutation_access",
                "runtime_network_access",
                "performance_claim",
            ]
        )
        XCTAssertEqual(policy["canonical_access"] as? String, metadata.canonicalAccessPolicy)
        XCTAssertEqual(policy["mutation_access"] as? String, metadata.mutationAccessPolicy)
        XCTAssertEqual(policy["runtime_network_access"] as? Bool, metadata.runtimeNetworkAccess)
        XCTAssertEqual(policy["performance_claim"] as? Bool, metadata.performanceClaim)

        let updateGuide = try String(
            contentsOf: NorthwindFixture.updateGuideURL,
            encoding: .utf8
        )
        XCTAssertTrue(updateGuide.contains("## Updating the fixture"))
        XCTAssertTrue(updateGuide.contains("UUID-named directory"))
        XCTAssertTrue(updateGuide.contains("16,143 orders"))
    }

    func testFixtureValidationRejectsTamperingAndWritableCanonicalAccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftql-northwind-tamper-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        var bytes = try Data(contentsOf: NorthwindFixture.canonicalURL)
        let offset = bytes.index(bytes.startIndex, offsetBy: 128)
        bytes[offset] ^= 0xff
        let tamperedURL = directory.appendingPathComponent("northwind.db")
        try bytes.write(to: tamperedURL, options: .atomic)

        XCTAssertThrowsError(try NorthwindFixture.validate(at: tamperedURL)) { error in
            guard let fixtureError = error as? NorthwindFixtureError,
                  case let .checksumMismatch(resource, expected, actual) = fixtureError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(resource, "database")
            XCTAssertEqual(expected, NorthwindFixture.metadata.databaseSHA256)
            XCTAssertNotEqual(actual, expected)
        }

        let pool = try NorthwindFixture.validatedReadOnlyPool()
        defer { try? pool.close() }

        XCTAssertEqual(
            try pool.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM Customers")
            },
            93
        )
        XCTAssertThrowsError(
            try pool.writeWithoutTransaction { database in
                try database.execute(sql: "CREATE TABLE must_not_exist (id INTEGER)")
            }
        )
        XCTAssertEqual(
            try pool.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM Customers")
            },
            93
        )
    }

    func testTemporaryCopiesAreWritableIsolatedAndRemovedWithSidecars() throws {
        let canonicalBefore = try NorthwindFixture.validateCanonical()
        var copiedURLs: [URL] = []

        try NorthwindFixture.withTemporaryCopy { first in
            copiedURLs.append(first.url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
            XCTAssertEqual(
                first.initialValidation.databaseSHA256,
                canonicalBefore.databaseSHA256
            )
            try first.databasePool.write { database in
                try database.execute(sql: "CREATE TABLE first_copy_only (id INTEGER)")
            }
            XCTAssertTrue(try first.databasePool.read { database in
                try database.tableExists("first_copy_only")
            })

            try NorthwindFixture.withTemporaryCopy { second in
                copiedURLs.append(second.url)
                XCTAssertNotEqual(first.url, second.url)
                XCTAssertNotEqual(
                    first.url.deletingLastPathComponent(),
                    second.url.deletingLastPathComponent()
                )
                XCTAssertFalse(try second.databasePool.read { database in
                    try database.tableExists("first_copy_only")
                })
                try second.databasePool.write { database in
                    try database.execute(sql: "CREATE TABLE second_copy_only (id INTEGER)")
                }
                XCTAssertFalse(try first.databasePool.read { database in
                    try database.tableExists("second_copy_only")
                })
            }
        }

        for url in copiedURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: url.deletingLastPathComponent().path
                )
            )
        }
        XCTAssertEqual(
            try NorthwindFixture.validateCanonical().databaseSHA256,
            canonicalBefore.databaseSHA256
        )
    }

    func testTemporaryCopyRemovesDirectoryWhenBodyThrows() throws {
        let canonicalBefore = try NorthwindFixture.validateCanonical()
        var copiedURL: URL?

        XCTAssertThrowsError(
            try NorthwindFixture.withTemporaryCopy { copy -> Void in
                copiedURL = copy.url
                try copy.databasePool.write { database in
                    try database.execute(sql: "CREATE TABLE throwing_body_only (id INTEGER)")
                }
                throw TemporaryCopyProbeError.intentionalBodyFailure
            }
        ) { error in
            XCTAssertEqual(
                error as? TemporaryCopyProbeError,
                .intentionalBodyFailure
            )
        }

        let unwrappedURL = try XCTUnwrap(copiedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unwrappedURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: unwrappedURL.deletingLastPathComponent().path
            )
        )
        XCTAssertEqual(
            try NorthwindFixture.validateCanonical().databaseSHA256,
            canonicalBefore.databaseSHA256
        )
    }

    func testConcurrentTemporaryCopiesAreUniqueWritableAndCleanedUp() {
        let copyCount = 4
        let allCopiesReady = expectation(description: "all concurrent copies are open")
        allCopiesReady.expectedFulfillmentCount = copyCount
        allCopiesReady.assertForOverFulfill = true

        let releaseCopies = DispatchSemaphore(value: 0)
        let workers = DispatchGroup()
        let queue = DispatchQueue(
            label: "SwiftQLNorthwindFixturesTests.concurrent-copies",
            attributes: .concurrent
        )
        let recorder = ConcurrentCopyRecorder()

        for index in 0..<copyCount {
            workers.enter()
            queue.async {
                defer { workers.leave() }
                do {
                    let cleanedURL = try NorthwindFixture.withTemporaryCopy { copy -> URL in
                        try copy.databasePool.write { database in
                            try database.execute(
                                sql: "CREATE TABLE concurrent_copy_\(index) (id INTEGER)"
                            )
                        }
                        recorder.record(url: copy.url)
                        allCopiesReady.fulfill()
                        guard releaseCopies.wait(timeout: .now() + 30) == .success else {
                            throw TemporaryCopyProbeError.concurrentReleaseTimedOut
                        }
                        return copy.url
                    }
                    if FileManager.default.fileExists(atPath: cleanedURL.path) {
                        recorder.record(
                            failure: "copy still exists after successful cleanup: \(cleanedURL.path)"
                        )
                    }
                } catch {
                    recorder.record(failure: String(describing: error))
                }
            }
        }

        wait(for: [allCopiesReady], timeout: 30)
        for _ in 0..<copyCount {
            releaseCopies.signal()
        }
        XCTAssertEqual(workers.wait(timeout: .now() + 30), .success)

        let snapshot = recorder.snapshot()
        XCTAssertTrue(snapshot.failures.isEmpty, snapshot.failures.joined(separator: "\n"))
        XCTAssertEqual(snapshot.urls.count, copyCount)
        XCTAssertEqual(Set(snapshot.urls).count, copyCount)
        XCTAssertEqual(
            Set(snapshot.urls.map { $0.deletingLastPathComponent() }).count,
            copyCount
        )
        for url in snapshot.urls {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: url.deletingLastPathComponent().path
                )
            )
        }
    }
}


private enum TemporaryCopyProbeError: Error, Equatable {
    case intentionalBodyFailure
    case concurrentReleaseTimedOut
}


private final class ConcurrentCopyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var failures: [String] = []

    func record(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    func record(failure: String) {
        lock.lock()
        defer { lock.unlock() }
        failures.append(failure)
    }

    func snapshot() -> (urls: [URL], failures: [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (urls, failures)
    }
}
