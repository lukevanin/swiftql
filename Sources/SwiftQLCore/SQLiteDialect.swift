import Foundation


/// Identifier quoting accepted by SQLite and retained by the v1 formatter shim.
public enum XLSQLiteIdentifierFormattingOptions: Hashable, Sendable {
    case noEscape
    case sqlite
    case mysqlCompatible
    case microsoftCompatible
}


/// The five runtime storage classes defined by SQLite.
public enum XLSQLiteStorageClass: String, CaseIterable, Hashable, Sendable {
    case null
    case integer
    case real
    case text
    case blob
}


/// A driver-neutral SQLite value.
public enum XLSQLiteValue: XLDialectValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var storageType: XLSQLiteStorageClass {
        switch self {
        case .null:
            return .null
        case .integer:
            return .integer
        case .real:
            return .real
        case .text:
            return .text
        case .blob:
            return .blob
        }
    }
}


/// SQLite syntax, capabilities, placeholders, identifiers, and value storage.
public struct XLSQLiteDialect: XLValueCodingDialect, Hashable, Sendable {

    public typealias Value = XLSQLiteValue

    public static let identity = XLDialectIdentifier(rawValue: "sqlite")

    public static let standardCapabilities: XLDialectCapabilities = [
        .namedBindings,
        .indexedBindings,
    ]

    public let descriptor: XLDialectDescriptor

    public let identifierFormattingOptions: XLSQLiteIdentifierFormattingOptions

    public init(
        identifierFormattingOptions: XLSQLiteIdentifierFormattingOptions = .sqlite,
        version: XLDialectVersion? = nil,
        capabilities: XLDialectCapabilities = XLSQLiteDialect.standardCapabilities
    ) {
        self.identifierFormattingOptions = identifierFormattingOptions
        self.descriptor = XLDialectDescriptor(
            identity: Self.identity,
            version: version,
            capabilities: capabilities
        )
    }

    public func formatIdentifier(_ identifier: String) -> String {
        switch identifierFormattingOptions {
        case .noEscape:
            return identifier
        case .sqlite:
            return Self.doubleQuoted(identifier)
        case .mysqlCompatible:
            return "`\(identifier.replacingOccurrences(of: "`", with: "``"))`"
        case .microsoftCompatible:
            if identifier.contains("]") {
                return Self.doubleQuoted(identifier)
            }
            return "[\(identifier)]"
        }
    }

    public func formatQualifiedIdentifier(_ components: [String]) -> String {
        components.map(formatIdentifier).joined(separator: ".")
    }

    public func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        switch placeholder {
        case .named(let name):
            return ":\(name)"
        case .indexed(let index):
            return "?\(index + 1)"
        }
    }

    public func isNull(_ value: XLSQLiteValue) -> Bool {
        value == .null
    }

    public var nullValue: XLSQLiteValue {
        .null
    }

    public func stableStorageIdentifier(
        for value: XLSQLiteValue
    ) -> XLValueStorageIdentifier {
        XLValueStorageIdentifier(rawValue: value.storageType.rawValue)
    }

    private static func doubleQuoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
