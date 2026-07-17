import XCTest
@testable import SwiftQL


private struct DialectCapabilityProbe: XLEncodable {

    let named: Bool

    let indexed: Bool

    func makeSQL(context: inout XLBuilder) {
        if named {
            context.namedBinding("name")
        }
        if indexed {
            context.indexedBinding(2)
        }
        if !named && !indexed {
            context.integer(1)
        }
    }
}


final class SQLDialectEncodingContractTests: XCTestCase {

    func testEncoderDerivesPlaceholderCapabilitiesFromRenderedSQL() {
        let encoder = XLiteEncoder(
            dialect: XLSQLiteDialect(version: XLDialectVersion(3, 46))
        )

        let literal = encoder.makeSQL(
            DialectCapabilityProbe(named: false, indexed: false)
        )
        let named = encoder.makeSQL(
            DialectCapabilityProbe(named: true, indexed: false)
        )
        let indexed = encoder.makeSQL(
            DialectCapabilityProbe(named: false, indexed: true)
        )
        let both = encoder.makeSQL(
            DialectCapabilityProbe(named: true, indexed: true)
        )

        XCTAssertEqual(literal.dialectRequirement.capabilities, [])
        XCTAssertEqual(named.dialectRequirement.capabilities, [.namedBindings])
        XCTAssertEqual(indexed.dialectRequirement.capabilities, [.indexedBindings])
        XCTAssertEqual(
            both.dialectRequirement.capabilities,
            [.namedBindings, .indexedBindings]
        )
        XCTAssertNil(both.dialectRequirement.minimumVersion)
    }

    func testEncodedNamedBindingRejectsDialectWithoutNamedBindings() {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            DialectCapabilityProbe(named: true, indexed: false)
        )
        let unsupported = XLDialectDescriptor(
            identity: XLSQLiteDialect.identity,
            capabilities: [.indexedBindings]
        )

        XCTAssertThrowsError(
            try encoding.dialectRequirement.validate(unsupported)
        ) { error in
            XCTAssertEqual(
                error as? XLDatabaseContractError,
                .capabilityMismatch(
                    dialect: XLSQLiteDialect.identity,
                    required: [.namedBindings],
                    available: [.indexedBindings]
                )
            )
        }
    }
}
