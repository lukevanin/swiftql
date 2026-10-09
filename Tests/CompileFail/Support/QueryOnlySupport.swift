import Foundation
import SwiftQLQuery

// Issue #790: shared by the QueryOnly* fixtures, which
// `scripts/ci/check-dialect-type-parameter-type-safety.sh` compiles with this
// file and with the query-only dialect's generated surface, and with nothing
// that imports SwiftQLSQLite or SwiftQL. It is what a dialect author's module
// sees: the dialect-neutral query surface and SwiftQLCore. It must type-check
// on its own: an error here is a fault in the gate, not evidence.

/// The query-only dialect's values. Its storage is not SQLite's.
enum QueryOnlyDialectValue: XLDialectValue {
    case null
    case string(String)

    var storageType: String {
        "query-only"
    }
}

/// A dialect declared against SwiftQLQuery alone, as a dialect author's would
/// be. Nothing here runs.
struct QueryOnlyDialect: XLLiteralValueDialect {
    typealias Value = QueryOnlyDialectValue

    let descriptor = XLDialectDescriptor(
        identity: XLDialectIdentifier(rawValue: "compile-fail.query-only")
    )

    func makeFormatter() -> XLiteFormatter { XLiteFormatter() }
    func makeVocabulary() -> XLiteVocabulary { XLiteVocabulary() }
    func makePlaceholderAssigner() -> XLitePlaceholderAssigner { XLitePlaceholderAssigner() }
    func formatIdentifier(_ identifier: String) -> String { identifier }
    func formatQualifiedIdentifier(_ components: [String]) -> String { components.joined(separator: ".") }
    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String { "?" }
    func isNull(_ value: Value) -> Bool { value == .null }
    var nullValue: Value { .null }
    func stableStorageIdentifier(for value: Value) -> XLValueStorageIdentifier {
        XLValueStorageIdentifier(rawValue: value.storageType)
    }

    static func literalStorageIdentifier(for type: Any.Type) -> XLValueStorageIdentifier? { nil }
    static func decodeLiteral<Literal: XLLiteral>(_ type: Literal.Type, from value: Value) throws -> Literal { fatalError() }
    static func encodeLiteral<Literal: XLBindable>(_ value: Literal, valueType: String, codingContext: XLValueCodingContext) throws -> Value { .null }
    static func isNullLiteral(_ value: Value) -> Bool { value == .null }
}

/// A model of the query-only dialect. Its expansion names only SwiftQLQuery,
/// SwiftQLCore, and the dialect's own surface.
@SQLTable(name: "QueryOnlyPerson", dialect: QueryOnlyDialect.self)
struct QueryOnlyPerson {
    var id: Int
    var name: String
    var level: QueryOnlyLevel
}

/// An enum of the query-only dialect, through its generated composition.
enum QueryOnlyLevel: Int, QueryOnlyDialectEnum {
    typealias T = Self

    case junior = 0
    case senior = 1

    static func sqlDefault() -> QueryOnlyLevel {
        .junior
    }
}
