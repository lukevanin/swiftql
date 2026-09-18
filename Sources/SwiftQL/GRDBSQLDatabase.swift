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

    /// Where a live query's recovery work is scheduled. `nil`, the default,
    /// waits on each observation's own private serial queue (issue #652).
    var liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler? = nil

    /// The encoder the database renders statements with. `nil`, the default,
    /// uses an `XLiteEncoder` for the database's dialect. Tests set it to
    /// count renders (issue #668); no public initializer sets it.
    var encoder: XLEncoder? = nil
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

    /// The database identifier render-once cache entries are keyed by: this
    /// database's own driver identifier, which a transaction scope copies from
    /// the database it was opened on instead of using its pinned driver's fresh
    /// one (issue #642).
    let renderCacheIdentifier: XLDatabaseIdentifier
    
    let logger: XLLogger?

    let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler?

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
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler?
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
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler?
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
        self.encoder = configuration.encoder ?? XLiteEncoder(dialect: dialect)
        self.databasePool = databasePool
        self.driverIdentifier = driver.driverIdentifier
        self.driver = driver
        self.renderCacheIdentifier = driver.databaseIdentifier
        self.logger = configuration.logger
        self.liveQueryRetryPolicy = configuration.liveQueryRetryPolicy
        self.liveQueryRetryScheduler = configuration.liveQueryRetryScheduler
    }

    /// Constructs a transaction-scoped copy of this database (issue #284),
    /// pinned to `pinnedDriver`'s connection. Every other field is copied
    /// unchanged, so a pinned scope renders through the same encoder,
    /// dialect, coding snapshot, logger, and live-query retry policy as the
    /// database ``withTransaction(_:)`` was called on. It also keeps that
    /// database's render-once cache identifier, so it shares that database's
    /// cache entries instead of adding its own (issue #642).
    init(pinnedDriver: GRDBDatabaseDriver, pinnedFrom other: GRDBDatabase) {
        self.dialect = other.dialect
        self.encoder = other.encoder
        self.codingConfiguration = other.codingConfiguration
        self.databasePool = other.databasePool
        self.driverIdentifier = other.driverIdentifier
        self.driver = pinnedDriver
        self.renderCacheIdentifier = other.renderCacheIdentifier
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
    ///
    /// A transaction scope returns the key of the database it was opened on,
    /// not a key of its own (issue #642). Its pinned driver still has a fresh
    /// identifier, but keying on that added one permanent entry per
    /// transaction. The cache binds the shared entry to the scope's driver at
    /// call time instead; see `bindRenderOnceRequest(_:)`.
    public var preparedQueryCacheKey: XLPreparedQueryCacheKey? {
        XLPreparedQueryCacheKey(
            databaseIdentifier: renderCacheIdentifier,
            dialectIdentifier: dialect.descriptor.identity
        )
    }
}


extension GRDBDatabase: XLRenderOnceRequestBinding {

    /// Binds a render-once cache entry to this database's driver (issue #642).
    ///
    /// One entry serves a database and every transaction scope opened on it,
    /// and the cache stores it bound to the database's pool driver (see
    /// `storableRenderOnceRequest(_:)`). It is returned unchanged when that
    /// driver is this database's own, and rebuilt around this driver otherwise
    /// -- on a scope, the pinned driver. Rebuilding reuses the rendered SQL,
    /// parameter layout, row reader, and recorded functions, so it renders
    /// nothing.
    func bindRenderOnceRequest<Row: Sendable>(_ request: any XLRequest<Row>) -> any XLRequest<Row> {
        guard let grdbRequest = request as? GRDBRequest<Row> else {
            assertionFailure("A GRDBDatabase render-once entry must be a GRDBRequest.")
            return request
        }
        guard grdbRequest.executor.driver.databaseIdentifier != driver.databaseIdentifier else {
            return request
        }
        return grdbRequest.rebound(to: driver)
    }

    /// The request a render-once cache stores for this database's key (issue
    /// #642): bound to the pool driver of the database that owns the key.
    ///
    /// A transaction scope that renders an entry first would otherwise store a
    /// request bound to its pinned driver. That entry would keep the scope's
    /// invalidated connection, and every later call on the database would have
    /// to rebuild it. The pool driver is rebuilt from the scope's own values --
    /// the pool, the dialect, and the cache identifier the scope copied from
    /// its database -- so it is the database's driver, with the identifier the
    /// root re-entry guard checks.
    func storableRenderOnceRequest<Row>(_ request: any XLRequest<Row>) -> any XLRequest<Row> {
        guard driver.isPinned else {
            return request
        }
        guard let grdbRequest = request as? GRDBRequest<Row> else {
            assertionFailure("A GRDBDatabase render-once entry must be a GRDBRequest.")
            return request
        }
        return grdbRequest.rebound(
            to: GRDBDatabaseDriver(
                databasePool: databasePool,
                dialect: dialect,
                databaseIdentifier: renderCacheIdentifier
            )
        )
    }
}
