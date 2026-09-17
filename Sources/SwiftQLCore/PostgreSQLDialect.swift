import Foundation


///
/// Formats SwiftQL literals into SQL sub-expressions for use with PostgreSQL.
///
/// Rendering only. There is no driver, no transport, and no connection type:
/// this exists to prove that the dialect is the rendering seam.
///
public struct XLPostgreSQLFormatter: XLFormatter {

    public init() {}

    public func null() -> String {
        "NULL"
    }

    public func integer(_ value: Int) -> String {
        String(value)
    }

    public func real(_ value: Double) -> String {
        // A non-finite value has no literal spelling here either. The empty
        // string is the same refusal the SQLite formatter makes, and the
        // encoder records the failure rather than emitting a broken token.
        guard value.isFinite else {
            return ""
        }
        return String(value)
    }

    public func text(_ value: String) -> String {
        // Doubling an embedded quote is the standard-conforming escape, and
        // it is what PostgreSQL expects while `standard_conforming_strings`
        // is on, which has been the default since 9.1.
        guard value.contains("'") else {
            return "'\(value)'"
        }
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    public func blob(_ value: Data) -> String {
        // PostgreSQL has no `x'...'` literal. `bytea` takes the hex input
        // format, which is a string literal whose contents begin with `\x`.
        "'\\x\(value.map { String(format: "%02x", $0) }.joined())'"
    }

    public func name(_ value: String) -> String {
        // PostgreSQL folds an unquoted identifier to lower case, so SwiftQL
        // always quotes: a Swift property named `createdAt` must reach the
        // column of that exact name.
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    public func scopedName(_ values: [String]) -> String {
        values.map(name).joined(separator: ".")
    }

    public func namedBinding(_ named: String) -> String {
        // PostgreSQL's extended query protocol has no named placeholder.
        // `XLPositionalPlaceholderAssigner` never yields a named placeholder
        // for this dialect, so reaching this method means a caller rendered a
        // parameter without going through the assigner. Rendering the name
        // would produce SQL the server rejects at parse time rather than
        // silently binding the wrong value.
        "$\(named)"
    }

    public func indexedBinding(_ index: Int) -> String {
        "$\(index + 1)"
    }
}


///
/// Spells the divergent SQL vocabulary the way PostgreSQL does.
///
/// Where PostgreSQL cannot express what a SwiftQL node means, this renders
/// the closest legal text and the gap is recorded in
/// `Documentation/Architecture/PostgreSQLRenderingGaps.md`.
///
/// Two of those gaps change meaning rather than only spelling, and a driver
/// must refuse the statement rather than execute it: an insert conflict
/// algorithm is dropped (G4), and a collation SQLite names is not the
/// sequence PostgreSQL applies (G5). This type renders SQL and cannot refuse,
/// which is one reason the proof ships no driver.
///
public struct XLPostgreSQLVocabulary: XLSQLVocabulary, Hashable, Sendable {

    public init() {}

    public func spelling(for comparison: XLComparisonOperator) -> String {
        switch comparison {
        case .equal:
            // `==` is a syntax error here.
            return "="
        case .notEqual:
            return "<>"
        case .nullSafeEqual:
            return "IS NOT DISTINCT FROM"
        case .nullSafeNotEqual:
            return "IS DISTINCT FROM"
        }
    }

    public func spelling(for test: XLNullTest) -> String {
        switch test {
        case .isNull:
            return "IS NULL"
        case .isNotNull:
            return "IS NOT NULL"
        }
    }

    public func form(for function: XLConditionalFunction) -> XLConditionalForm {
        switch function {
        case .immediateIf:
            // PostgreSQL has no `IIF`.
            return .caseWhen
        }
    }

    public func spelling(for prefix: XLCommonTablePrefix) -> String {
        switch prefix {
        case .with:
            return "WITH"
        case .withRecursive:
            // PostgreSQL requires the token; SQLite does not.
            return "WITH RECURSIVE"
        }
    }

    public func spelling(for target: XLInsertTarget) -> String {
        switch target {
        case .insert:
            return "INSERT INTO"
        case .insertOr, .replace:
            // PostgreSQL resolves a conflict with a trailing `ON CONFLICT`
            // clause, not with a keyword before `INTO`. The opening clause is
            // therefore the plain one, and the conflict behaviour is lost.
            // Recorded as gap G4.
            return "INSERT INTO"
        }
    }

    public func spelling(for collation: XLCollationName) -> String {
        switch collation {
        case .binary:
            // The `C` collation compares by byte value, which is what
            // SQLite's BINARY does.
            return "\"C\""
        case .noCase, .rTrim:
            // Neither has a PostgreSQL equivalent that is a collation.
            // Case-insensitive comparison needs `citext` or an ICU collation
            // the database defines; trailing-space folding has no equivalent
            // at all. Recorded as gap G5.
            return "\"C\""
        }
    }

    public func spelling(for modifier: XLDateModifierTerm) -> String {
        // SQLite applies modifiers as text arguments to `date(...)`.
        // PostgreSQL uses interval arithmetic and `date_trunc`, which is a
        // different shape rather than different text, so these strings are
        // not valid PostgreSQL on their own. Recorded as gap G6; no golden
        // file renders a date modifier through this dialect.
        switch modifier {
        case .offset(let count, let unit):
            return "\(count) \(unit.rawValue)"
        case .startOf(let unit):
            return "\(unit.rawValue)"
        case .weekday(let day):
            return "dow \(day)"
        case .ceiling:
            return "ceiling"
        case .floor:
            return "floor"
        case .localTime:
            return "localtime"
        case .utc:
            return "utc"
        case .subsecond:
            return "microseconds"
        case .custom(let text):
            return text
        }
    }

    public func spelling(for match: XLRegexMatchOperator) -> String {
        switch match {
        case .matches:
            // Case-sensitive POSIX regular-expression match.
            return "~"
        }
    }

    public func requiredFunctions(
        for match: XLRegexMatchOperator
    ) -> Set<XLCustomFunctionDefinition> {
        // PostgreSQL matches natively, so a statement needs nothing
        // registered before it can be prepared.
        []
    }
}


///
/// A value normalized to PostgreSQL's storage model.
///
/// Deliberately minimal: this proof renders SQL and never binds a value, so
/// the type exists to satisfy the dialect contract. Native `uuid`, `json`,
/// `jsonb`, and `timestamptz` are **not** mapped onto SQLite's storage
/// presets, and adding them belongs to the production slice.
///
public enum XLPostgreSQLValue: XLDialectValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case bytea(Data)

    public var storageType: String {
        switch self {
        case .null:
            return "null"
        case .integer:
            return "bigint"
        case .real:
            return "double precision"
        case .text:
            return "text"
        case .bytea:
            return "bytea"
        }
    }
}


///
/// PostgreSQL syntax, placeholders, identifiers, and keyword spelling.
///
/// A rendering proof for the v2 dialect seam, not a supported backend. It has
/// no driver and no transport, and SwiftQL does not claim PostgreSQL support.
/// The production slice is issue #137.
///
/// The point of this type is that it changes the rendered SQL without
/// changing one expression node, one statement node, or the encoder.
///
public struct XLPostgreSQLDialect: XLSQLDialect, Hashable, Sendable {

