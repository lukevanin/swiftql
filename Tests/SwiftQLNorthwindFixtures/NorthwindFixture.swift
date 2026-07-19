import Foundation
import GRDB


public struct NorthwindFixtureMetadata: Equatable, Sendable {
    public let provenanceSchemaVersion: Int
    public let upstreamRepository: String
    public let upstreamCommit: String
    public let upstreamPath: String
    public let upstreamURL: String
    public let licenseSPDX: String
    public let upstreamLicensePath: String
    public let upstreamLicenseGitBlobSHA: String
    public let databaseResourcePath: String
    public let databaseSHA256: String
    public let licenseNoticePath: String
    public let licenseSHA256: String
    public let databaseByteCount: Int
    public let applicationTables: Set<String>
    public let views: Set<String>
    public let rowCounts: [String: Int]
    public let sentinelOrderID: Int
    public let sentinelOrderDetailCount: Int
    public let sentinelOrderSubtotal: Double
    public let canonicalAccessPolicy: String
    public let mutationAccessPolicy: String
    public let runtimeNetworkAccess: Bool
    public let performanceClaim: Bool
}


public struct NorthwindFixtureValidation: Equatable, Sendable {
    let databaseURL: URL
    public let databaseSHA256: String
    public let databaseByteCount: Int
    public let integrityCheck: [String]
    public let applicationTables: Set<String>
    public let views: Set<String>
    public let rowCounts: [String: Int]
    public let sentinelOrderID: Int
    public let sentinelOrderDetailCount: Int
    public let sentinelOrderSubtotal: Double
    public let sqliteVersion: String
    public let sqliteSourceID: String
}


public struct NorthwindTemporaryCopy {
    public let url: URL
    public let databasePool: DatabasePool
    public let initialValidation: NorthwindFixtureValidation
}


public enum NorthwindFixtureError: Error, Equatable, CustomStringConvertible {
    case missingResource(String)
    case checksumMismatch(resource: String, expected: String, actual: String)
    case integrityCheckMismatch(expected: [String], actual: [String])
    case schemaMismatch(kind: String, expected: [String], actual: [String])
    case rowCountMismatch(table: String, expected: Int, actual: Int?)
    case orderSentinelMismatch(
        orderID: Int,
        expectedDetailCount: Int,
        actualDetailCount: Int,
        expectedSubtotal: Double,
        actualSubtotal: Double
    )
    case missingOrderSentinelResult(orderID: Int)
    case missingSQLiteRuntimeMetadata

    public var description: String {
        switch self {
        case let .missingResource(name):
            return "Missing bundled Northwind fixture resource: \(name)"
        case let .checksumMismatch(resource, expected, actual):
            return "Northwind \(resource) SHA-256 mismatch: expected \(expected), got \(actual)"
        case let .integrityCheckMismatch(expected, actual):
            return "Northwind PRAGMA integrity_check mismatch: expected \(expected), got \(actual)"
        case let .schemaMismatch(kind, expected, actual):
            return "Northwind \(kind) mismatch: expected \(expected), got \(actual)"
        case let .rowCountMismatch(table, expected, actual):
            let actualDescription = actual.map(String.init) ?? "nil"
            return "Northwind row-count mismatch for \(table): expected \(expected), got \(actualDescription)"
        case let .orderSentinelMismatch(
            orderID,
            expectedDetailCount,
            actualDetailCount,
            expectedSubtotal,
            actualSubtotal
        ):
            return "Northwind order \(orderID) sentinel mismatch: expected \(expectedDetailCount) details totaling \(expectedSubtotal), got \(actualDetailCount) totaling \(actualSubtotal)"
        case let .missingOrderSentinelResult(orderID):
            return "Northwind validation could not read the order \(orderID) sentinel"
        case .missingSQLiteRuntimeMetadata:
            return "Northwind validation could not read SQLite version and source ID"
        }
    }
}


/// Access to the immutable, checksum-pinned Northwind correctness fixture.
///
/// The canonical database is always opened read-only. Tests that write must use
/// ``withTemporaryCopy(_:)`` and keep the database pool inside that closure.
public enum NorthwindFixture {

