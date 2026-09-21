//
//  DeclaredQueryManifestTests.swift
//  SwiftQLSQLiteBuildValidationDeclaredQueriesTests
//
//  Issue #659: declared queries lower to static descriptors with the SQL
//  their executors run, the generated registry finds every declaration in
//  this target, and the descriptors project into a format version 2 manifest
//  that round-trips through the validator against a real snapshot.
//
//  This test target applies SwiftQLDeclaredQueryRegistryPlugin, so
//  `Registry` below is generated from the declarations in this file.
//

import Foundation
import GRDB
import SwiftQL
import SwiftQLCore
import SwiftQLSQLiteBuildValidationDeclaredQueries
import SwiftQLSQLiteBuildValidationManifest
import SwiftQLSQLiteBuildValidationValidator
import XCTest


private typealias Registry = SwiftQLSQLiteBuildValidationDeclaredQueriesTestsDeclaredQueries


// MARK: - Schema

@SQLTable
struct DeclaredManifestAuthor: Equatable {
    let id: String
    let name: String
    let rating: Int?
}


enum DeclaredManifestGenre: Int, XLEnum, CaseIterable {
    typealias T = Self

    case fiction = 0
    case poetry = 1

    static func sqlDefault() -> DeclaredManifestGenre {
        .fiction
    }
}


/// A custom literal stored as text.
struct DeclaredManifestCode: XLCustomType, XLComparable, Hashable {
    typealias T = Self

    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(reader: XLFieldReader) throws {
        value = try reader.readText()
    }

    func bind(context: inout XLBindingContext) {
        context.bindText(value: value)
    }

    func makeSQL(context: inout XLBuilder) {
        context.text(value)
    }

    static func sqlDefault() -> DeclaredManifestCode {
        DeclaredManifestCode("")
    }
}


@SQLTable
struct DeclaredManifestBook: Equatable {
    let id: String
    let authorID: String
    let title: String
    let genre: DeclaredManifestGenre
    let code: DeclaredManifestCode
}


/// A row read through a static layout whose date travels through a codec.
@SQLTable
struct DeclaredManifestEvent: Equatable {
    let id: String

    @SQLCodec(XLDateTextCodec.standardKey)
    let happenedAt: Date
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


/// A literal whose placeholder binds `NULL`, so no storage class can be
/// derived for it.
struct DeclaredManifestNullDefault: XLCustomType, XLComparable, Hashable {
    typealias T = Self

    let value: String?

    init(value: String?) {
        self.value = value
    }

    init(reader: XLFieldReader) throws {
        value = try reader.isNull() ? nil : reader.readText()
    }

    func bind(context: inout XLBindingContext) {
        if let value {
            context.bindText(value: value)
        }
        else {
            context.bindNull()
        }
    }

    func makeSQL(context: inout XLBuilder) {
        context.text(value ?? "")
    }

    static func sqlDefault() -> DeclaredManifestNullDefault {
        DeclaredManifestNullDefault(value: nil)
    }
}


@SQLResult
struct DeclaredManifestNullRow: Equatable {
    let value: DeclaredManifestNullDefault
}


let declaredManifestCoding: XLValueCodingConfiguration = {
    try! XLValueCodingConfiguration(
        registry: XLValueCodecRegistry().registering(XLDateTextCodec.standard)
    )
}()


func declaredManifestEventLayout(
    id: any XLExpression<String>,
    happenedAt: any XLExpression<Date>
) -> XLStaticRowLayout<DeclaredManifestEvent, XLSQLiteDialect> {
    try! DeclaredManifestEvent.staticRowLayout(
        using: XLSQLiteDialect.self,
        id: XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: id,
            identifiedBy: XLQuerySlotIdentity(path: ["event", "id"])
        ),
        happenedAt: DeclaredManifestEvent.staticResultField(
            happenedAt: happenedAt,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["event", "happened-at"]),
            using: XLSQLiteDialect(),
            configuration: declaredManifestCoding
        )
    )
}


// MARK: - Declarations

extension GRDBDatabase {

    /// Read by declarations below, to prove a body may use the database
    /// instance.
    var declaredManifestRatingFloor: Int {
        3
    }
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

        func declaredAuthorsRated(rating: Int?) -> [DeclaredManifestAuthor] {
            sqlResult { schema in
                let author = schema.table(DeclaredManifestAuthor.self)
                Select(author)
                From(author)
                Where(author.rating == rating)
            }
        }

        func declaredBooks(genre: DeclaredManifestGenre, code: DeclaredManifestCode) -> [DeclaredManifestBook] {
            sqlResult { schema in
                let book = schema.table(DeclaredManifestBook.self)
                Select(book)
                From(book)
                Where(book.genre == genre && book.code == code)
            }
        }

