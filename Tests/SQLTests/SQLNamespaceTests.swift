import XCTest

@testable import SwiftQL


final class XLNamespaceTests: XCTestCase {

    func testAutomaticAliasesSkipExplicitAliases() {
        let namespace = XLNamespace.table()

        XCTAssertEqual(namespace.makeAlias(alias: "t0"), "t0")
        XCTAssertEqual(namespace.makeAlias(alias: "t1"), "t1")
        XCTAssertEqual(namespace.makeAlias(alias: nil), "t2")
    }

    func testAutomaticAliasesSkipMultipleNoncontiguousAliases() {
        let namespace = XLNamespace.table()

        XCTAssertEqual(namespace.makeAlias(alias: "t0"), "t0")
        XCTAssertEqual(namespace.makeAlias(alias: "t2"), "t2")
        XCTAssertEqual(namespace.makeAlias(alias: "t4"), "t4")
        XCTAssertEqual(namespace.makeAlias(alias: nil), "t1")
        XCTAssertEqual(namespace.makeAlias(alias: nil), "t3")
        XCTAssertEqual(namespace.makeAlias(alias: nil), "t5")
    }

    func testAutomaticAliasesTreatExplicitAliasesAsCaseInsensitive() {
        let namespace = XLNamespace.table()

        XCTAssertEqual(namespace.makeAlias(alias: "T0"), "T0")
        XCTAssertEqual(namespace.makeAlias(alias: nil), "t1")
    }

    func testAutomaticAliasesRemainFiniteWithConstantNameFormat() {
        let namespace = XLNamespace.table()
        namespace.nameFormat = "alias"

        XCTAssertEqual(namespace.makeAlias(alias: nil), "alias")
        XCTAssertEqual(namespace.makeAlias(alias: nil), "alias0")
    }
}
