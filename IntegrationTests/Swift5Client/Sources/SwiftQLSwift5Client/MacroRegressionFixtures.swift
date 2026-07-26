import Foundation
import SwiftQL

// A downstream, non-`@testable` regression corpus for issue #256: awkward
// `@SQLTable`/`@SQLResult` declarations that must import, compile, and
// execute against real SQLite from a separate SwiftPM package -- not only
// expand cleanly inside the SQLMacros test target. Every case referenced
// here is recorded, with its provenance and disposition, in
// `Tests/SQLMacrosTests/MacroRegressionCorpus.json`.
//
// This file only ever uses SwiftQL's public API (`import SwiftQL`, never
// `@testable`), matching the hard constraint that same-target visibility
// cannot stand in for proof that generated members are actually usable by a
// real client.

enum MacroRegressionFixtureError: Error {
    case unexpectedOddlyNamedRow(OddlyNamedRow?)
    case unexpectedRichlyTypedRows([RichlyTypedRow])
    case unexpectedWideRow(WideDownstreamRow?)
    case unexpectedCompositeRows([DownstreamEmployeeCompany])
}

// MARK: - Reserved, escaped, Unicode, and SQL-keyword-like identifiers
//
// `class` is a Swift reserved keyword (escaped with backticks); `order` and
// `select` are unreserved in Swift but reserved in SQL; `café` and `名前`
// are non-ASCII Unicode identifiers. Every SQL identifier SwiftQL renders is
// always double-quoted, so none of these are actually ambiguous at the SQL
// level, but the *Swift* code the macro generates (initializer, `columns`,
// table metadata) must still compile and round-trip correctly for each
// shape.

@SQLTable(name: "OddlyNamedRow")
struct OddlyNamedRow: Equatable {
    let id: Int
    let `class`: String
    let order: Int
    let café: String
    let 名前: String
}

private func validateOddlyNamedIdentifiers(
    database: GRDBDatabase
) throws {
    try database.makeRequest(with: sqlCreate(OddlyNamedRow.self)).execute()
    try database.makeRequest(
        with: sqlInsert(
            OddlyNamedRow(
                id: 1,
                class: "Physics",
                order: 3,
                café: "Blue Bottle",
                名前: "SwiftQL"
            )
        )
    ).execute()

    let statement = sql { schema in
        let row = schema.table(OddlyNamedRow.self)
        Select(row)
        From(row)
    }
    let result = try database.makeRequest(with: statement).fetchOne()
    guard result == OddlyNamedRow(
        id: 1,
        class: "Physics",
        order: 3,
        café: "Blue Bottle",
        名前: "SwiftQL"
    ) else {
        throw MacroRegressionFixtureError.unexpectedOddlyNamedRow(result)
    }
}

// MARK: - BLOBs, optionals, and enum-backed columns

enum RichPriority: Int, XLEnum {
    typealias T = Self

    case low = 0
    case high = 1

    static func sqlDefault() -> RichPriority { .low }
}

enum RichStatus: String, XLEnum {
    typealias T = Self

    case queued
    case done

    static func sqlDefault() -> RichStatus { .queued }
}

@SQLTable(name: "RichlyTypedRow")
struct RichlyTypedRow: Equatable {
    let id: Int
    let payload: Data
    let priority: RichPriority
    let status: RichStatus?
    let note: String?
}

private func validateBlobOptionalAndEnumColumns(
    database: GRDBDatabase
) throws {
    try database.makeRequest(with: sqlCreate(RichlyTypedRow.self)).execute()
    try database.makeRequest(
        with: sqlInsert(
            RichlyTypedRow(
                id: 1,
                payload: Data([0x00, 0x01, 0xFF]),
                priority: .high,
                status: .done,
                note: "first"
            )
        )
    ).execute()
    try database.makeRequest(
        with: sqlInsert(
            RichlyTypedRow(
                id: 2,
                payload: Data(),
                priority: .low,
                status: nil,
                note: nil
            )
        )
    ).execute()

    let idParameter = XLNamedBindingReference<Int>(name: "id")
    let statement = sql { schema in
        let row = schema.table(RichlyTypedRow.self)
        Select(row)
        From(row)
        Where(row.id >= idParameter)
        OrderBy(row.id.ascending())
    }
    var request = database.makeRequest(with: statement)
    request.set(idParameter, 1)
    let rows = try request.fetchAll()

    guard rows == [
        RichlyTypedRow(
            id: 1,
            payload: Data([0x00, 0x01, 0xFF]),
            priority: .high,
            status: .done,
            note: "first"
        ),
        RichlyTypedRow(
            id: 2,
            payload: Data(),
            priority: .low,
            status: nil,
            note: nil
        ),
    ] else {
        throw MacroRegressionFixtureError.unexpectedRichlyTypedRows(rows)
    }
}

// MARK: - Many stored properties (a wide row)
//
// A denormalized row with more columns than any single-purpose fixture
// nearby, so a running-offset or generated-identifier regression that only
// shows up once several properties accumulate would be caught here rather
// than only in a synthetic expansion test.

@SQLTable(name: "WideDownstreamRow")
struct WideDownstreamRow: Equatable {
    let id: Int
    let field0: Int
    let field1: Int
    let field2: Int
    let field3: String
    let field4: String
    let field5: String
    let field6: Double
    let field7: Double
    let field8: Bool
    let field9: Bool
}