        func declaredOnlyAuthor(id: String) -> DeclaredManifestAuthor {
            sqlResult { schema in
                let author = schema.table(DeclaredManifestAuthor.self)
                Select(author)
                From(author)
                Where(author.id == id)
            }
        }
    }
}


extension GRDBDatabase {

    /// Reads an instance property of the database in its body.
    @SQLQuery
    func declaredHighlyRated() -> [DeclaredManifestAuthor] {
        sqlResult { schema in
            let author = schema.table(DeclaredManifestAuthor.self)
            Select(author)
            From(author)
            Where(author.rating >= self.declaredManifestRatingFloor)
        }
    }

    /// Selects through a static row layout with a codec-selected field.
    @SQLQuery
    func declaredEvents(id: String) -> [DeclaredManifestEvent] {
        sqlResult { schema in
            let event = schema.table(DeclaredManifestEvent.self)
            Select(declaredManifestEventLayout(id: event.id, happenedAt: event.happenedAt))
            From(event)
            Where(event.id == id)
        }
    }

    /// Declared against a table the snapshot lacks.
    @SQLQuery
    func declaredMissingRows() -> [DeclaredManifestMissing] {
        sqlResult { schema in
            let missing = schema.table(DeclaredManifestMissing.self)
            Select(missing)
            From(missing)
        }
    }
}


/// A value-type database, so a declaration on it can be `mutating`.
struct DeclaredMutatingDatabase: XLDatabase {

    let base: GRDBDatabase

    func makeRequest<Row: Sendable>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row> {
        base.makeRequest(with: statement)
    }

    func makeRequest(with statement: any XLUpdateStatement) -> any XLWriteRequest {
        base.makeRequest(with: statement)
    }

    func makeRequest(with statement: any XLInsertStatement) -> any XLWriteRequest {
        base.makeRequest(with: statement)
    }

    func makeRequest(with statement: any XLCreateStatement) -> any XLWriteRequest {
        base.makeRequest(with: statement)
    }

    func makeRequest(with statement: any XLDeleteStatement) -> any XLWriteRequest {
        base.makeRequest(with: statement)
    }
}


extension DeclaredMutatingDatabase {

    @SQLQuery
    mutating func declaredMutatingAuthors() -> [DeclaredManifestAuthor] {
        sqlResult { schema in
            let author = schema.table(DeclaredManifestAuthor.self)
            Select(author)
            From(author)
        }
    }
}


enum DeclaredOuterA {
    enum Database {}
}


enum DeclaredOuterB {
    enum Database {}
}


private enum DeclaredPrivateScope {
    enum Database {}
}


/// Records the SQL of every statement SQLite runs.
final class DeclaredManifestSQLTrace: @unchecked Sendable {

    private let lock = NSLock()

    private var recorded: [String] = []

    func append(_ sql: String) {
        lock.lock()
        recorded.append(sql)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        recorded.removeAll()
        lock.unlock()
    }

    var statements: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}


// MARK: - Tests

final class DeclaredQueryManifestTests: XCTestCase {

    private var directory: URL!

