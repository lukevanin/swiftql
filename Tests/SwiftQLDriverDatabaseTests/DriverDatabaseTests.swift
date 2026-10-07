//
//  DriverDatabaseTests.swift
//  SwiftQLDriverDatabaseTests
//
//  Issue #682: a driver with no GRDB import backs a full request, write,
//  result set, and static query through `XLDriverDatabase`. This target
//  depends on SwiftQL alone, and `scripts/ci/check-core-contract-boundary.py`
//  rejects a GRDB, CSQLite, or Combine import in it.
//

import Foundation
@testable import SwiftQL
import XCTest


@SQLTable(name: "Person")
struct DriverPerson: Equatable {
    let id: String
    let age: Int
}


final class DriverDatabaseTests: XCTestCase {

    private var driver: ScriptedDriver!

    private var database: XLDriverDatabase<ScriptedDriver>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        driver = ScriptedDriver()
        database = try XLDriverDatabase(driver: driver)
    }

    override func tearDown() {
        database = nil
        driver = nil
        super.tearDown()
    }

    // MARK: - Requests

    func testRequestFetchesAndDecodesRowsThroughTheDriver() throws {
        let minimumAge = XLNamedBindingReference<Int>(name: "minimumAge")
        var request = database.makeRequest(with: sql { schema in
            let person = schema.table(DriverPerson.self)
            Select(person)
            From(person)
            Where(person.age >= minimumAge)
        })
        request.set(minimumAge, 21)
        driver.store.rows = [
            [.text("alice"), .integer(30)],
            [.text("bob"), .integer(42)],
        ]

        let people = try request.fetchAll()

        XCTAssertEqual(people, [
            DriverPerson(id: "alice", age: 30),
            DriverPerson(id: "bob", age: 42),
        ])
        let execution = try XCTUnwrap(driver.store.executions.last)
        XCTAssertTrue(execution.sql.hasPrefix("SELECT"), execution.sql)
        XCTAssertEqual(Array(execution.bindings.values), [.integer(21)])
        XCTAssertEqual(driver.store.scopes, ["blocking read"])
    }

    func testFetchOneReturnsTheFirstRow() throws {
        let request = database.makeRequest(with: selectPeople())
        driver.store.rows = [[.text("carol"), .integer(19)], [.text("dave"), .integer(50)]]

        XCTAssertEqual(try request.fetchOne(), DriverPerson(id: "carol", age: 19))
    }

    func testAsyncFetchRunsOnTheAsynchronousScope() async throws {
        let request = database.makeRequest(with: selectPeople())
        driver.store.rows = [[.text("erin"), .integer(28)]]

        let people = try await request.async.fetchAll()

        XCTAssertEqual(people, [DriverPerson(id: "erin", age: 28)])
        XCTAssertEqual(driver.store.scopes, ["read"])
    }

    // MARK: - Writes

    func testWriteRequestExecutesInATransactionWithItsBindings() throws {
        let result = try database
            .makeRequest(with: sqlInsert(DriverPerson(id: "frank", age: 61)))
            .execute()

        XCTAssertEqual(result.rowsAffected, 1)
        let execution = try XCTUnwrap(driver.store.executions.last)
        XCTAssertTrue(execution.sql.hasPrefix("INSERT INTO"), execution.sql)
        XCTAssertFalse(execution.returnsRows)
        // `sqlInsert(_:)` renders a model's values into the SQL as literals.
        XCTAssertTrue(execution.sql.contains("'frank'"), execution.sql)
        XCTAssertTrue(execution.sql.contains("61"), execution.sql)
        XCTAssertEqual(driver.store.scopes, ["blocking transaction"])
    }

    // MARK: - Result sets

    /// The scripted connection overrides neither `forEachRow(_:_:)` nor
    /// `withValuesStepper(_:_:)`, so this runs on the contract's eager
    /// defaults.
    func testResultSetStepsRowsOneAtATime() throws {
        let request = database.makeRequest(with: selectPeople())
        driver.store.rows = [[.text("gina"), .integer(33)], [.text("hal"), .integer(44)]]

        let seen = try request.withResultSet { rows -> [DriverPerson] in
            var seen: [DriverPerson] = []
            while let row = try rows.next() {
                seen.append(row)
            }
            XCTAssertNil(try rows.next(), "An exhausted result set stays exhausted.")
            return seen
        }

        XCTAssertEqual(seen, [DriverPerson(id: "gina", age: 33), DriverPerson(id: "hal", age: 44)])
    }

    // MARK: - Static queries

    func testStaticQueryFetchesValuesThroughTheDriver() throws {
        let encoding = try XLiteEncoder(dialect: driver.dialect).makeValidatedSQL(
            sql { schema in
                let person = schema.table(DriverPerson.self)
                Select(person.id)
                From(person)
            }
        )
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(path: ["tests", "driver", "ids"], version: 1),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: try XLStaticQueryResultMetadata(
                slots: [
                    XLStaticQueryResultSlot(
                        index: XLLogicalResultIndex(0),
                        identity: try XLQuerySlotIdentity(path: ["result", "id"]),
                        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.string"),
                        valueTypeName: String(reflecting: String.self),
                        nullability: .required,
                        codecIdentity: nil,
                        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
                        codingContext: XLValueCodingContext(
                            site: .result,
                            path: XLValueCodingPath(["id"])
                        )
                    ),
                ]
            ),
            cardinality: .many
        )
        let query = try database.prepareInvocation(with: descriptor)
        driver.store.rows = [[.text("ivy")], [.text("jon")]]

        let rows = try query.fetchAllValues(
            bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty)
        )

        XCTAssertEqual(rows, [[.text("ivy")], [.text("jon")]])
        XCTAssertEqual(driver.store.executions.last?.sql, descriptor.statement.sql)
    }

    func testPreparedInvocationFetchesRawValues() throws {
        let invocation = database.prepareInvocation(with: selectPeople())
        driver.store.rows = [[.text("kim"), .integer(37)]]

        XCTAssertEqual(
            try invocation.fetchOneValues(bindings: XLInvocationBindings<XLSQLiteValue>(layout: .empty)),
            [.text("kim"), .integer(37)]
        )
    }

    // MARK: - Live queries

    func testStreamFetchesAgainAfterAWriteToAnEntityItReads() async throws {
        driver.store.rows = [[.text("lee"), .integer(20)]]
        var iterator = database.makeRequest(with: selectPeople()).stream().makeAsyncIterator()

        let initial = try await iterator.next()
        XCTAssertEqual(initial, [DriverPerson(id: "lee", age: 20)])

        driver.store.rows = [[.text("lee"), .integer(20)], [.text("mo"), .integer(25)]]
        try database.makeRequest(with: sqlInsert(DriverPerson(id: "mo", age: 25))).execute()

        let refreshed = try await iterator.next()
        XCTAssertEqual(refreshed, [DriverPerson(id: "lee", age: 20), DriverPerson(id: "mo", age: 25)])
    }

    /// A decode failure ends the stream and releases the observation, so the
    /// driver stops notifying it (issue #682).
    func testDecodeFailureEndsTheStreamAndStopsTheObservation() async throws {
        driver.store.rows = [[.text("olga"), .integer(20)]]
        var iterator = database.makeRequest(with: selectPeople()).stream().makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial, [DriverPerson(id: "olga", age: 20)])
        XCTAssertEqual(driver.store.observerCount, 1, "A running stream is observing.")

        driver.store.rows = [[.null, .integer(20)]]
        try database.makeRequest(with: sqlInsert(DriverPerson(id: "pat", age: 22))).execute()
        do {
            _ = try await iterator.next()
            XCTFail("A row that cannot decode must fail the stream.")
        }
        catch {}

        XCTAssertEqual(driver.store.observerCount, 0, "The failure must release the observation.")
        let afterFailure = try await iterator.next()
        XCTAssertNil(afterFailure, "The stream ends after a decode failure.")
    }

    // MARK: - Publish preflight

    /// The synchronous publish preflight serves every driver, not only GRDB
    /// (issue #682): a `RETURNING` statement is refused before observing.
    func testPublishPreflightRefusesAReturningStatementOnAnyDriver() throws {
        let schema = XLSchema()
        let person = schema.table(DriverPerson.self)
        let request = database.makeRequest(
            with: insert(person)
                .values(DriverPerson.MetaInsert(DriverPerson(id: "nina", age: 40)))
                .returning(person)
        )

        let preflight = try XCTUnwrap(request as? any XLLivePublishPreflight)
        let failure = preflight.livePublishPreflightFailure(bindings: nil)

        XCTAssertEqual(failure as? XLReturningRequestError, .observationUnsupported)
        XCTAssertNil(
            (database.makeRequest(with: selectPeople()) as? any XLLivePublishPreflight)?
                .livePublishPreflightFailure(bindings: nil),
            "A plain query on an observing driver may be observed."
        )
    }

    // MARK: - Contextual bindings and captures

    /// A driver database resolves codec-backed parameters and static-query
    /// captures from its own coding snapshot, as ``GRDBDatabase`` does.
    func testContextualBindingAndQueryCaptureResolveAgainstTheDatabase() throws {
        let codecDatabase = XLDriverDatabase(
            driver: driver,
            codingConfiguration: try XLValueCodingConfiguration(
                registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
                defaultCodecKeys: [XLDateTextCodec.standardKey]
            )
        )

        let binding = try codecDatabase.contextualBinding(
            Date.self,
            expressedAs: String.self,
            named: "cutoff"
        )
        XCTAssertEqual(binding.declaration.key, .named("cutoff"))
        XCTAssertEqual(binding.declaration.nullability, .required)
        XCTAssertEqual(binding.declaration.codecIdentity?.key, XLDateTextCodec.standardKey)

        XCTAssertThrowsError(
            try codecDatabase.contextualBinding(
                Date.self,
                expressedAs: String.self,
                named: "cutoff",
                nullability: .nullable
            ),
            "A nullable parameter needs an optional expression type."
        )
        XCTAssertThrowsError(
            try database.contextualBinding(Date.self, expressedAs: String.self, named: "cutoff"),
            "A database without a Date codec cannot resolve the parameter."
        )

        let identity = try XLQuerySlotIdentity(path: ["person", "seen"])
        let capture = try codecDatabase.queryCapture(
            Date.self,
            expressedAs: String.self,
            identifiedBy: identity
        )
        XCTAssertEqual(capture.identity, identity)
    }

    /// Code that holds any value-coding database declares its bindings and
    /// captures without naming the driver (issue #113).
    func testValueCodingDatabaseResolvesCapturesWithoutNamingTheDriver() throws {
        func seenCapture(
            on database: some XLValueCodingDatabase<XLSQLiteDialect>
        ) throws -> XLQueryCapture<Date, String, XLSQLiteDialect> {
            try database.queryCapture(
                Date.self,
                expressedAs: String.self,
                identifiedBy: try XLQuerySlotIdentity(path: ["person", "seen"])
            )
        }
        let codecDatabase = XLDriverDatabase(
            driver: driver,
            codingConfiguration: try XLValueCodingConfiguration(
                registry: try XLValueCodecRegistry().registering(XLDateTextCodec.standard),
                defaultCodecKeys: [XLDateTextCodec.standardKey]
            )
        )

        let capture = try seenCapture(on: codecDatabase)

        XCTAssertEqual(capture.identity, try XLQuerySlotIdentity(path: ["person", "seen"]))
        XCTAssertThrowsError(
            try seenCapture(on: database!),
            "A database without a Date codec cannot resolve the capture."
        )
    }

    // MARK: - Declared queries

    /// A declared query read from a driver database still cannot borrow its
    /// encoder (issue #113): its identity would carry the generic driver
    /// argument. Issue #802 gives declared queries a driver-neutral host.
    func testDeclaredQueryOnADriverDatabaseHasNoEncoder() throws {
        let query = XLDeclaredQuery(
            database: database!,
            name: "people",
            cardinality: .many,
            parameters: [],
            rowType: DriverPerson.self,
            statement: { self.selectPeople() }
        )

        XCTAssertThrowsError(try query.makeDescriptor()) { error in
            guard case .encoderUnavailable(_, _)? = error as? XLDeclaredQueryError else {
                return XCTFail("Expected encoderUnavailable, got \(error)")
            }
        }
    }

    // MARK: - Render-once cache

    /// Each database renders its own cache entries, because a cached request
    /// captures the database's coding configuration and logger; copies of one
    /// database share them.
    func testRenderOnceCacheKeepsDatabasesOverOneDriverApart() throws {
        let other = try XLDriverDatabase(driver: driver)
        let copy = database!
        let cache = XLRenderOnceCache<DriverPerson>()
        var renders = 0
        let statement = { () -> any XLQueryStatement<DriverPerson> in
            renders += 1
            return self.selectPeople()
        }

        _ = cache.request(for: database, statement: statement)
        _ = cache.request(for: copy, statement: statement)
        XCTAssertEqual(renders, 1, "Copies of one database share an entry.")

        _ = cache.request(for: other, statement: statement)
        XCTAssertEqual(renders, 2, "A second database over the same driver renders its own entry.")
    }

    // MARK: - Helpers

    private func selectPeople() -> any XLQueryStatement<DriverPerson> {
        sql { schema in
            let person = schema.table(DriverPerson.self)
            Select(person)
            From(person)
        }
    }
}
