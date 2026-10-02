import Foundation
import SwiftQL

// Issue #687: one model, declared once, builds its static layout for SQLite
// and for a second dialect. Every generated member the layout uses absorbs
// the dialect, so the call site does not change between the two.

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

@SQLBindings(dialect: CompileFailSecondDialect.self)
struct DialectFixtureBindings {
    var code: String
}

func dialectFixtureLayout<Dialect: XLLiteralValueDialect>(
    using dialect: Dialect,
    configuration: XLValueCodingConfiguration
) throws -> XLStaticRowLayout<DialectFixtureGauge, Dialect> {
    let gauge = XLSchema().table(DialectFixtureGauge.self)
    return try DialectFixtureGauge.staticRowLayout(
        using: Dialect.self,
        id: XLStaticSelectField<Int, Int, Dialect>.intrinsic(
            selecting: gauge.id,
            identifiedBy: XLQuerySlotIdentity(path: ["gauge", "id"]),
            using: dialect
        ),
        code: DialectFixtureGauge.staticResultField(
            code: gauge.code,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["gauge", "code"]),
            using: dialect,
            configuration: configuration
        )
    )
}

func bothDialects(configuration: XLValueCodingConfiguration) throws {
    let sqlite: XLStaticRowLayout<DialectFixtureGauge, XLSQLiteDialect> = try dialectFixtureLayout(
        using: XLSQLiteDialect(),
        configuration: configuration
    )
    let second: XLStaticRowLayout<DialectFixtureGauge, CompileFailSecondDialect> = try dialectFixtureLayout(
        using: CompileFailSecondDialect(),
        configuration: configuration
    )
    _ = (sqlite, second)
    let packet: XLInvocationBindings<CompileFailSecondDialectValue> = try DialectFixtureBindings(code: "abc")
        .bindings(in: .empty)
    _ = packet
}
