import Foundation
import XCTest

import SwiftQLCore


final class SQLDialectContractTests: XCTestCase {

    func testSQLiteIdentityPlaceholdersAndQualifiedIdentifiers() {
        let dialect = XLSQLiteDialect(identifierFormattingOptions: .sqlite)

        XCTAssertEqual(dialect.descriptor.identity, XLSQLiteDialect.identity)
        XCTAssertEqual(dialect.formatPlaceholder(.named("personID")), ":personID")
        XCTAssertEqual(dialect.formatPlaceholder(.indexed(0)), "?1")
        XCTAssertEqual(dialect.formatPlaceholder(.indexed(4)), "?5")
        XCTAssertEqual(dialect.formatIdentifier(#"a"b"#), #""a""b""#)
        XCTAssertEqual(
            dialect.formatQualifiedIdentifier(["schema.with.dot", "table name"]),
            #""schema.with.dot"."table name""#
        )
    }

    func testEveryLegacyCompatibleSQLiteIdentifierModeEscapesSafely() {
        XCTAssertEqual(
            XLSQLiteDialect(identifierFormattingOptions: .noEscape)
                .formatIdentifier("main.StaticTable"),
            "main.StaticTable"
        )
        XCTAssertEqual(
            XLSQLiteDialect(identifierFormattingOptions: .sqlite)
                .formatIdentifier(#"a"b"#),
            #""a""b""#
        )
        XCTAssertEqual(
            XLSQLiteDialect(identifierFormattingOptions: .mysqlCompatible)
                .formatIdentifier("a`b"),
            "`a``b`"
        )
        XCTAssertEqual(
            XLSQLiteDialect(identifierFormattingOptions: .microsoftCompatible)
                .formatIdentifier("ordinary"),
            "[ordinary]"
        )
        XCTAssertEqual(
            XLSQLiteDialect(identifierFormattingOptions: .microsoftCompatible)
                .formatIdentifier(#"a]"b"#),
            #""a]""b""#
        )
    }

    func testAllSQLiteStorageClassesHaveValueSemanticRepresentations() {
        let values: [(XLSQLiteValue, XLSQLiteStorageClass)] = [
            (.null, .null),
            (.integer(Int64.min), .integer),
            (.real(-42.75), .real),
            (.text("nul\u{0} unicode 🧪"), .text),
            (.blob(Data([0x00, 0x7f, 0xff])), .blob),
        ]

        XCTAssertEqual(Set(values.map(\.1)), Set(XLSQLiteStorageClass.allCases))
        for (value, storageClass) in values {
            XCTAssertEqual(value.storageType, storageClass)
            XCTAssertEqual(value, value)
            XCTAssertEqual(value.hashValue, value.hashValue)
        }
        XCTAssertEqual(XLSQLiteValue.integer(Int64.max), .integer(9_223_372_036_854_775_807))
        XCTAssertEqual(XLSQLiteValue.blob(Data()), .blob(Data()))
    }

    func testRequirementAcceptsMatchingIdentityVersionAndCapabilities() throws {
        let requirement = XLDialectRequirement(
            identity: XLSQLiteDialect.identity,
            minimumVersion: XLDialectVersion(3, 35),
            capabilities: [.namedBindings, .indexedBindings]
        )
        let descriptor = XLDialectDescriptor(
            identity: XLSQLiteDialect.identity,
            version: XLDialectVersion(3, 46, 1),
            capabilities: XLSQLiteDialect.standardCapabilities.union(
                XLDialectCapabilities(rawValue: 1 << 40)
            )
        )

        XCTAssertNoThrow(try requirement.validate(descriptor))
        XCTAssertLessThan(XLDialectVersion(3, 46), XLDialectVersion(3, 46, 1))
    }

    func testRequirementReportsDialectVersionAndCapabilityFailures() {
        let requiredCapabilities: XLDialectCapabilities = [
            .namedBindings,
            .indexedBindings,
        ]
        let requirement = XLDialectRequirement(
            identity: XLSQLiteDialect.identity,
            minimumVersion: XLDialectVersion(3, 40),
            capabilities: requiredCapabilities
        )

        assertError(
            try requirement.validate(
                XLDialectDescriptor(
                    identity: XLDialectIdentifier(rawValue: "postgresql"),
                    version: XLDialectVersion(16),
                    capabilities: requiredCapabilities
                )
            ),
            equals: .dialectMismatch(
                expected: XLSQLiteDialect.identity,
                actual: XLDialectIdentifier(rawValue: "postgresql")
            )
        )
        assertError(
            try requirement.validate(
                XLDialectDescriptor(
                    identity: XLSQLiteDialect.identity,
                    version: XLDialectVersion(3, 39),
                    capabilities: requiredCapabilities
                )
            ),
            equals: .versionMismatch(
                dialect: XLSQLiteDialect.identity,
                minimum: XLDialectVersion(3, 40),
                actual: XLDialectVersion(3, 39)
            )
        )
        assertError(
            try requirement.validate(
                XLDialectDescriptor(
                    identity: XLSQLiteDialect.identity,
                    version: XLDialectVersion(3, 40),
                    capabilities: [.namedBindings]
                )
            ),
            equals: .capabilityMismatch(
                dialect: XLSQLiteDialect.identity,
                required: requiredCapabilities,
                available: [.namedBindings]
            )
        )
    }

    func testASecondDialectCanExposeNativeValuesOutsideSQLiteStorageClasses() {
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000131")!
        let dialect = NativeTestDialect()
        let value = NativeTestValue.uuid(uuid)

        XCTAssertEqual(dialect.descriptor.identity.rawValue, "native-test")
        XCTAssertEqual(value.storageType, .uuid)
        XCTAssertEqual(value, .uuid(uuid))
        XCTAssertEqual(dialect.formatPlaceholder(.indexed(0)), "$1")
    }

    private func assertError<T>(
        _ expression: @autoclosure () throws -> T,
        equals expected: XLDatabaseContractError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? XLDatabaseContractError, expected, file: file, line: line)
        }
    }
}


private enum NativeTestStorage: Hashable, Sendable {
    case uuid
    case json
}


private enum NativeTestValue: XLDialectValue {
    case uuid(UUID)
    case json(String)

    var storageType: NativeTestStorage {
        switch self {
        case .uuid:
            return .uuid
        case .json:
            return .json
        }
    }
}


private struct NativeTestDialect: XLSQLDialect {

    typealias Value = NativeTestValue

    let descriptor = XLDialectDescriptor(
        identity: XLDialectIdentifier(rawValue: "native-test"),
        version: XLDialectVersion(1),
        capabilities: [.indexedBindings]
    )

    func formatIdentifier(_ identifier: String) -> String {
        "\"\(identifier)\""
    }

    func formatQualifiedIdentifier(_ components: [String]) -> String {
        components.map(formatIdentifier).joined(separator: ".")
    }

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        switch placeholder {
        case .named(let name):
            return "$\(name)"
        case .indexed(let index):
            return "$\(index + 1)"
        }
    }
}