    public typealias Value = XLPostgreSQLValue

    public static let identity = XLDialectIdentifier(rawValue: "postgresql")

    ///
    /// PostgreSQL binds by position only, so a statement that names its
    /// parameters is still rendered positionally.
    ///
    public static let standardCapabilities: XLDialectCapabilities = [
        .indexedBindings,
    ]

    public let descriptor: XLDialectDescriptor

    public init(
        version: XLDialectVersion? = nil,
        capabilities: XLDialectCapabilities = XLPostgreSQLDialect.standardCapabilities
    ) {
        self.descriptor = XLDialectDescriptor(
            identity: Self.identity,
            version: version,
            capabilities: capabilities
        )
    }

    public func makeFormatter() -> XLPostgreSQLFormatter {
        XLPostgreSQLFormatter()
    }

    public func makeVocabulary() -> XLPostgreSQLVocabulary {
        XLPostgreSQLVocabulary()
    }

    public func makePlaceholderAssigner() -> XLPositionalPlaceholderAssigner {
        XLPositionalPlaceholderAssigner()
    }

    public func formatIdentifier(_ identifier: String) -> String {
        makeFormatter().name(identifier)
    }

    public func formatQualifiedIdentifier(_ components: [String]) -> String {
        makeFormatter().scopedName(components)
    }

    public func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        switch placeholder {
        case .named(let name):
            return makeFormatter().namedBinding(name)
        case .indexed(let index):
            return makeFormatter().indexedBinding(index)
        }
    }
}
