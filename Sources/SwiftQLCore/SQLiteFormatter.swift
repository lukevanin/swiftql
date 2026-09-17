import Foundation


///
/// Formats SwiftQL literals into SQL sub-expressions for use with SQLite.
///
public struct XLiteFormatter: XLFormatter {

    ///
    /// Defines the escape sequence used to encode identifiers.
    ///
    /// SQLite provides compatibility for different conventions for escaping names of identifiers. SwiftQL
    /// uses SQLite's canonical double-quoted identifier syntax by default.
    ///
    public typealias IdentifierFormattingOptions = XLSQLiteIdentifierFormattingOptions

    public var identifierFormattingOptions: IdentifierFormattingOptions

    public init(identifierFormattingOptions: IdentifierFormattingOptions = .sqlite) {
        self.identifierFormattingOptions = identifierFormattingOptions
    }

    public func null() -> String {
        "NULL"
    }

    public func integer(_ value: Int) -> String {
        String(value)
    }

    public func real(_ value: Double) -> String {
        guard value.isFinite else {
            return ""
        }
        return String(value)
    }

    public func text(_ text: String) -> String {
        // Embedded single quotes must be doubled per the SQL standard, otherwise
        // the value breaks out of the literal (broken SQL at best, injection at worst).
        guard text.contains("'") else {
            return "'\(text)'"
        }
        return "'\(text.replacingOccurrences(of: "'", with: "''"))'"
    }

    public func text(_ text: StaticString) -> String {
        self.text(text.description)
    }

    public func blob(_ data: Data) -> String {
        "x'\(data.hex())'"
    }

    public func name(_ value: String) -> String {
        XLSQLiteDialect(
            identifierFormattingOptions: identifierFormattingOptions
        ).formatIdentifier(value)
    }

    public func scopedName(_ values: [String]) -> String {
        // Qualified names are almost always one ("column") or two
        // ("table"."column") components. Handle those without the intermediate
        // `map` array that `joined` would otherwise allocate on every reference.
        switch values.count {
        case 0:
            return ""
        case 1:
            return name(values[0])
        case 2:
            // Build in place so only the result string is allocated; `a + "." + b`
            // would materialise an extra intermediate from the first `+`.
            var scoped = name(values[0])
            scoped += "."
            scoped += name(values[1])
            return scoped
        default:
            return values.map(name).joined(separator: ".")
        }
    }

    public func namedBinding(_ named: String) -> String {
        ":\(named)"
    }

    public func indexedBinding(_ index: Int) -> String {
        "?\(index + 1)"
    }
}


extension Data {

    ///
    /// Convenience function used to encode data into a hexadecimal string.
    ///
    internal func hex() -> String {
        map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
