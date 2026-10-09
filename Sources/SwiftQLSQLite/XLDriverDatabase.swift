//
//  XLDriverDatabase.swift
//  SwiftQL
//
//  A SwiftQL database over any driver that implements the driver contract
//  (issue #682).
//

import Foundation


///
/// A SwiftQL database over any driver that implements SwiftQL's driver
/// contract (issue #682).
///
/// `XLDriverDatabase` makes the same requests, write requests, result sets,
/// prepared invocations, and static queries as `GRDBDatabase`, through the
/// same implementation, but runs them on the driver it is given. A driver from
/// outside SwiftQL plugs in here: it needs no GRDB types, and SwiftQL needs
/// nothing from it beyond the driver protocols.
///
/// The driver must conform to three protocols from SwiftQLCore:
///
/// - `XLDatabaseDriver`, whose asynchronous scopes serve each request's
///   `async` view;
/// - `XLBlockingDatabaseDriver`, whose blocking scopes serve the synchronous
///   members, such as `fetchAll()` and `execute()`;
/// - `XLObservingDatabaseDriver`, whose `observe(_:fetch:)` serves the
///   live-query members, `stream()` and the publish members.
///
/// Its dialect must be `XLSQLiteDialect`: requests bind and decode SQLite
/// values. Dialect-parametric storage is issue #686.
///
/// ```swift
/// let database = try XLDriverDatabase(driver: MyDriver())
/// let people = try database.makeRequest(with: peopleQuery).fetchAll()
/// ```
///
/// Two capabilities of `GRDBDatabase` are not offered here yet:
///
/// - Transaction scopes. `XLDriverDatabase` conforms to `XLDatabase`, not
///   `XLTransactionalDatabase`, because a portable way for a driver to pin
///   one connection for a scope does not exist yet (issue #808).
/// - Batch inserts with `insert(contentsOf:)`, which rely on GRDB savepoints.
///
public struct XLDriverDatabase<Driver>: XLDatabase
    where Driver: XLBlockingDatabaseDriver,
          Driver: XLObservingDatabaseDriver,
          Driver.Dialect == XLSQLiteDialect
{

    /// The driver every request this database makes runs on.
    public let driver: Driver

    /// The encoder used to render SwiftQL statements, for the driver's
    /// dialect.
    public let encoder: XLEncoder

    /// Immutable contextual value-coding policy captured by this database and
    /// every request it makes.
    public let codingConfiguration: XLValueCodingConfiguration

    package let logger: XLLogger?

    /// The identity render-once cache entries are keyed by: one per database
    /// value, not per driver. A cached request captures this database's coding
    /// configuration and logger, so two databases over one driver must not
    /// share entries.
    let renderCacheIdentifier = XLDatabaseIdentifier(rawValue: UUID())

    /// Creates a database over `driver`, with an explicit value-coding policy.
    ///
    /// - Parameters:
    ///   - driver: The driver every request runs on. Statements are rendered
    ///     for its dialect, including its identifier formatting options.
    ///   - codingConfiguration: The contextual codecs and defaults every
    ///     request captures.
    ///   - logger: An optional logger for executed statements.
    public init(
        driver: Driver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger? = nil
    ) {
        self.driver = driver
        self.encoder = XLiteEncoder(dialect: driver.dialect)
        self.codingConfiguration = codingConfiguration
        self.logger = logger
    }

    /// Creates a database over `driver`, with SwiftQL's default value-coding
    /// policy.
    ///
    /// - Parameters:
    ///   - driver: The driver every request runs on.
    ///   - logger: An optional logger for executed statements.
    /// - Throws: An error when the default value-coding policy cannot be
    ///   built.
    public init(driver: Driver, logger: XLLogger? = nil) throws {
        self.init(
            driver: driver,
            codingConfiguration: try XLValueCodingConfiguration(),
            logger: logger
        )
    }

    /// The SQLite dialect statements are rendered for: the driver's own.
    public var dialect: XLSQLiteDialect {
        driver.dialect
    }

    /// Stable identity of the driver's database transport.
    public var driverIdentifier: XLDriverIdentifier {
        driver.driverIdentifier
    }

    /// Scopes render-once cache entries to this database and its dialect, so
    /// a declared query renders once per database (see
    /// `XLPreparedQueryCacheKey`).
    ///
    /// The key belongs to this database value, not to its driver: each cached
    /// request captures the database's coding configuration and logger, so a
    /// second database over the same driver renders its own entries. Copies
    /// of one database share the key.
    public var preparedQueryCacheKey: XLPreparedQueryCacheKey? {
        XLPreparedQueryCacheKey(
            databaseIdentifier: renderCacheIdentifier,
            dialectIdentifier: dialect.descriptor.identity
        )
    }

    public func makeRequest<Row: Sendable>(
        with statement: any XLQueryStatement<Row>
    ) -> any XLRequest<Row> {
        makeQueryRequest(with: statement)
    }

    public func makeRequest<Row: Sendable>(
        with statement: any XLReturningStatement<Row>
    ) -> any XLRequest<Row> {
        makeReturningRequest(with: statement)
    }

    public func makeRequest(with statement: any XLUpdateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    public func makeRequest(with statement: any XLInsertStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    public func makeRequest(with statement: any XLCreateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    public func makeRequest(with statement: any XLDeleteStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    /// Prepares an immutable raw-value runtime handle for concurrent
    /// invocations of one rendered statement.
    public func prepareInvocation(
        with statement: any XLEncodable
    ) -> XLPreparedInvocation {
        makePreparedInvocation(with: statement)
    }

    /// Prepares a database-independent static query descriptor against this
    /// database's dialect and immutable coding snapshot.
    ///
    /// Only the functions SwiftQL bundles, such as `regexp`, are made
    /// available to the statement. An application's own custom function must
    /// already be on the driver's connections.
    public func prepareInvocation(
        with descriptor: XLStaticQueryDescriptor
    ) throws -> XLPreparedStaticQuery {
        try makePreparedStaticQuery(with: descriptor)
    }

    /// Prepares a typed static query only after its generated row layout has
    /// been proven equal to the descriptor's complete result metadata.
    public func prepareInvocation<Row>(
        with definition: XLTypedStaticQueryDescriptor<Row, XLSQLiteDialect>
    ) throws -> XLPreparedTypedStaticQuery<Row> {
        try makePreparedTypedStaticQuery(with: definition)
    }
}


extension XLDriverDatabase: XLDriverRequestFactory {}


/// Contextual bindings and query captures resolve against this database's
/// coding snapshot through the members ``XLValueCodingDatabase`` provides,
/// which `GRDBDatabase` shares (issue #113). The request factory implies
/// this conformance too; it is stated here so that a reader of this type
/// sees it.
extension XLDriverDatabase: XLValueCodingDatabase {}


/// `@unchecked Sendable` because sharing one value across threads is this
/// type's purpose, as it is `GRDBDatabase`'s: every stored property is
/// immutable, the driver is `Sendable`, and the encoder renders without
/// shared mutable state, but `XLEncoder` itself is not declared `Sendable`.
extension XLDriverDatabase: @unchecked Sendable {}
