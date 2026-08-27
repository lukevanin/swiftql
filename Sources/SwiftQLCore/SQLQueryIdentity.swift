//
//  SQLQueryIdentity.swift
//  SwiftQLCore
//
//  What names a declared query and the values it moves: the definition and
//  slot identities, the cardinality it returns, and the identity format
//  version those are hashed under.
//
//  Split out of SQLStaticQueryDescriptor.swift (issue #559).
//

import Foundation


public struct XLQueryDefinitionIdentity:
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let path: [String]

    public let version: UInt64

    public init(path: [String], version: UInt64) throws {
        try _xlValidateStablePath(path, kind: .definition)
        self.path = path
        self.version = version
    }

    public var description: String {
        "\(path.joined(separator: "/"))@\(version)"
    }
}


/// A durable logical identity for one property, parameter, or result slot.
///
/// This is intentionally separate from ``XLValueCodingContext``. Coding
/// contexts are diagnostic paths and may change without changing a query's
/// static SQL or value layout contract.
public struct XLQuerySlotIdentity:
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let path: [String]

    public init(path: [String]) throws {
        try _xlValidateStablePath(path, kind: .slot)
        self.path = path
    }

    public var description: String {
        path.joined(separator: "/")
    }
}


/// The number of rows a static query promises to expose to its caller.
public enum XLQueryCardinality: UInt8, Hashable, Sendable {
    /// A statement executed for its effects without a returned row layout.
    case command = 0

    /// A query that must produce exactly one row.
    case exactlyOne = 1

    /// A query that may produce zero or one row, but never more than one.
    case zeroOrOne = 2

    /// A query that may produce any number of rows.
    case many = 3
}


/// The version of SwiftQL's canonical static-query identity representation.
///
/// Version 1 is frozen. Changing field inclusion, ordering, tags, integer
/// encoding, or string canonicalization requires a new format version.
public struct XLQueryIdentityFormatVersion:
    RawRepresentable,
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public static let v1 = Self(rawValue: 1)

    public static let current = Self.v1

    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public var description: String {
        String(rawValue)
    }
}


/// A collision-safe, cross-process identity for one static query contract.
///
/// `canonicalBytes` is the durable identity. It is produced by a frozen binary
/// encoder and contains the complete identity material instead of a truncated
/// or randomized hash. The `Hashable` conformance is only an in-process
/// collection convenience; never persist `hashValue`.
public struct XLQueryIdentity:
    Hashable,
    Sendable,
    CustomStringConvertible
{

    public let formatVersion: XLQueryIdentityFormatVersion

    public let definitionIdentity: XLQueryDefinitionIdentity

    public let canonicalBytes: [UInt8]

    package init(
        formatVersion: XLQueryIdentityFormatVersion,
        definitionIdentity: XLQueryDefinitionIdentity,
        canonicalBytes: [UInt8]
    ) {
        self.formatVersion = formatVersion
        self.definitionIdentity = definitionIdentity
        self.canonicalBytes = canonicalBytes
    }

    /// A stable lowercase hexadecimal spelling suitable for diagnostics and
    /// persisted cache metadata.
    public var canonicalHex: String {
        let digits = Array("0123456789abcdef".utf8)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(canonicalBytes.count * 2)
        for byte in canonicalBytes {
            encoded.append(digits[Int(byte >> 4)])
            encoded.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    public var description: String {
        "swiftql-query-v\(formatVersion.rawValue)-\(canonicalHex)"
    }

    /// Verifies that one durable definition path/version still names the same
    /// canonical query contract.
    ///
    /// Reusing a definition identity for different canonical material is an
    /// explicit collision and fails closed. Incrementing the definition
    /// version produces a distinct identity and does not conflict.
    public func validateDefinitionCompatibility(
        with other: Self
    ) throws {
        guard definitionIdentity == other.definitionIdentity else {
            return
        }
        guard canonicalBytes == other.canonicalBytes else {
            throw XLStaticQueryError.definitionIdentityCollision(
                definition: definitionIdentity,
                existing: self,
                incoming: other
            )
        }
    }
}


/// A rendered, database-independent SQL statement definition.
///
/// The statement captures only static SQL and its logical requirements. It
/// never owns a database, driver, physical statement, codec registry, or
/// invocation values.


// MARK: - Shared validation

enum XLStablePathKind {
    case definition
    case slot
}


//
// Internal rather than `private`: the identities, the row metadata, and the
// descriptor were split into separate files (issue #559), and all three apply
// these same two rules.
//

func _xlValidateStablePath(
    _ path: [String],
    kind: XLStablePathKind
) throws {
    guard !path.isEmpty else {
        switch kind {
        case .definition:
            throw XLStaticQueryError.emptyDefinitionPath
        case .slot:
            throw XLStaticQueryError.emptySlotPath
        }
    }
    for (index, component) in path.enumerated() where component.isEmpty {
        switch kind {
        case .definition:
            throw XLStaticQueryError.emptyDefinitionPathComponent(index: index)
        case .slot:
            throw XLStaticQueryError.emptySlotPathComponent(index: index)
        }
    }
}


func _xlValidate(_ version: XLDialectVersion?) throws {
    guard let version else {
        return
    }
    guard version.major >= 0, version.minor >= 0, version.patch >= 0 else {
        throw XLStaticQueryError.negativeDialectVersion(version)
    }
}
