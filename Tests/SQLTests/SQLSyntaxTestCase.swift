//
//  SQLSyntaxTestCase.swift
//
//  The fixture the syntax-rendering tests share.
//
//  `SQLSyntaxTests.swift` was 2,042 lines, one class, 187 tests, and twenty
//  `// MARK:` sections. Issue #567 split it along those boundaries; every test
//  is a self-contained string assertion, so the split needed no visibility
//  change and no shared state beyond this encoder.
//

import XCTest
import SwiftQL


class XLSyntaxTestCase: XCTestCase {

    var encoder: XLiteEncoder!

    override func setUp() {
        // `.noEscape` so the expected SQL in these tests reads as SQL rather
        // than as a wall of quoting. Identifier escaping has its own coverage.
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .noEscape
        )
        encoder = XLiteEncoder(formatter: formatter)
    }

    override func tearDown() {
        encoder = nil
    }

    ///
    /// Asserts that an expression renders as exactly this SQL.
    ///
    /// One passthrough for every exact-SQL assertion in these files, so a
    /// change to how rendered SQL is compared -- normalising whitespace, say --
    /// is one edit rather than two hundred (issue #567).
    ///
    func assertRenders(
        _ expression: some XLEncodable,
        as sql: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(encoder.makeSQL(expression).sql, sql, file: file, line: line)
    }
}


struct RawRealRenderingProbe: XLEncodable {
    let value: Double

    func makeSQL(context: inout XLBuilder) {
        context.real(value)
    }
}
