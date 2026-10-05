//
//  GRDBDatabase+GRDBSPI.swift
//  SwiftQL
//
//  The GRDB escape hatch (issue #702): every SwiftQL declaration that takes
//  or returns a GRDB type. They are SPI, so a client declares them with
//  `@_spi(GRDB) import SwiftQL`, and they live here so that this is the one
//  SwiftQL file that imports GRDB `public`. Every other file imports it
//  `internal` or `package`, and the compiler rejects a GRDB type in their
//  public declarations.
//

import Foundation
public import GRDB


extension GRDBDatabase {

    /// The GRDB connection pool used to execute requests.
    ///
    /// Part of the GRDB escape hatch: declare it with
    /// `@_spi(GRDB) import SwiftQL`.
    @_spi(GRDB)
    public var databasePool: DatabasePool {
        pool
    }

    /// Wraps an existing GRDB database pool.
    ///
    /// Part of the GRDB escape hatch: declare it with
    /// `@_spi(GRDB) import SwiftQL`.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures. The
    ///     default is ``GRDBLiveQueryRetryPolicy/terminal``.
    @_spi(GRDB)
    public init(
        databasePool: DatabasePool,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.init(
            databasePool: databasePool,
            settings: GRDBDatabaseSettings(
                codingConfiguration: try XLValueCodingConfiguration(),
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy
            )
        )
    }

    /// Wraps an existing GRDB pool with a value-coding snapshot.
    ///
    /// Part of the GRDB escape hatch: declare it with
    /// `@_spi(GRDB) import SwiftQL`.
    ///
    /// - Parameters:
    ///   - databasePool: The pool used to execute requests.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and every request it creates.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    @_spi(GRDB)
    public init(
        databasePool: DatabasePool,
        codingConfiguration: XLValueCodingConfiguration,
        formatter: XLiteFormatter,
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.init(
            databasePool: databasePool,
            settings: GRDBDatabaseSettings(
                codingConfiguration: codingConfiguration,
                formatter: formatter,
                logger: logger,
                liveQueryRetryPolicy: liveQueryRetryPolicy
            )
        )
    }
}


extension GRDBDatabaseBuilder {

    /// Creates a database builder that extends a GRDB configuration.
    ///
    /// Part of the GRDB escape hatch (issue #702): declare it with
    /// `@_spi(GRDB) import SwiftQL`. Use it for a GRDB option that
    /// ``GRDBDatabaseConfiguration`` does not cover, such as a
    /// `prepareDatabase` hook. Functions and collations added to the builder
    /// are registered after the configuration's own `prepareDatabase` hooks.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - grdbConfiguration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    @_spi(GRDB)
    public init(
        url: URL,
        grdbConfiguration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        try self.init(
            url: url,
            codingConfiguration: XLValueCodingConfiguration(),
            grdbConfiguration: grdbConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }

    /// Creates a database builder that extends a GRDB configuration, with an
    /// immutable value-coding snapshot.
    ///
    /// Part of the GRDB escape hatch (issue #702): declare it with
    /// `@_spi(GRDB) import SwiftQL`.
    ///
    /// - Parameters:
    ///   - url: The SQLite database file URL.
    ///   - codingConfiguration: Contextual codecs and defaults captured by the
    ///     database and requests built from it.
    ///   - grdbConfiguration: The GRDB connection configuration to extend.
    ///   - formatter: The formatter used when SwiftQL renders SQL.
    ///   - logger: An optional logger for executed statements.
    ///   - liveQueryRetryPolicy: Recovery policy for live-query failures.
    @_spi(GRDB)
    public init(
        url: URL,
        codingConfiguration: XLValueCodingConfiguration,
        grdbConfiguration: GRDB.Configuration,
        formatter: XLiteFormatter = XLiteFormatter(),
        logger: XLLogger?,
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy = .terminal
    ) throws {
        self.init(
            url: url,
            codingConfiguration: codingConfiguration,
            connectionConfiguration: grdbConfiguration,
            formatter: formatter,
            logger: logger,
            liveQueryRetryPolicy: liveQueryRetryPolicy
        )
    }
}
