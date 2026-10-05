import Foundation
import SwiftQL

// Issue #687: shared by the DialectParameterised* fixtures, which
// `scripts/ci/check-dialect-parameterised-macro-type-safety.sh` compiles with
// this file. It must type-check on its own: an error here is a fault in the
// gate, not evidence.

/// A second dialect's values. Its storage is not SQLite's.
enum CompileFailSecondDialectValue: XLDialectValue {
    case null
    case string(String)

    var storageType: String {
        "second"
    }
}

/// A second dialect, enough to type-check against. Nothing here runs.
struct CompileFailSecondDialect: XLLiteralValueDialect {
    typealias Value = CompileFailSecondDialectValue

    let descriptor = XLDialectDescriptor(
        identity: XLDialectIdentifier(rawValue: "compile-fail.second")
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

enum DialectFixtureCodecs {
    static let reversed = XLValueCodecKey(id: "compile-fail.reversed", version: 1)
}

/// One model, declared once. Nothing here names a dialect.
@SQLTable struct DialectFixtureGauge {
    var id: Int
    @SQLCodec(DialectFixtureCodecs.reversed)
    var code: String
}