    public static let metadata = NorthwindFixtureMetadata(
        provenanceSchemaVersion: 1,
        upstreamRepository: "Northwind-swift/NorthwindSQLite.swift",
        upstreamCommit: "865de0872e61692a49cd6069cd2df8f9ac04541e",
        upstreamPath: "dist/northwind.db",
        upstreamURL: "https://github.com/Northwind-swift/NorthwindSQLite.swift/blob/865de0872e61692a49cd6069cd2df8f9ac04541e/dist/northwind.db",
        licenseSPDX: "MIT",
        upstreamLicensePath: "LICENSE",
        upstreamLicenseGitBlobSHA: "7b784d8b065952c289f6fe51adf74ed780c4d996",
        databaseResourcePath: "northwind.db",
        databaseSHA256: "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8",
        licenseNoticePath: "LICENSE.txt",
        licenseSHA256: "c28e204be6418b87ae1c83127096aad9c9e1a218c365f8f4d630e84d8ba96c47",
        databaseByteCount: 602_112,
        applicationTables: [
            "Categories",
            "CustomerCustomerDemo",
            "CustomerDemographics",
            "Customers",
            "EmployeeTerritories",
            "Employees",
            "Order Details",
            "Orders",
            "Products",
            "Regions",
            "Shippers",
            "Suppliers",
            "Territories",
        ],
        views: [
            "Alphabetical list of products",
            "Category Sales for 1997",
            "Current Product List",
            "Customer and Suppliers by City",
            "Invoices",
            "Order Details Extended",
            "Order Subtotals",
            "Orders Qry",
            "Product Sales for 1997",
            "ProductDetails_V",
            "Products Above Average Price",
            "Products by Category",
            "Quarterly Orders",
            "Sales Totals by Amount",
            "Sales by Category",
            "Summary of Sales by Quarter",
            "Summary of Sales by Year",
        ],
        rowCounts: [
            "Customers": 93,
            "Order Details": 2_155,
            "Orders": 830,
            "Products": 77,
        ],
        sentinelOrderID: 10_248,
        sentinelOrderDetailCount: 3,
        sentinelOrderSubtotal: 440.0,
        canonicalAccessPolicy: "read-only",
        mutationAccessPolicy: "unique temporary copy",
        runtimeNetworkAccess: false,
        performanceClaim: false
    )

    static var canonicalURL: URL {
        get throws {
            try bundledResourceURL(named: metadata.databaseResourcePath)
        }
    }

    static var licenseURL: URL {
        get throws {
            try bundledResourceURL(named: metadata.licenseNoticePath)
        }
    }

    static var provenanceURL: URL {
        get throws {
            try bundledResourceURL(named: "PROVENANCE.json")
        }
    }

    static var updateGuideURL: URL {
        get throws {
            try bundledResourceURL(named: "README.md")
        }
    }

