import Foundation
import SwiftQL

// Issue #687: a field built for one dialect cannot join a layout for another.
// The error names both dialects.

enum CompileFailSecondDialectValue: XLDialectValue {
    case null
    case string(String)

    var storageType: String {
        "second"
    }
}

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

@SQLTable struct DialectFixtureGauge {
    var id: Int
    @SQLCodec(DialectFixtureCodecs.reversed)
    var code: String
}

func mixedLayout(configuration: XLValueCodingConfiguration) throws {
    let gauge = XLSchema().table(DialectFixtureGauge.self)
    let id = try XLStaticSelectField<Int, Int, XLSQLiteDialect>.intrinsic(
        selecting: gauge.id,
        identifiedBy: XLQuerySlotIdentity(path: ["gauge", "id"])
    )
    let code = try DialectFixtureGauge.staticResultField(
        code: gauge.code,
        storedAs: String.self,
        identifiedBy: XLQuerySlotIdentity(path: ["gauge", "code"]),
        using: CompileFailSecondDialect(),
        configuration: configuration
    )
    _ = try DialectFixtureGauge.staticRowLayout(using: XLSQLiteDialect.self, id: id, code: code) // expected-error
}
