//
//  GRDBDatabaseBuilder.swift
//  SwiftQL
//
//  Building a database whose connections carry custom functions and collations.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


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
    ///   - configuration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            configuration: configuration,
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
    ///   - configuration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.url = url
        self.configuration = configuration
        self.codingConfiguration = codingConfiguration
        self.formatter = formatter
        self.logger = logger
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
    }
    
    /// Registers a custom scalar function on every database connection created by the builder.
    ///
    /// - Parameter function: The custom function type to register.
    public mutating func addFunction<F>(_ function: F.Type) where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        configuration.prepareDatabase { database in
            database.add(
                function: DatabaseFunction(
                    function.definition.name,
                    argumentCount: Int(function.definition.numberOfArguments),
                    function: { values in
                        let reader = GRDBValuesAdapter(values: values)
                        return try F.execute(reader: reader)
                    }
                )
            )
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
    func makeDatabasePool() throws -> DatabasePool {
        try DatabasePool(path: url.path, configuration: configuration)
    }

    /// The database configuration this builder was given.
    var databaseConfiguration: GRDBDatabaseConfiguration {
        GRDBDatabaseConfiguration(
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
            configuration: builder.databaseConfiguration
        )
    }
}
