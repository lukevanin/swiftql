//
//  SQLSyntaxTestCase.swift
//
//  The fixture the rendering tests share: an encoder, and nothing else.
//
//  Eight suites carried an identical `setUp`/`tearDown` pair building one and
//  clearing it, each forcing an implicitly-unwrapped optional to hold it
//  (issue #557).
//
//  `SQLSyntaxTests.swift` was 2,042 lines, one class, 187 tests, and twenty
//  `// MARK:` sections. Issue #567 split it along those boundaries; every test
//  is a self-contained string assertion, so the split needed no visibility
//  change and no shared state beyond this encoder.
//

import XCTest
import SwiftQL


class XLEncoderTestCase: XCTestCase {

    var encoder: XLiteEncoder!

    /// How identifiers are spelled in the SQL these tests expect. Override in
    /// a subclass that needs a different one.
    class var identifierFormattingOptions: XLSQLiteIdentifierFormattingOptions {
        .sqlite
    }

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(
                identifierFormattingOptions: Self.identifierFormattingOptions
            )
        )
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

class XLSyntaxTestCase: XLEncoderTestCase {

    /// `.noEscape` so the expected SQL in these tests reads as SQL rather than
    /// as a wall of quoting. Identifier escaping has its own coverage.
    override class var identifierFormattingOptions: XLSQLiteIdentifierFormattingOptions {
        .noEscape
    }
}


struct RawRealRenderingProbe: XLEncodable {
    let value: Double

    func makeSQL(context: inout XLBuilder) {
        context.real(value)
    }
}
