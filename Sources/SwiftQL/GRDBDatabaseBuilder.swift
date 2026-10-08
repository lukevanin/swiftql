//
//  GRDBDatabaseBuilder.swift
//  SwiftQL
//
//  Building a database whose connections carry custom functions and collations.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
internal import GRDB


/// Configures a GRDB-backed SwiftQL database before its connection pool is created.
///
/// Custom functions and collations have to be registered on every physical
/// connection the pool opens, which means they have to be declared before the
/// pool exists. That is what this type is for, and why
/// ``GRDBDatabase/init(url:configuration:formatter:logger:liveQueryRetryPolicy:)``
/// cannot offer them: by the time it runs, the pool is already open.
public struct GRDBDatabaseBuilder {
    
    private let url: URL

    private var configuration: GRDB.Configuration

    private let codingConfiguration: XLValueCodingConfiguration

    private let formatter: XLiteFormatter
    
    private let logger: XLLogger?

    private let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy
    
    /// Creates a database builder.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - configuration: The connection options the pool opens with.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDBDatabaseConfiguration = GRDBDatabaseConfiguration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            connectionConfiguration: configuration.grdbConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Creates a database builder with an immutable value-coding snapshot.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and requests built from it.
    ///   - configuration: The connection options the pool opens with.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDBDatabaseConfiguration = GRDBDatabaseConfiguration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.init(
            url: url,
            codingConfiguration: codingConfiguration,
            connectionConfiguration: configuration.grdbConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// The designated initializer. The public initializers, and the GRDB
    /// escape hatch's in `GRDBDatabase+GRDBSPI.swift`, arrive here.
    init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        connectionConfiguration: GRDB.Configuration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy
    ) {
        self.url = url
        self.configuration = connectionConfiguration
        self.codingConfiguration = codingConfiguration
        self.formatter = formatter
        self.logger = logger
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
    }
    
    /// Registers a custom scalar function on every database connection created by the builder.
    ///
    /// The registration is built here, outside the `prepareDatabase` closure.
    /// GRDB 7 declares that closure `@Sendable`, and a generic metatype such
    /// as `F.Type` is not `Sendable`.
    /// `XLCustomFunctionRegistration.make(_:)` already reduces the type to
    /// plain `Sendable` values, and it is the same registration the implicit,
    /// on-demand path uses.
    ///
    /// - Parameter function: The custom function type to register.
    public mutating func addFunction<F>(
        _ function: F.Type
    ) where F: XLCustomFunction, F.T: XLBindable & Sendable {
        let registration = XLCustomFunctionRegistration.make(function)
        configuration.prepareDatabase { database in
            database.add(function: registration.makeGRDBFunction())
        }
    }

    /// Registers a custom collating sequence on every database connection
    /// created by the builder.
    ///
    /// Name the same sequence in a query with `XLCollation(rawValue:)`. SQLite
    /// resolves collations at preparation, so an unregistered name fails with
    /// `no such collation sequence` rather than silently comparing differently.
    ///
    /// - Parameter name: Collation name, matched case-insensitively by SQLite.
    /// - Parameter compare: Ordering between two strings.
    public mutating func addCollation(
        _ name: String,
        compare: @escaping @Sendable (String, String) -> ComparisonResult
    ) {
        configuration.prepareDatabase { database in
            database.add(collation: DatabaseCollation(name, function: compare))
        }
    }

    /// Creates the configured database and its connection pool.
    public func build() throws -> GRDBDatabase {
        try GRDBDatabase(builder: self)
    }

    /// Opens the pool this builder describes.
    ///
    /// The one place a `DatabasePool` is opened from a URL. `GRDBDatabase`'s
    /// own URL initializer goes through here too (issue #560), so a change to
    /// how a pool is opened cannot apply to one path and not the other.
    ///
    /// A GRDB failure while opening, such as a file that is not a database,
    /// is reported as an `XLDatabaseError` (issue #679), including one raised
    /// by a `prepareDatabase` hook in the configuration.
    ///
    /// A `maximumReaderCount` below 1, or a busy timeout that is negative or
    /// that GRDB cannot convert to whole milliseconds, fails here with an
    /// `XLDatabaseError` whose code is `.misuse` (issue #702). GRDB would stop
    /// the process for all but a negative timeout, which SQLite would treat
    /// as no timeout at all.
    ///
    /// The queue that runs the pool's transaction bodies gets a SwiftQL mark,
    /// so a transaction scope used from a block that another queue runs on
    /// the body's thread throws instead of reaching GRDB's queue check
    /// (issue #816). See ``GRDBTransactionQueueMark``.
    func makeDatabasePool() throws -> DatabasePool {
        try xlMappingDatabaseErrors(driver: .grdb) {
            guard configuration.maximumReaderCount > 0 else {
                throw DatabaseError(
                    resultCode: .SQLITE_MISUSE,
                    message: "maximumReaderCount must be at least 1; it is "
                        + "\(configuration.maximumReaderCount)"
                )
            }
            if case .timeout(let timeout) = configuration.busyMode {
                // GRDB passes `CInt(timeout * 1000)` to SQLite, which traps
                // for a value that is not finite or does not fit.
                let milliseconds = timeout * 1000
                guard milliseconds.isFinite,
                      milliseconds >= 0,
                      milliseconds <= Double(CInt.max)
                else {
                    throw DatabaseError(
                        resultCode: .SQLITE_MISUSE,
                        message: "busy timeout must be between 0 and "
                            + "\(Double(CInt.max) / 1000) seconds; it is \(timeout)"
                    )
                }
            }
            return try DatabasePool(
                path: url.path,
                configuration: GRDBTransactionQueueMark.marking(configuration)
            )
        }
    }

    /// The database settings this builder was given.
    var databaseSettings: GRDBDatabaseSettings {
        GRDBDatabaseSettings(
            codingConfiguration: codingConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }
}


extension GRDBDatabase {

    /// Opens the database a builder describes.
    init(builder: GRDBDatabaseBuilder) throws {
        self.init(
            databasePool: try builder.makeDatabasePool(),
            settings: builder.databaseSettings
        )
    }
}
