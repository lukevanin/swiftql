import Foundation


/// A stable identity for one SQL dialect.
public struct XLDialectIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}


/// A stable identity for one database-driver implementation.
public struct XLDriverIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}


/// Identifies a concrete database or pool independently of its driver type.
public struct XLDatabaseIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }
}


/// A comparable semantic version reported by a dialect implementation.
public struct XLDialectVersion: Comparable, Hashable, Sendable, CustomStringConvertible {

    public let major: Int

    public let minor: Int

    public let patch: Int

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}


/// Syntax and placeholder capabilities owned by a dialect.
public struct XLDialectCapabilities: OptionSet, Hashable, Sendable {

    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let namedBindings = Self(rawValue: 1 << 0)

    public static let indexedBindings = Self(rawValue: 1 << 1)
}


/// Runtime identity, version, and capabilities for a dialect implementation.
public struct XLDialectDescriptor: Hashable, Sendable {

    public let identity: XLDialectIdentifier

    public let version: XLDialectVersion?

    public let capabilities: XLDialectCapabilities

    public init(
        identity: XLDialectIdentifier,
        version: XLDialectVersion? = nil,
        capabilities: XLDialectCapabilities = []
    ) {
        self.identity = identity
        self.version = version
        self.capabilities = capabilities
    }
}


/// Dialect constraints captured by a logical prepared statement.
public struct XLDialectRequirement: Hashable, Sendable {

    public let identity: XLDialectIdentifier

    public let minimumVersion: XLDialectVersion?

    public let capabilities: XLDialectCapabilities

    public init(
        identity: XLDialectIdentifier,
        minimumVersion: XLDialectVersion? = nil,
        capabilities: XLDialectCapabilities = []
    ) {
        self.identity = identity
        self.minimumVersion = minimumVersion
        self.capabilities = capabilities
    }

    /// Validates identity, minimum version, and required capabilities in that order.
    public func validate(_ descriptor: XLDialectDescriptor) throws {
        guard descriptor.identity == identity else {
            throw XLDatabaseContractError.dialectMismatch(
                expected: identity,
                actual: descriptor.identity
            )
        }

        if let minimumVersion {
            guard let actualVersion = descriptor.version, actualVersion >= minimumVersion else {
                throw XLDatabaseContractError.versionMismatch(
                    dialect: identity,
                    minimum: minimumVersion,
                    actual: descriptor.version
                )
            }
        }

        guard descriptor.capabilities.contains(capabilities) else {
            throw XLDatabaseContractError.capabilityMismatch(
                dialect: identity,
                required: capabilities,
                available: descriptor.capabilities
            )
        }
    }
}


/// A placeholder rendered into SQL text.
public enum XLBindingPlaceholder: Hashable, Sendable {
    case named(String)
    case indexed(Int)
}


/// The logical key used to bind one value to a physical statement.
public enum XLBindingKey: Hashable, Sendable {
    case named(String)
    case indexed(Int)
}


/// A value normalized to the storage model owned by one SQL dialect.
public protocol XLDialectValue: Hashable, Sendable {

    associatedtype StorageType: Hashable & Sendable

    var storageType: StorageType { get }
}


/// Defines SQL rendering and the value model for one dialect.
public protocol XLSQLDialect: Sendable {

    associatedtype Value: XLDialectValue

    var descriptor: XLDialectDescriptor { get }

    func formatIdentifier(_ identifier: String) -> String

    func formatQualifiedIdentifier(_ components: [String]) -> String

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String
}


/// A dialect that exposes the stable value operations required by codecs.
///
/// This refinement keeps existing `XLSQLDialect` conformers source-compatible:
/// only dialects that opt into contextual value coding must provide these rules.
public protocol XLValueCodingDialect: XLSQLDialect {

    /// Returns whether a normalized dialect value represents SQL `NULL`.
    func isNull(_ value: Value) -> Bool

    /// The normalized SQL `NULL` value.
    var nullValue: Value { get }

    /// A stable identifier for the value's dialect-owned storage representation.
    func stableStorageIdentifier(for value: Value) -> XLValueStorageIdentifier
}


/// A database-bound logical statement that owns no physical connection statement.
public struct XLLogicalPreparedStatement: Hashable, Sendable {

    public let databaseIdentifier: XLDatabaseIdentifier

    public let dialectRequirement: XLDialectRequirement

    public let sql: String

    public let entities: Set<String>

    /// Immutable static parameter metadata captured while rendering `sql`.
    public let parameterLayout: XLParameterLayout

    public init(
        databaseIdentifier: XLDatabaseIdentifier,
        dialectRequirement: XLDialectRequirement,
        sql: String,
        entities: Set<String> = [],
        parameterLayout: XLParameterLayout = .empty
    ) {
        self.databaseIdentifier = databaseIdentifier
        self.dialectRequirement = dialectRequirement
        self.sql = sql
        self.entities = entities
        self.parameterLayout = parameterLayout
    }
}


/// Proof that a logical statement matches a connection's database and dialect.
///
/// Only the connection wrapper can create this value, so a driver conformance
/// cannot accidentally prepare an unvalidated logical statement.
public struct XLValidatedLogicalPreparedStatement: Hashable, Sendable {

    public let logicalStatement: XLLogicalPreparedStatement

    init(_ logicalStatement: XLLogicalPreparedStatement) {
        self.logicalStatement = logicalStatement
    }
}