    /// Validates the database bytes, SQLite integrity, exact schema sets, fixed
    /// row-count and order-subtotal sentinels, and runtime identity at an
    /// explicit URL.
    public static func validate(at url: URL) throws -> NorthwindFixtureValidation {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = PortableSHA256.hexDigest(of: data)
        guard digest == metadata.databaseSHA256 else {
            throw NorthwindFixtureError.checksumMismatch(
                resource: "database",
                expected: metadata.databaseSHA256,
                actual: digest
            )
        }
        guard data.count == metadata.databaseByteCount else {
            throw NorthwindFixtureError.schemaMismatch(
                kind: "database byte count",
                expected: [String(metadata.databaseByteCount)],
                actual: [String(data.count)]
            )
        }

        let pool = try readOnlyPool(at: url)
        defer { try? pool.close() }

        return try pool.read { database in
            let integrityCheck = try String.fetchAll(
                database,
                sql: "PRAGMA integrity_check"
            )
            guard integrityCheck == ["ok"] else {
                throw NorthwindFixtureError.integrityCheckMismatch(
                    expected: ["ok"],
                    actual: integrityCheck
                )
            }

            let applicationTables = Set(try String.fetchAll(
                database,
                sql: """
                    SELECT name
                    FROM sqlite_schema
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                    ORDER BY name
                    """
            ))
            guard applicationTables == metadata.applicationTables else {
                throw NorthwindFixtureError.schemaMismatch(
                    kind: "application tables",
                    expected: metadata.applicationTables.sorted(),
                    actual: applicationTables.sorted()
                )
            }

            let views = Set(try String.fetchAll(
                database,
                sql: """
                    SELECT name
                    FROM sqlite_schema
                    WHERE type = 'view'
                    ORDER BY name
                    """
            ))
            guard views == metadata.views else {
                throw NorthwindFixtureError.schemaMismatch(
                    kind: "views",
                    expected: metadata.views.sorted(),
                    actual: views.sorted()
                )
            }

            var rowCounts: [String: Int] = [:]
            for table in metadata.rowCounts.keys.sorted() {
                let expected = metadata.rowCounts[table]!
                let fetched = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM \(table.quotedDatabaseIdentifier)"
                )
                guard let actual = fetched, actual == expected else {
                    throw NorthwindFixtureError.rowCountMismatch(
                        table: table,
                        expected: expected,
                        actual: fetched
                    )
                }
                rowCounts[table] = actual
            }

            guard let orderSentinel = try Row.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) AS detailCount,
                           COALESCE(
                               SUM(UnitPrice * Quantity * (1 - Discount)),
                               0.0
                           ) AS subtotal
                    FROM "Order Details"
                    WHERE OrderID = ?
                    """,
                arguments: [metadata.sentinelOrderID]
            ) else {
                throw NorthwindFixtureError.missingOrderSentinelResult(
                    orderID: metadata.sentinelOrderID
                )
            }
            let sentinelOrderDetailCount: Int = orderSentinel["detailCount"]
            let sentinelOrderSubtotal: Double = orderSentinel["subtotal"]
            guard sentinelOrderDetailCount == metadata.sentinelOrderDetailCount,
                  sentinelOrderSubtotal == metadata.sentinelOrderSubtotal else {
                throw NorthwindFixtureError.orderSentinelMismatch(
                    orderID: metadata.sentinelOrderID,
                    expectedDetailCount: metadata.sentinelOrderDetailCount,
                    actualDetailCount: sentinelOrderDetailCount,
                    expectedSubtotal: metadata.sentinelOrderSubtotal,
                    actualSubtotal: sentinelOrderSubtotal
                )
            }

            guard let runtime = try Row.fetchOne(
                database,
                sql: """
                    SELECT sqlite_version() AS version,
                           sqlite_source_id() AS sourceID
                    """
            ) else {
                throw NorthwindFixtureError.missingSQLiteRuntimeMetadata
            }
            let sqliteVersion: String = runtime["version"]
            let sqliteSourceID: String = runtime["sourceID"]
            guard !sqliteVersion.isEmpty, !sqliteSourceID.isEmpty else {
                throw NorthwindFixtureError.missingSQLiteRuntimeMetadata
            }

            return NorthwindFixtureValidation(
                databaseURL: url,
                databaseSHA256: digest,
                databaseByteCount: data.count,
                integrityCheck: integrityCheck,
                applicationTables: applicationTables,
                views: views,
                rowCounts: rowCounts,
                sentinelOrderID: metadata.sentinelOrderID,
                sentinelOrderDetailCount: sentinelOrderDetailCount,
                sentinelOrderSubtotal: sentinelOrderSubtotal,
                sqliteVersion: sqliteVersion,
                sqliteSourceID: sqliteSourceID
            )
        }
    }

    public static func validateCanonical() throws -> NorthwindFixtureValidation {
        let licenseData = try Data(contentsOf: licenseURL, options: .mappedIfSafe)
        let licenseDigest = PortableSHA256.hexDigest(of: licenseData)
        guard licenseDigest == metadata.licenseSHA256 else {
            throw NorthwindFixtureError.checksumMismatch(
                resource: "license",
                expected: metadata.licenseSHA256,
                actual: licenseDigest
            )
        }
        _ = try provenanceURL
        _ = try updateGuideURL
        return try validate(at: canonicalURL)
    }

    /// Returns a validated pool whose SQLite connections use read-only and
    /// query-only modes. The caller should close the pool when finished.
    public static func validatedReadOnlyPool() throws -> DatabasePool {
        _ = try validateCanonical()
        return try readOnlyPool(at: canonicalURL)
    }

    /// Creates a unique writable copy, closes it after `body`, and removes the
    /// complete temporary directory (including any WAL/SHM sidecars). A close or
    /// removal failure is thrown after a successful body. If the body throws,
    /// its error remains primary and cleanup is attempted on a best-effort basis.
    ///
    /// Do not return or otherwise retain the supplied pool outside `body`.
    public static func withTemporaryCopy<Result>(
        _ body: (NorthwindTemporaryCopy) throws -> Result
    ) throws -> Result {
        _ = try validateCanonical()

        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "swiftql-northwind-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
            let copiedURL = directory.appendingPathComponent(metadata.databaseResourcePath)
            try fileManager.copyItem(at: canonicalURL, to: copiedURL)
            let initialValidation = try validate(at: copiedURL)

            var configuration = Configuration()
            configuration.label = "SwiftQLNorthwindFixtures.temporary.\(directory.lastPathComponent)"
            let pool = try DatabasePool(path: copiedURL.path, configuration: configuration)
            let result: Result
            do {
                result = try body(NorthwindTemporaryCopy(
                    url: copiedURL,
                    databasePool: pool,
                    initialValidation: initialValidation
                ))
            } catch {
                try? pool.close()
                try? fileManager.removeItem(at: directory)
                throw error
            }

            try pool.close()
            try fileManager.removeItem(at: directory)
            return result
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private static func bundledResourceURL(named name: String) throws -> URL {
        guard let resourceRoot = Bundle.module.resourceURL else {
            throw NorthwindFixtureError.missingResource(name)
        }
        let url = resourceRoot
            .appendingPathComponent("Northwind", isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NorthwindFixtureError.missingResource(name)
        }
        return url
    }

    private static func readOnlyPool(at url: URL) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.label = "SwiftQLNorthwindFixtures.canonical"
        configuration.readonly = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA query_only = ON")
        }
        return try DatabasePool(path: url.path, configuration: configuration)
    }
}
