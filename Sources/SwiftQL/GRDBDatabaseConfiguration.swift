//
//  GRDBDatabaseConfiguration.swift
//  SwiftQL
//
//  The connection options a GRDB-backed database is opened with, as a value
//  SwiftQL owns, so opening a database does not need `import GRDB` (issue
//  #702).
//

import Foundation
internal import GRDB


/// The connection options a ``GRDBDatabase`` opens its connection pool with.
///
/// Pass one to ``GRDBDatabase/init(url:configuration:formatter:logger:liveQueryRetryPolicy:)``
/// or ``GRDBDatabaseBuilder/init(url:configuration:formatter:logger:liveQueryRetryPolicy:)``.
/// The defaults are GRDB's own, so `GRDBDatabaseConfiguration()` opens the
/// same pool an unconfigured GRDB `Configuration` does.
///
/// ```swift
/// var configuration = GRDBDatabaseConfiguration()
/// configuration.readonly = true
/// configuration.busyTimeout = 5
/// let database = try GRDBDatabase(
///     url: databaseURL,
///     configuration: configuration,
///     logger: nil
/// )
/// ```
///
/// It covers the options an application commonly sets. A GRDB option it does
/// not cover, such as a `prepareDatabase` hook or a dispatch quality of
/// service, is reached through the GRDB escape hatch described in
/// <doc:AdvancedUsage>.
public struct GRDBDatabaseConfiguration: Hashable, Sendable {

    /// Whether the database is opened read-only. The default is `false`.
    ///
    /// A read-only database must already exist. Every write through it fails
    /// with an `XLDatabaseError` whose code is `.readOnly`.
    public var readonly: Bool

    /// Whether SQLite enforces foreign keys. The default is `true`.
    public var foreignKeysEnabled: Bool

    /// How long, in seconds, a write waits for a lock another connection
    /// holds before it fails with an `XLDatabaseError` whose code is `.busy`.
    ///
    /// The default, `nil`, fails at once. A pool serializes its own writes and
    /// its readers do not block its writer, so this matters mostly when
    /// another process, or another pool, writes the same file.
    ///
    /// It applies to the pool's writer connection. GRDB gives the pool's
    /// reader connections a 10-second timeout of its own, which this does
    /// not change. It must be between 0 and 2,147,483.647 seconds: opening a
    /// database with any other value, or with NaN, throws an `XLDatabaseError`
    /// whose code is `.misuse`.
    public var busyTimeout: TimeInterval?

    /// The most reader connections the pool opens at once. The default is
    /// `5`. It must be at least `1`: opening a database with a smaller value
    /// throws an `XLDatabaseError` whose code is `.misuse`.
    public var maximumReaderCount: Int

    /// A label for the pool's dispatch queues, shown in a debugger and in
    /// crash reports. The default is `nil`.
    public var label: String?

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - readonly: Whether the database is opened read-only.
    ///   - foreignKeysEnabled: Whether SQLite enforces foreign keys.
    ///   - busyTimeout: How long a statement waits for another connection's
    ///     lock, in seconds; `nil` fails at once.
    ///   - maximumReaderCount: The most reader connections the pool opens at
    ///     once. At least `1`.
    ///   - label: A label for the pool's dispatch queues.
    public init(
        readonly: Bool = false,
        foreignKeysEnabled: Bool = true,
        busyTimeout: TimeInterval? = nil,
        maximumReaderCount: Int = 5,
        label: String? = nil
    ) {
        self.readonly = readonly
        self.foreignKeysEnabled = foreignKeysEnabled
        self.busyTimeout = busyTimeout
        self.maximumReaderCount = maximumReaderCount
        self.label = label
    }

    /// The GRDB configuration these options describe.
    var grdbConfiguration: GRDB.Configuration {
        var configuration = GRDB.Configuration()
        configuration.readonly = readonly
        configuration.foreignKeysEnabled = foreignKeysEnabled
        if let busyTimeout {
            configuration.busyMode = .timeout(busyTimeout)
        }
        configuration.maximumReaderCount = maximumReaderCount
        configuration.label = label
        return configuration
    }
}