    private var pools: [DatabasePool] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeclaredQueryManifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for pool in pools {
            try? pool.close()
        }
        pools = []
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
    }

    private static func tableSQL(includingEvents: Bool) throws -> [String] {
        let encoder = XLiteEncoder(dialect: XLSQLiteDialect())
        var statements = [
            try encoder.makeValidatedSQL(sqlCreate(DeclaredManifestAuthor.self)).sql,
            try encoder.makeValidatedSQL(sqlCreate(DeclaredManifestBook.self)).sql,
        ]
        if includingEvents {
            statements.append("CREATE TABLE DeclaredManifestEvent (id TEXT NOT NULL, happenedAt TEXT NOT NULL)")
        }
        return statements
    }

    private func makeDatabase(
        formatter: XLiteFormatter = XLiteFormatter(),
        trace: DeclaredManifestSQLTrace? = nil
    ) throws -> GRDBDatabase {
        var configuration = Configuration()
        if let trace {
            configuration.prepareDatabase { database in
                database.trace { event in
                    if case .statement(let statement) = event {
                        trace.append(statement.sql)
                    }
                }
            }
        }
        let pool = try DatabasePool(
            path: directory.appendingPathComponent("\(UUID().uuidString).sqlite").path,
            configuration: configuration
        )
        pools.append(pool)
        let statements = try Self.tableSQL(includingEvents: true)
        try pool.write { database in
            for statement in statements {
                try database.execute(sql: statement)
            }
        }
        return try GRDBDatabase(
            databasePool: pool,
            codingConfiguration: declaredManifestCoding,
            formatter: formatter,
            logger: nil
        )
    }

    /// Writes a rollback-journal snapshot holding the author and book tables.
    private func makeSnapshot() throws -> URL {
        let url = directory.appendingPathComponent("snapshot.sqlite")
        let statements = try Self.tableSQL(includingEvents: false)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { database in
            for statement in statements {
                try database.execute(sql: statement)
            }
        }
        try queue.close()
        return url
    }

    private func declared(_ name: String, in database: GRDBDatabase) throws -> XLDeclaredQuery {
        try XCTUnwrap(database.declaredQueries.first { $0.name == name }, name)
    }

    // MARK: Discovery

    func testTheGeneratedRegistryFindsEveryDeclarationInThisTarget() throws {
        let database = try makeDatabase()
        let mutatingDatabase = DeclaredMutatingDatabase(base: database)

        let queries = try Registry.queries(for: [database, mutatingDatabase])

        XCTAssertEqual(Set(Registry.databaseTypeNames), ["GRDBDatabase", "DeclaredMutatingDatabase"])
        XCTAssertEqual(Set(queries.map(\.id)), [
            "GRDBDatabase.declaredAuthors",
            "GRDBDatabase.declaredAuthor",
            "GRDBDatabase.declaredTitles",
            "GRDBDatabase.declaredAuthorsRated",
            "GRDBDatabase.declaredBooks",
            "GRDBDatabase.declaredOnlyAuthor",
            "GRDBDatabase.declaredHighlyRated",
            "GRDBDatabase.declaredEvents",
            "GRDBDatabase.declaredMissingRows",
            "DeclaredMutatingDatabase.declaredMutatingAuthors",
        ])
        XCTAssertEqual(queries.count, 10)
    }

    func testTheRegistryRefusesToLeaveADatabaseTypeOut() throws {
        let database = try makeDatabase()

        XCTAssertThrowsError(try Registry.queries(for: [database])) { error in
            XCTAssertEqual(
                error as? XLDeclaredQueryError,
                .missingDatabaseInstance(typeName: "DeclaredMutatingDatabase")
            )
        }
    }

    func testTheContainerListsEverySpecificationInDeclarationOrder() throws {
        let database = try makeDatabase()

        XCTAssertEqual(database.declaredQueries.map(\.name), [
            "declaredAuthors",
            "declaredAuthor",
            "declaredTitles",
            "declaredAuthorsRated",
            "declaredBooks",
            "declaredOnlyAuthor",
        ])
        XCTAssertEqual(
            database.declaredQueries.map(\.cardinality),
            [.many, .zeroOrOne, .many, .many, .many, .exactlyOne]
        )
    }

    func testAMutatingDeclarationIsDescribed() throws {
        var mutatingDatabase = DeclaredMutatingDatabase(base: try makeDatabase())

        let query = mutatingDatabase.declaredMutatingAuthorsDeclaredQuery()

        XCTAssertEqual(query.id, "DeclaredMutatingDatabase.declaredMutatingAuthors")
        // Only a GRDBDatabase exposes its encoder, so this one cannot render.
        XCTAssertThrowsError(try query.makeDescriptor()) { error in
            XCTAssertEqual(
                error as? XLDeclaredQueryError,
                .encoderUnavailable(
                    query: "DeclaredMutatingDatabase.declaredMutatingAuthors",
                    databaseType: "DeclaredMutatingDatabase"
                )
            )
        }
    }

    func testTypeNamesKeepTheirEnclosingTypes() {
        func query<Database>(on type: Database.Type) -> XLDeclaredQuery {
            XLDeclaredQuery(
                databaseType: type,
                encoder: XLiteEncoder(dialect: XLSQLiteDialect()),
                name: "rows",
                cardinality: .many,
                parameters: [],
                rowType: DeclaredManifestAuthor.self,
                statement: {
                    sql { schema in
                        let author = schema.table(DeclaredManifestAuthor.self)
                        Select(author)
                        From(author)
                    }
                }
            )
        }

        XCTAssertEqual(query(on: DeclaredOuterA.Database.self).id, "DeclaredOuterA.Database.rows")
        XCTAssertEqual(query(on: DeclaredOuterB.Database.self).id, "DeclaredOuterB.Database.rows")
        XCTAssertEqual(query(on: DeclaredPrivateScope.Database.self).id, "DeclaredPrivateScope.Database.rows")
        XCTAssertEqual(query(on: GRDBDatabase.self).id, "GRDBDatabase.rows")
    }

    // MARK: Descriptor

    /// Each case runs the generated executor on a database that records
    /// every statement SQLite prepares, then checks that the lowered
    /// descriptor carries one of those statements exactly. The database uses
    /// a non-default formatter, so the SQL is the database's own, not the
    /// default dialect's.
    func testEveryShapeRendersTheSQLItsExecutorRuns() throws {
        let trace = DeclaredManifestSQLTrace()
        let database = try makeDatabase(
            formatter: XLiteFormatter(identifierFormattingOptions: .mysqlCompatible),
            trace: trace
        )

        let cases: [(label: String, run: () throws -> Void, query: () throws -> XLDeclaredQuery)] = [
            (
                "container, array result",
                { _ = try database.declaredAuthors() },
                { try self.declared("declaredAuthors", in: database) }
            ),
            (
                "container, optional row and string parameter",
                { _ = try database.declaredAuthor(id: "a") },
                { try self.declared("declaredAuthor", in: database) }
            ),
            (
                "container, composite result over a join",
                { _ = try database.declaredTitles(authorID: "a", minimumRating: 1) },
                { try self.declared("declaredTitles", in: database) }
            ),
            (
                "container, optional parameter",
                { _ = try database.declaredAuthorsRated(rating: nil) },
                { try self.declared("declaredAuthorsRated", in: database) }
            ),
            (
                "container, enum and custom-literal parameters and results",
                { _ = try database.declaredBooks(genre: .poetry, code: DeclaredManifestCode("x")) },
                { try self.declared("declaredBooks", in: database) }
            ),
            (
                "container, exactly one row",
                // The table is empty, so the executor throws after SQLite
                // ran the statement.
                { _ = try? database.declaredOnlyAuthor(id: "a") },
                { try self.declared("declaredOnlyAuthor", in: database) }
            ),
            (
                "peer, body reads the database instance",
                { _ = try database.fetchDeclaredHighlyRated() },
                { database.declaredHighlyRatedDeclaredQuery() }
            ),
            (
                "peer, static row layout with a codec",
                { _ = try database.fetchDeclaredEvents(id: "e") },
                { database.declaredEventsDeclaredQuery() }
            ),
        ]

        for testCase in cases {
            // Cleared per case, so a match cannot come from an earlier case.
            trace.clear()
            try testCase.run()
            let sql = try testCase.query().makeDescriptor().descriptor.sql
            XCTAssertTrue(
                trace.statements.contains(sql),
                "\(testCase.label): \(sql) is not among \(trace.statements)"
            )
        }

        let defaultDatabase = try makeDatabase()
        XCTAssertNotEqual(
            try declared("declaredAuthors", in: database).makeDescriptor().descriptor.sql,
            try declared("declaredAuthors", in: defaultDatabase).makeDescriptor().descriptor.sql,
            "the formatter must change the rendered SQL, or the test above proves nothing about it"
        )
    }

    func testADescriptorCarriesTheRenderedParametersAndResults() throws {
        let database = try makeDatabase()

        let author = try declared("declaredAuthor", in: database).makeDescriptor()
        XCTAssertEqual(author.descriptor.definitionIdentity.description, "GRDBDatabase/declaredAuthor@1")
        XCTAssertEqual(author.descriptor.parameters.map(\.identity.description), ["parameter/id"])
        XCTAssertEqual(author.descriptor.parameters.map(\.storageIdentifier.rawValue), ["text"])
        XCTAssertEqual(author.resultAliases, ["id", "name", "rating"])
        XCTAssertEqual(author.descriptor.results.slots.map(\.nullability), [.required, .required, .nullable])
        XCTAssertEqual(author.descriptor.results.slots.map(\.storageIdentifier.rawValue), ["text", "text", "integer"])

        let rated = try declared("declaredAuthorsRated", in: database).makeDescriptor()
        XCTAssertEqual(rated.descriptor.parameters.map(\.slot.nullability), [.nullable])
        XCTAssertEqual(rated.descriptor.parameters.map(\.storageIdentifier.rawValue), ["integer"])

        let books = try declared("declaredBooks", in: database).makeDescriptor()
        XCTAssertEqual(books.descriptor.parameters.map(\.slot.key), [.named("genre"), .named("code")])
        XCTAssertEqual(books.descriptor.parameters.map(\.storageIdentifier.rawValue), ["integer", "text"])
        XCTAssertEqual(
            books.descriptor.results.slots.suffix(2).map(\.storageIdentifier.rawValue),
            ["integer", "text"]
        )

        let titles = try declared("declaredTitles", in: database).makeDescriptor()
        XCTAssertEqual(titles.resultAliases, ["authorName", "title"])
    }

    func testAStaticRowLayoutKeepsItsCodecs() throws {
        let database = try makeDatabase()

        let events = try database.declaredEventsDeclaredQuery().makeDescriptor()

        XCTAssertEqual(events.resultAliases, ["id", "happenedAt"])
        XCTAssertEqual(
            events.descriptor.results.slots.map(\.codecIdentity?.key),
            [nil, XLDateTextCodec.standardKey]
        )
        XCTAssertEqual(events.descriptor.parameters.map(\.identity.description), ["parameter/id"])
    }

    /// The identity is derived only from the declaration and the SQL it
    /// renders, so it is the same in every build. The digest pins it: a
    /// change to it is a change to every manifest generated from this
    /// declaration. The identity spells its complete canonical bytes, so the
    /// test pins their SHA-256 rather than a literal hundreds of characters
    /// long.
    func testTheDescriptorIdentityIsStableAcrossBuilds() throws {
        let database = try makeDatabase()
        let query = try declared("declaredAuthor", in: database)
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

    // MARK: Manifest

    private func validQueries(on database: GRDBDatabase) -> [XLDeclaredQuery] {
        database.declaredQueries + [database.declaredHighlyRatedDeclaredQuery()]
    }

    func testAnEmittedManifestValidatesAgainstARealSnapshot() throws {
        let database = try makeDatabase()
        let snapshotURL = try makeSnapshot()

        let generated = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: validQueries(on: database),
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )
        let manifest = generated.manifest

        XCTAssertEqual(generated.skippedQueries, [])
        XCTAssertEqual(manifest.formatVersion, .v2)
        XCTAssertNil(manifest.conformanceInventoryVersion)
        XCTAssertNil(manifest.combinatorialManifestVersion)
        XCTAssertEqual(manifest.queries.count, 7)

        let report = try SQLiteBuildValidator.validate(
            manifest: manifest,
            againstDatabaseAt: snapshotURL
        )
        XCTAssertEqual(report.overallVerdict, .passed, "\(report.diagnostics)")
        XCTAssertEqual(
            Set(report.outcomes.map(\.queryID)),
            Set(validQueries(on: database).map(\.id))
        )
    }

    func testABrokenDeclarationFailsWithTheValidatorsOwnDiagnostic() throws {
        let database = try makeDatabase()
        let snapshotURL = try makeSnapshot()

        let generated = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: validQueries(on: database) + [database.declaredMissingRowsDeclaredQuery()],
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )
        let report = try SQLiteBuildValidator.validate(
            manifest: generated.manifest,
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
        let database = try makeDatabase()
        let snapshotURL = try makeSnapshot()

        let first = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: validQueries(on: database),
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )
        let second = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: validQueries(on: try makeDatabase()),
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )

        XCTAssertEqual(try first.manifest.canonicalJSONData(), try second.manifest.canonicalJSONData())
    }

    func testATargetWithNoDeclaredQueriesProducesAValidManifest() throws {
        let snapshotURL = try makeSnapshot()

        let generated = try SQLiteBuildValidationDeclaredQueryManifest.makeManifest(
            queries: [],
            snapshotIdentifier: "declared-query-test.schema",
            snapshotURL: snapshotURL
        )

        XCTAssertEqual(generated.manifest.queries, [])
        let report = try SQLiteBuildValidator.validate(
            manifest: generated.manifest,
            againstDatabaseAt: snapshotURL
        )
        XCTAssertEqual(report.overallVerdict, .passed, "\(report.diagnostics)")
    }

    func testAQueryWhoseRowsCannotBeDescribedIsSkippedByName() throws {
        let database = try makeDatabase()
        let unlowerable = XLDeclaredQuery(
            database: database,
            name: "nullPlaceholder",
            cardinality: .many,
            parameters: [],
            rowType: DeclaredManifestNullRow.self,
            statement: {
                sql { schema in
                    let author = schema.table(DeclaredManifestAuthor.self)
                    Select(DeclaredManifestNullRow.columns(value: DeclaredManifestNullDefault(value: "x")))
                    From(author)
                }
            }
        )

        let projection = try SQLiteBuildValidationDeclaredQueryManifest.queryEntries(
            for: [try declared("declaredAuthors", in: database), unlowerable]
        )

        XCTAssertEqual(projection.entries.map(\.id), ["GRDBDatabase.declaredAuthors"])
        XCTAssertEqual(projection.skippedQueries.map(\.queryID), ["GRDBDatabase.nullPlaceholder"])
        XCTAssertTrue(projection.skippedQueries[0].reason.contains("sqlDefault()"), projection.skippedQueries[0].reason)
    }
}
