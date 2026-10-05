import Foundation
import SwiftQL

// Issue #687: a field built for one dialect cannot join a layout for another.
// The error names both dialects. Compiled with
// Support/DialectParameterisedSupport.swift.

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
