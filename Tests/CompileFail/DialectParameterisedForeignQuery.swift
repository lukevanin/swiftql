import Foundation
import SwiftQL

// Issue #687: a model's layout built for one dialect cannot prepare a query
// on a database of another. The error names both dialects. Compiled with
// Support/DialectParameterisedSupport.swift.

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