private func validateManyStoredProperties(
    database: GRDBDatabase
) throws {
    try database.makeRequest(with: sqlCreate(WideDownstreamRow.self)).execute()
    let inserted = WideDownstreamRow(
        id: 1,
        field0: 10, field1: 11, field2: 12,
        field3: "a", field4: "b", field5: "c",
        field6: 1.5, field7: 2.5,
        field8: true, field9: false
    )
    try database.makeRequest(with: sqlInsert(inserted)).execute()

    let statement = sql { schema in
        let row = schema.table(WideDownstreamRow.self)
        Select(row)
        From(row)
    }
    let result = try database.makeRequest(with: statement).fetchOne()
    guard result == inserted else {
        throw MacroRegressionFixtureError.unexpectedWideRow(result)
    }
}

// MARK: - Composite (nested `@SQLTable`) result selection, issue #6 / PR #382
//
// Proves the composite/nested selection feature this regression corpus was
// commissioned to cover (issue #256's coordinating branch) is usable from a
// real downstream package through SwiftQL's public static-row-layout API,
// not only inside the SQLMacros test target. This mirrors
// `StaticRowLayoutGRDBTests.testGeneratedCompositeLayoutFlattensNestedTablesAndReconstructsSubObjects`,
// which proves the same generated code with `@testable import SwiftQL`; this
// downstream copy proves it compiles and runs without that access.

@SQLTable(name: "DownstreamEmployee")
struct DownstreamEmployee: Equatable {
    let id: Int
    let name: String
    let companyId: Int
}

@SQLTable(name: "DownstreamCompany")
struct DownstreamCompany: Equatable {
    let id: Int
    let title: String
}

@SQLResult
struct DownstreamEmployeeCompany: Equatable {
    let employee: DownstreamEmployee
    let company: DownstreamCompany
}

private func validateCompositeResultSelection(
    database: GRDBDatabase
) throws {
    try database.makeRequest(with: sqlCreate(DownstreamCompany.self)).execute()
    try database.makeRequest(with: sqlCreate(DownstreamEmployee.self)).execute()
    try database.makeRequest(
        with: sqlInsert(DownstreamCompany(id: 1, title: "Acme"))
    ).execute()
    try database.makeRequest(
        with: sqlInsert(DownstreamEmployee(id: 10, name: "Ada", companyId: 1))
    ).execute()

    let schema = XLSchema()
    let employeeTable = schema.table(DownstreamEmployee.self, as: "employee")
    let companyTable = schema.table(DownstreamCompany.self, as: "company")

    let employeeLayout = try DownstreamEmployee.staticRowLayout(
        using: XLSQLiteDialect.self,
        id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
            selecting: employeeTable.id,
            identifiedBy: XLQuerySlotIdentity(
                path: ["downstream", "composite", "employee", "id"]
            )
        ),
        name: XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: employeeTable.name,
            identifiedBy: XLQuerySlotIdentity(
                path: ["downstream", "composite", "employee", "name"]
            )
        ),
        companyId: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
            selecting: employeeTable.companyId,
            identifiedBy: XLQuerySlotIdentity(
                path: ["downstream", "composite", "employee", "companyId"]
            )
        )
    )
    let companyLayout = try DownstreamCompany.staticRowLayout(
        using: XLSQLiteDialect.self,
        id: XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
            selecting: companyTable.id,
            identifiedBy: XLQuerySlotIdentity(
                path: ["downstream", "composite", "company", "id"]
            )
        ),
        title: XLStaticSelectField<String, String, XLSQLiteDialect>.intrinsic(
            selecting: companyTable.title,
            identifiedBy: XLQuerySlotIdentity(
                path: ["downstream", "composite", "company", "title"]
            )
        )
    )
    let combinedLayout = try DownstreamEmployeeCompany.staticRowLayout(
        using: XLSQLiteDialect.self,
        employee: employeeLayout,
        company: companyLayout
    )

    let statement = sql { _ in
        Select(combinedLayout)
        From(employeeTable)
        Join(companyTable, on: employeeTable.companyId == companyTable.id)
    }
    let encoding = try XLiteEncoder(dialect: database.dialect)
        .makeValidatedSQL(statement)
    let descriptor = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["downstream", "composite-employee-company"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(validating: encoding),
        parameters: [],
        results: combinedLayout.metadata.results,
        cardinality: .many
    )
    let prepared = try database.prepareInvocation(
        with: XLTypedStaticQueryDescriptor(
            descriptor: descriptor,
            layout: combinedLayout
        )
    )
    let rows = try prepared.fetchAll(bindings: prepared.makeInvocationBindings())

    guard rows == [
        DownstreamEmployeeCompany(
            employee: DownstreamEmployee(id: 10, name: "Ada", companyId: 1),
            company: DownstreamCompany(id: 1, title: "Acme")
        )
    ] else {
        throw MacroRegressionFixtureError.unexpectedCompositeRows(rows)
    }
}

// MARK: - Entry point

func runMacroRegressionFixtures(database: GRDBDatabase) throws {
    try validateOddlyNamedIdentifiers(database: database)
    try validateBlobOptionalAndEnumColumns(database: database)
    try validateManyStoredProperties(database: database)
    try validateCompositeResultSelection(database: database)
}
