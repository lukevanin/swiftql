//
//  GRDBSQLDatabase.swift
//
//
//  Created by Luke Van In on 2023/07/31.
//
//  The database adapter itself: what it holds and how it is opened. Everything
//  it *does* lives in the GRDBDatabase+... files beside it (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


/// Everything a ``GRDBDatabase`` is configured with beyond the connection pool
/// itself.
///
/// The public initializers differ only in which of these they let a caller
/// state and which they default, which is why there are six of them. They all
/// build one of these and hand it to a single designated initializer, so the
/// defaults live in one place rather than being re-stated down a chain (issue
/// #560).
struct GRDBDatabaseConfiguration {

    /// Contextual codecs and defaults captured by the database and every
    /// request it creates.
    ///
    /// No default: building an empty one can throw, which a stored-property
    /// default cannot. Each initializer supplies it under its own `try`.
    var codingConfiguration: XLValueCodingConfiguration

    /// The formatter SwiftQL renders SQL with.
    var formatter: XLiteFormatter = XLiteFormatter()

    /// An optional logger for executed statements.
    var logger: XLLogger?

    /// Recovery policy for live-query failures.
    var liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal

    /// Where a live query's recovery work is scheduled.
    var liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler = .mainQueue
}


/// A SwiftQL database adapter backed by a GRDB `DatabasePool`.
public struct GRDBDatabase: XLDatabase {
    
    /// The GRDB connection pool used to execute requests.
    public let databasePool: DatabasePool
    
    /// The encoder used to render SwiftQL statements.
    public let encoder: XLEncoder

    /// Explicit SQLite syntax and value contract used by this adapter.
    public let dialect: XLSQLiteDialect

    /// Immutable contextual value-coding policy captured by this database.
    public let codingConfiguration: XLValueCodingConfiguration

    /// Stable identity of the database transport used by this adapter.
    public let driverIdentifier: XLDriverIdentifier

    let driver: GRDBDatabaseDriver
    
    let logger: XLLogger?

    let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    
    /// Opens a GRDB-backed SQLite database.
    ///
    /// Custom functions and collations cannot be registered through this
    /// initializer: they attach to each physical connection as the pool opens
    /// it, so they have to be declared before the pool exists. Use
    /// ``GRDBDatabaseBuilder`` when a query calls one.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - configuration: The GRDB connection configuration.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        url: URL,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: try XLValueCodingConfiguration(),
            configuration: configuration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Opens a GRDB-backed SQLite database with a value-coding snapshot.
    ///
    /// Custom functions and collations cannot be registered through this
    /// initializer; see ``GRDBDatabaseBuilder``.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - configuration: The GRDB connection configuration.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        configuration: GRDB.Configuration = GRDB.Configuration(),
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        // Through the builder, so opening a pool from a URL happens in exactly
        // one place. The builder registers nothing extra when nothing was
        // added to it, so this is the same pool the initializer used to build
        // itself.
        try self.init(
            builder: GRDBDatabaseBuilder(
                url: url,
                codingConfiguration: codingConfiguration,
                configuration: configuration,
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy
            )
        )
    }

    /// Wraps an existing GRDB database pool.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    public init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.init(
            databasePool: databasePool,
            configuration: GRDBDatabaseConfiguration(
                codingConfiguration: try XLValueCodingConfiguration(),
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy
            )
        )
    }

    /// Wraps an existing GRDB pool with a value-coding snapshot.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    public init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.init(
            databasePool: databasePool,
            configuration: GRDBDatabaseConfiguration(
                codingConfiguration: codingConfiguration,
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy
            )
        )
    }

    init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) throws {
        self.init(
            databasePool: databasePool,
            configuration: GRDBDatabaseConfiguration(
                codingConfiguration: try XLValueCodingConfiguration(),
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy,
                liveQueryRetryScheduler: liveQueryRetryScheduler
            )
        )
    }

    init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) throws {
        self.init(
            databasePool: databasePool,
            configuration: GRDBDatabaseConfiguration(
                codingConfiguration: codingConfiguration,
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy,
                liveQueryRetryScheduler: liveQueryRetryScheduler
            )
        )
    }

    /// The designated initializer. Every other one settles its arguments into a
    /// ``GRDBDatabaseConfiguration`` and arrives here.
    init(
        databasePool: DatabasePool,
        configuration: GRDBDatabaseConfiguration
    ) {
        let dialect = XLSQLiteDialect(
            identifierFormattingOptions: configuration.formatter
                .identifierFormattingOptions
        )
        let driver = GRDBDatabaseDriver(
            databasePool: databasePool,
            dialect: dialect
        )
        self.dialect = dialect
        self.codingConfiguration = configuration.codingConfiguration
        self.encoder = XLiteEncoder(dialect: dialect)
        self.databasePool = databasePool
        self.driverIdentifier = driver.driverIdentifier
        self.driver = driver
        self.logger = configuration.logger
        self.liveQueryRetryPolicy = configuration.liveQueryRetryPolicy
        self.liveQueryRetryScheduler = configuration.liveQueryRetryScheduler
    }

    /// Constructs a transaction-scoped copy of this database (issue #284),
    /// pinned to `pinnedDriver`'s connection. Every other field is copied
    /// unchanged, so a pinned scope renders through the same encoder,
    /// dialect, coding snapshot, logger, and live-query retry policy as the
    /// database ``withTransaction(_:)`` was called on.
    init(pinnedDriver: GRDBDatabaseDriver, pinnedFrom other: GRDBDatabase) {
        self.dialect = other.dialect
        self.encoder = other.encoder
        self.codingConfiguration = other.codingConfiguration
        self.databasePool = other.databasePool
        self.driverIdentifier = other.driverIdentifier
        self.driver = pinnedDriver
        self.logger = other.logger
        self.liveQueryRetryPolicy = other.liveQueryRetryPolicy
        self.liveQueryRetryScheduler = other.liveQueryRetryScheduler
    }

    /// Scopes render-once cache entries (issues #18/#26) to this database and
    /// dialect. Rendering depends only on the dialect; the database identifier
    /// keeps a per-declaration `static` cache from binding one database's
    /// request to another. The driver assigns a fresh identifier per init, so
    /// the scope is per `GRDBDatabase` instance rather than per `DatabasePool`
    /// (see ``XLPreparedQueryCacheKey``).
    public var preparedQueryCacheKey: XLPreparedQueryCacheKey? {
        XLPreparedQueryCacheKey(
            databaseIdentifier: driver.databaseIdentifier,
            dialectIdentifier: dialect.descriptor.identity
        )
    }
}
