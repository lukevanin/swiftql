import Foundation
import SwiftQL

// Issue #687: one model, declared once, builds its static layout for SQLite
// and for a second dialect. Every generated member the layout uses absorbs
// the dialect, so the call site does not change between the two. Compiled
// with Support/DialectParameterisedSupport.swift.

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
