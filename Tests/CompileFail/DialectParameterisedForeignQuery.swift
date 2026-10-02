import Foundation
import SwiftQL

// Issue #687: a model's layout built for one dialect cannot prepare a query
// on a database of another. The error names both dialects.

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

// The layout comes from the members `@SQLTable` and `@SQLCodec` generate, so
// the dialect the database refuses is the one the macro output carries.
func prepare(
    _ descriptor: XLStaticQueryDescriptor,
    configuration: XLValueCodingConfiguration,
    on database: GRDBDatabase
) throws {
    let gauge = XLSchema().table(DialectFixtureGauge.self)
    let layout = try DialectFixtureGauge.staticRowLayout(
        using: CompileFailSecondDialect.self,
        id: XLStaticSelectField<Int, Int, CompileFailSecondDialect>.intrinsic(
            selecting: gauge.id,
            identifiedBy: XLQuerySlotIdentity(path: ["gauge", "id"]),
            using: CompileFailSecondDialect()
        ),
        code: DialectFixtureGauge.staticResultField(
            code: gauge.code,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["gauge", "code"]),
            using: CompileFailSecondDialect(),
            configuration: configuration
        )
    )
    let definition = try XLTypedStaticQueryDescriptor(descriptor: descriptor, layout: layout)
    _ = try database.prepareInvocation(with: definition) // expected-error
}
