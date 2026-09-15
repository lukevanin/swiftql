//
//  DeclaredQueryManifestTests.swift
//  SwiftQLSQLiteBuildValidationDeclaredQueriesTests
//
//  Issue #659: declared queries lower to static descriptors, the descriptors
//  project into a format version 2 manifest with no hand-written query list,
//  and that manifest round-trips through the validator against a real
//  snapshot.
//

import Foundation
import GRDB
import SwiftQL
import SwiftQLCore
import SwiftQLSQLiteBuildValidationDeclaredQueries
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator
import XCTest


@SQLTable
struct DeclaredManifestAuthor: Equatable {
    let id: String
    let name: String
    let rating: Int?
}


@SQLTable
struct DeclaredManifestBook: Equatable {
    let id: String
    let authorID: String
    let title: String
}


/// A table the snapshot deliberately does not contain.
@SQLTable
struct DeclaredManifestMissing: Equatable {
    let id: String
}


@SQLResult
struct DeclaredManifestTitle: Equatable {
    let authorName: String
    let title: String
}


@SQLQueries
extension GRDBDatabase {

    fileprivate struct Query {

        func declaredAuthors() -> [DeclaredManifestAuthor] {
            sqlResult { schema in
                let author = schema.table(DeclaredManifestAuthor.self)
                Select(author)
                From(author)
                OrderBy(author.name.ascending())
            }
        }

        func declaredAuthor(id: String) -> DeclaredManifestAuthor? {
            sqlResult { schema in
                let author = schema.table(DeclaredManifestAuthor.self)
                Select(author)
                From(author)
                Where(author.id == id)
            }
        }

        func declaredTitles(authorID: String, minimumRating: Int) -> [DeclaredManifestTitle] {
            sqlResult { schema in
                let author = schema.table(DeclaredManifestAuthor.self)
                let book = schema.table(DeclaredManifestBook.self)
                Select(DeclaredManifestTitle.columns(
                    authorName: author.name,
                    title: book.title
                ))
                From(book)
                Join.Inner(author, on: author.id == book.authorID)
                Where(author.id == authorID && author.rating >= minimumRating)
            }
        }
    }
}


extension GRDBDatabase {

    /// Declared with the peer form, against a table the snapshot lacks.
    @SQLQuery
    func declaredMissingRows() -> [DeclaredManifestMissing] {
        sqlResult { schema in
            let missing = schema.table(DeclaredManifestMissing.self)
            Select(missing)
            From(missing)
        }
    }
}


