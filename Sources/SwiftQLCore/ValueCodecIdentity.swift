//
//  ValueCodecIdentity.swift
//  SwiftQLCore
//
//  What names a codec, what it codes for, and where a value sits when it is
//  coded: the identifiers and coding context every other part of the codec
//  system is described in terms of.
//
//  Split out of ValueCodec.swift (issue #559).
//

import Foundation


public struct XLValueCodecKey: Hashable, Sendable, CustomStringConvertible {

    public let id: String

    public let version: UInt

    public init(id: String, version: UInt) {
        self.id = id
        self.version = version
    }

    public var stableIdentityComponents: [String] {
        [id, String(version)]
    }

    public var description: String {
        "\(id)@\(version)"
    }
}


/// A durable identity for a Swift value's persisted meaning.
public struct XLValueTypeIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}


/// A durable identity for one dialect-owned storage representation.
public struct XLValueStorageIdentifier: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}


/// The stable value-and-dialect target exposed for default and fingerprint metadata.
public struct XLValueCodecTarget: Hashable, Sendable {

    public let valueTypeIdentifier: XLValueTypeIdentifier

    public let dialectIdentifier: XLDialectIdentifier

    public init(
        valueTypeIdentifier: XLValueTypeIdentifier,
        dialectIdentifier: XLDialectIdentifier
    ) {
        self.valueTypeIdentifier = valueTypeIdentifier
        self.dialectIdentifier = dialectIdentifier
    }
}


/// Stable metadata used by schema and query fingerprints.
public struct XLValueCodecIdentity: Hashable, Sendable {

    public let key: XLValueCodecKey

    public let valueTypeIdentifier: XLValueTypeIdentifier

    public let dialectIdentifier: XLDialectIdentifier

    public let storageIdentifier: XLValueStorageIdentifier

    public init(
        key: XLValueCodecKey,
        valueTypeIdentifier: XLValueTypeIdentifier,
        dialectIdentifier: XLDialectIdentifier,
        storageIdentifier: XLValueStorageIdentifier
    ) {
        self.key = key
        self.valueTypeIdentifier = valueTypeIdentifier
        self.dialectIdentifier = dialectIdentifier
        self.storageIdentifier = storageIdentifier
    }

    public var target: XLValueCodecTarget {
        XLValueCodecTarget(
            valueTypeIdentifier: valueTypeIdentifier,
            dialectIdentifier: dialectIdentifier
        )
    }

    public var stableIdentityComponents: [String] {
        key.stableIdentityComponents + [
            valueTypeIdentifier.rawValue,
            dialectIdentifier.rawValue,
            storageIdentifier.rawValue,
        ]
    }
}


/// The semantic location at which a value is encoded or decoded.
public enum XLValueCodingSite: String, Hashable, Sendable {
    case property
    case parameter
    case result
    case configuration
}


/// A stable path to a property, parameter, result, or configuration entry.
public struct XLValueCodingPath: Hashable, Sendable, CustomStringConvertible {

    public let components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public init(_ component: String) {
        self.components = [component]
    }

    public var description: String {
        components.joined(separator: ".")
    }
}


/// Context passed to both halves of a value codec and retained in failures.
public struct XLValueCodingContext: Hashable, Sendable, CustomStringConvertible {

    public let site: XLValueCodingSite

    public let path: XLValueCodingPath

    public init(site: XLValueCodingSite, path: XLValueCodingPath) {
        self.site = site
        self.path = path
    }

    public var description: String {
        "\(site.rawValue):\(path)"
    }

    static let configurationDefaults = Self(
        site: .configuration,
        path: XLValueCodingPath("defaults")
    )
}


/// Identifies the precedence tier that selected, or failed to select, a codec.
public enum XLValueCodecSelectionSource: String, Hashable, Sendable {
    case explicit
    case query
    case configurationDefault
    case legacy
}


/// Per-use selectors layered over an immutable database coding configuration.
public struct XLValueCodecSelection: Hashable, Sendable {

    public let explicitCodecKey: XLValueCodecKey?

    public let queryCodecKey: XLValueCodecKey?

    public let legacyCodecKey: XLValueCodecKey?

    public init(
        explicitCodecKey: XLValueCodecKey? = nil,
        queryCodecKey: XLValueCodecKey? = nil,
        legacyCodecKey: XLValueCodecKey? = nil
    ) {
        self.explicitCodecKey = explicitCodecKey
        self.queryCodecKey = queryCodecKey
        self.legacyCodecKey = legacyCodecKey
    }
}


/// Query-declaration codec selection constrained by the SQL expression's
/// stable storage representation.
///
/// Unlike ``XLValueCodecSelection``, inference never consults a legacy codec.
/// A query may either request inference from its immutable configuration
/// snapshot or select one codec explicitly at the declaration/query tier.
public enum XLQueryCodecSelection: Hashable, Sendable {
    case inferred
    case explicit(XLValueCodecKey)
    case query(XLValueCodecKey)
}


/// Storage-constrained inference failures for static query declarations.
///
/// This is separate from ``XLValueCodecError`` so query inference can add
/// storage-specific diagnostics without changing that existing public enum.
