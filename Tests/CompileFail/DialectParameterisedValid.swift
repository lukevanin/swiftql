import Foundation
import SwiftQL

// Issue #687: one model builds its static layout for SQLite and for a second
// dialect. Every generated member the layout uses absorbs the dialect, so the
// call site does not change between the two. Since issue #789 a query selects
// the columns of a model declared for its dialect, so the second dialect's
// layout selects the second declaration's columns. Compiled with
// Support/DialectParameterisedSupport.swift.

@SQLBindings(dialect: CompileFailSecondDialect.self)
struct DialectFixtureBindings {
    var code: String
}

func dialectFixtureLayout<Dialect: XLLiteralValueDialect>(
    using dialect: Dialect,
    id: any XLExpression<Int>,
    code: any XLExpression<String>,
    configuration: XLValueCodingConfiguration
) throws -> XLStaticRowLayout<DialectFixtureGauge, Dialect> {
    try DialectFixtureGauge.staticRowLayout(
        using: Dialect.self,
        id: XLStaticSelectField<Int, Int, Dialect>.intrinsic(
            selecting: id,
            identifiedBy: XLQuerySlotIdentity(path: ["gauge", "id"]),
            using: dialect
        ),
        code: DialectFixtureGauge.staticResultField(
            code: code,
            storedAs: String.self,
            identifiedBy: XLQuerySlotIdentity(path: ["gauge", "code"]),
            using: dialect,
            configuration: configuration
        )
    )
}

func bothDialects(configuration: XLValueCodingConfiguration) throws {
    let sqliteGauge = XLSchema().table(DialectFixtureGauge.self)
    let secondGauge = XLSchema(dialect: CompileFailSecondDialect.self)
        .table(SecondDialectFixtureGauge.self)
    let sqlite: XLStaticRowLayout<DialectFixtureGauge, XLSQLiteDialect> = try dialectFixtureLayout(
        using: XLSQLiteDialect(),
        id: sqliteGauge.id,
        code: sqliteGauge.code,
        configuration: configuration
    )
    let second: XLStaticRowLayout<DialectFixtureGauge, CompileFailSecondDialect> = try dialectFixtureLayout(
        using: CompileFailSecondDialect(),
        id: secondGauge.id,
        code: secondGauge.code,
        configuration: configuration
    )
    _ = (sqlite, second)
    let packet: XLInvocationBindings<CompileFailSecondDialectValue> = try DialectFixtureBindings(code: "abc")
        .bindings(in: .empty)
    _ = packet
}