final class DeclaredQueryManifestTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeclaredQueryManifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
    }

    /// Writes a rollback-journal snapshot holding the author and book tables.
    private func makeSnapshot() throws -> URL {
        let url = directory.appendingPathComponent("snapshot.sqlite")
        let encoder = XLiteEncoder(dialect: XLSQLiteDialect())
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { database in
            try database.execute(sql: encoder.makeValidatedSQL(sqlCreate(DeclaredManifestAuthor.self)).sql)
            try database.execute(sql: encoder.makeValidatedSQL(sqlCreate(DeclaredManifestBook.self)).sql)
        }
        try queue.close()
        return url
    }

    // MARK: - Discovery

    func testTheContainerListsEverySpecificationInDeclarationOrder() {
        let queries = GRDBDatabase.declaredQueries

        XCTAssertEqual(
            queries.map(\.id),
            [
                "GRDBDatabase.declaredAuthors",
                "GRDBDatabase.declaredAuthor",
                "GRDBDatabase.declaredTitles",
            ]
        )
        XCTAssertEqual(queries.map(\.cardinality), [.many, .zeroOrOne, .many])
        XCTAssertEqual(
            queries.map { $0.parameters.map(\.name) },
            [[], ["id"], ["authorID", "minimumRating"]]
        )
    }

    // MARK: - Descriptor

    func testADescriptorCarriesTheRenderedParametersAndResults() throws {
        let lowered = try GRDBDatabase.declaredQueries[1].makeDescriptor()
        let descriptor = lowered.descriptor

        XCTAssertEqual(descriptor.definitionIdentity.description, "GRDBDatabase/declaredAuthor@1")
        XCTAssertEqual(descriptor.cardinality, .zeroOrOne)
        XCTAssertEqual(descriptor.parameters.map(\.identity.description), ["parameter/id"])
        XCTAssertEqual(descriptor.parameters.map(\.slot.key), [.named("id")])
        XCTAssertEqual(descriptor.parameters.map(\.storageIdentifier.rawValue), ["text"])
        XCTAssertEqual(lowered.resultAliases, ["id", "name", "rating"])
        XCTAssertEqual(
            descriptor.results.slots.map(\.valueTypeIdentifier.rawValue),
            ["swift.string", "swift.string", "swift.int"]
        )
        XCTAssertEqual(
            descriptor.results.slots.map(\.nullability),
            [.required, .required, .nullable]
        )
        XCTAssertEqual(
            descriptor.results.slots.map(\.storageIdentifier.rawValue),
            ["text", "text", "integer"]
        )
    }

    func testThePeerDescriptorRendersTheSQLItsStatementBuilderRenders() throws {
        let databaseURL = directory.appendingPathComponent("peer.sqlite")
        let pool = try DatabasePool(path: databaseURL.path)
        defer { try? pool.close() }
        let database = try GRDBDatabase(databasePool: pool, formatter: XLiteFormatter(), logger: nil)

        let descriptor = try GRDBDatabase.declaredMissingRowsDeclaredQuery.makeDescriptor().descriptor
        let executorSQL = database.encoder.makeSQL(database.declaredMissingRowsStatement()).sql

        XCTAssertEqual(descriptor.sql, executorSQL)
        XCTAssertEqual(descriptor.definitionIdentity.description, "GRDBDatabase/declaredMissingRows@1")
    }

    /// The identity is derived only from the declaration and the SQL it
    /// renders, so it is the same in every build. The digest pins it: a
    /// change to it is a change to every manifest generated from this
    /// declaration. The identity spells its complete canonical bytes, so the
    /// test pins their SHA-256 rather than a literal hundreds of characters
    /// long.
    func testTheDescriptorIdentityIsStableAcrossBuilds() throws {
        let query = GRDBDatabase.declaredQueries[1]
        let first = try query.makeDescriptor().descriptor.identity
        let second = try query.makeDescriptor().descriptor.identity

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.formatVersion, .v1)
        XCTAssertEqual(first.definitionIdentity.description, "GRDBDatabase/declaredAuthor@1")
        XCTAssertEqual(
            SQLiteBuildValidationSHA256.hexDigest(of: Data(first.canonicalBytes)),
            "859b3c1558a7cd766aaffab4551fe1bcfd5a28e639beec04ff01315e1d6c915e"
        )
    }

    // MARK: - Manifest

    func testAnEmittedManifestValidatesAgainstARealSnapshot() throws {
        let snapshotURL = try makeSnapshot()

        let manifest = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: GRDBDatabase.declaredQueries,
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )

        XCTAssertEqual(manifest.formatVersion, .v2)
        XCTAssertNil(manifest.conformanceInventoryVersion)
        XCTAssertNil(manifest.combinatorialManifestVersion)
        XCTAssertEqual(manifest.queries.count, 3)

        let report = try SQLiteBuildValidator.validate(
            manifest: manifest,
            againstDatabaseAt: snapshotURL
        )
        XCTAssertEqual(report.overallVerdict, .passed, "\(report.diagnostics)")
        XCTAssertEqual(
            Set(report.outcomes.map(\.queryID)),
            Set(GRDBDatabase.declaredQueries.map(\.id))
        )
    }

    func testABrokenDeclarationFailsWithTheValidatorsOwnDiagnostic() throws {
        let snapshotURL = try makeSnapshot()

        let manifest = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: GRDBDatabase.declaredQueries + [GRDBDatabase.declaredMissingRowsDeclaredQuery],
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )
        let report = try SQLiteBuildValidator.validate(
            manifest: manifest,
            againstDatabaseAt: snapshotURL
        )

        XCTAssertEqual(report.overallVerdict, .failed)
        let failed = report.outcomes.filter { $0.verdict == .failed }
        XCTAssertEqual(failed.map(\.queryID), ["GRDBDatabase.declaredMissingRows"])
        XCTAssertTrue(
            failed.flatMap(\.diagnostics).contains { $0.message.contains("DeclaredManifestMissing") },
            "\(failed.flatMap(\.diagnostics))"
        )
    }

    func testRegeneratingAnUnchangedManifestIsByteIdentical() throws {
        let snapshotURL = try makeSnapshot()

        let first = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: GRDBDatabase.declaredQueries,
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )
        let second = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: GRDBDatabase.declaredQueries,
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )

        XCTAssertEqual(try first.canonicalJSONData(), try second.canonicalJSONData())
    }

    func testATargetWithNoDeclaredQueriesProducesAValidManifest() throws {
        let snapshotURL = try makeSnapshot()

        let manifest = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: [],
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )

        XCTAssertEqual(manifest.queries, [])
        let report = try SQLiteBuildValidator.validate(
            manifest: manifest,
            againstDatabaseAt: snapshotURL
        )
        XCTAssertEqual(report.overallVerdict, .passed, "\(report.diagnostics)")
    }
}
