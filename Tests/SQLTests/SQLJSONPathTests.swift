//
//  SQLJSONPathTests.swift
//
//
//  Milestone v1.6, issue #588: the typed JSON path builder. The rendering
//  cases pin the path text for each segment kind. The execution cases run the
//  built path through real SQLite, so a path that renders but does not select
//  the intended element fails here.
//

import Foundation
import XCTest
import GRDB
import SwiftQL


final class XLJSONPathRenderingTests: XCTestCase {

    private var encoder: XLiteEncoder!

    override func setUp() {
        encoder = XLiteEncoder(
            formatter: XLiteFormatter(identifierFormattingOptions: .noEscape)
        )
    }

    override func tearDown() {
        encoder = nil
    }

    // MARK: - Segments

    func testRootRendersAsDollar() {
        XCTAssertEqual(XLJSONPath.root.path, "$")
    }

    func testPlainKeySegmentsRenderUnquoted() {
        XCTAssertEqual(XLJSONPath.root.key("address").path, "$.address")
        XCTAssertEqual(
            XLJSONPath.root.key("address").key("city").path,
            "$.address.city"
        )
    }

    func testIndexSegmentsRenderInBrackets() {
        XCTAssertEqual(XLJSONPath.root.key("items").index(0).path, "$.items[0]")
        XCTAssertEqual(XLJSONPath.root.index(12).path, "$[12]")
    }

    func testCountingBackFromTheEndRendersHashOffset() {
        XCTAssertEqual(XLJSONPath.root.key("items").last.path, "$.items[#-1]")
        XCTAssertEqual(
            XLJSONPath.root.key("items").index(fromEnd: 3).path,
            "$.items[#-3]"
        )
    }

    func testTheAppendPositionRendersAsAHash() {
        XCTAssertEqual(XLJSONPath.root.key("items").appended.path, "$.items[#]")
        XCTAssertEqual(XLJSONPath.root.appended.path, "$[#]")
    }

    func testSegmentsCompose() {
        XCTAssertEqual(
            XLJSONPath.root.key("a").key("b").index(0).key("c").path,
            "$.a.b[0].c"
        )
    }

    // MARK: - Key escaping

    func testAKeyIsQuotedOnlyWhenTheGrammarNeedsIt() {
        // `.` and `[` end an unquoted label, so a key holding either has to
        // be quoted.
        XCTAssertEqual(XLJSONPath.root.key("a.b").path, "$.\"a.b\"")
        XCTAssertEqual(XLJSONPath.root.key("a[0]").path, "$.\"a[0]\"")
        // A `"` or a `\\` does not end a label, so the grammar does not
        // force the quoted form. Quoting one would need an escape, and an
        // escape inside a quoted label needs a newer SQLite. Leaving it
        // unquoted is the better of two spellings, not a portable one: such
        // a key resolves only where the engine unescapes JSON labels either
        // way, which is why the execution cases probe the connection first.
        XCTAssertEqual(XLJSONPath.root.key("a\"b").path, "$.a\"b")
        XCTAssertEqual(XLJSONPath.root.key("a\\b").path, "$.a\\b")
        // `]` and `#` are only special inside brackets.
        XCTAssertEqual(XLJSONPath.root.key("a]b").path, "$.a]b")
        XCTAssertEqual(XLJSONPath.root.key("a#b").path, "$.a#b")
    }

    func testAKeyNeedingBothQuotingAndEscapingIsEscaped() {
        // The one combination that needs a SQLite which unescapes quoted
        // labels: the `.` forces the quoted form, and the `"` then has to be
        // escaped.
        XCTAssertEqual(
            XLJSONPath.root.key("a.b\"c").path,
            "$.\"a.b\\\"c\""
        )
        XCTAssertEqual(
            XLJSONPath.root.key("a.b\\c").path,
            "$.\"a.b\\\\c\""
        )
    }

    func testControlCharactersInAPlainKeyStayAsTheyAre() {
        // A control character does not end an unquoted label, so it needs no
        // escape and no newer SQLite.
        XCTAssertEqual(XLJSONPath.root.key("a\nb").path, "$.a\nb")
        XCTAssertEqual(XLJSONPath.root.key("a\tb").path, "$.a\tb")
    }

    func testControlCharactersInAQuotedKeyUseJSONEscapes() {
        XCTAssertEqual(XLJSONPath.root.key("a.\nb").path, "$.\"a.\\nb\"")
        XCTAssertEqual(XLJSONPath.root.key("a.\tb").path, "$.\"a.\\tb\"")
        XCTAssertEqual(
            XLJSONPath.root.key("a.\u{01}b").path,
            "$.\"a.\\u0001b\""
        )
    }

    func testEmptyAndNonASCIIKeysSurvive() {
        // An empty name has no unquoted spelling, so it is always quoted.
        XCTAssertEqual(XLJSONPath.root.key("").path, "$.\"\"")
        XCTAssertEqual(XLJSONPath.root.key("é").path, "$.é")
    }

    // MARK: - Value semantics

    func testPathsAreEquatableAndHashable() {
        let first = XLJSONPath.root.key("items").index(0)
        let second = XLJSONPath.root.key("items").index(0)
        let third = XLJSONPath.root.key("items").index(1)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(Set([first, second, third]).count, 2)
    }

    func testDescriptionIsThePathText() {
        XCTAssertEqual(String(describing: XLJSONPath.root.key("a")), "$.a")
    }

    // MARK: - Rendering as a SQL operand

    func testPathRendersAsATextOperand() {
        let json = XLNamedBindingReference<String>(name: "json")
        XCTAssertEqual(
            encoder.makeSQL(
                json.jsonArrayLength(path: XLJSONPath.root.key("items"))
            ).sql,
            "json_array_length(:json, '$.items')"
        )
    }

    func testAQuoteInAKeyIsStillEscapedForSQL() {
        // The key holds one double quote and one single quote. The label is
        // unquoted, so the double quote passes through, but the single quote
        // is still escaped for the SQL text literal. A path is a text
        // operand, and it cannot end that operand early.
        let json = XLNamedBindingReference<String>(name: "json")
        XCTAssertEqual(
            encoder.makeSQL(
                json.jsonArrayLength(path: XLJSONPath.root.key("a\"b'c"))
            ).sql,
            "json_array_length(:json, '$.a\"b''c')"
        )
    }

    func testTheStringPathOverloadStillCompiles() {
        // v1 source compatibility: the original spelling keeps working.
        let json = XLNamedBindingReference<String>(name: "json")
        XCTAssertEqual(
            encoder.makeSQL(json.jsonArrayLength(path: "$.items")).sql,
            "json_array_length(:json, '$.items')"
        )
    }
}


final class XLJSONPathExecutionTests: XCTestCase {

    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!

    override func setUp() {
        let formatter = XLiteFormatter(
            identifierFormattingOptions: .mysqlCompatible
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("sqlite")
        databasePool = try! DatabasePool(path: fileURL.path)
        database = try! GRDBDatabase(
            databasePool: databasePool,
            formatter: formatter,
            logger: nil
        )
    }

    override func tearDown() {
        try? databasePool?.close()
        databasePool = nil
        database = nil
    }

    private func document() -> XLNamedBindingReference<String> {
        XLNamedBindingReference<String>(name: "document")
    }

    private func evaluate<Value>(
        _ expression: any XLExpression<Value>,
        document json: String
    ) throws -> Value? where Value: XLLiteral {
        let statement = sql { _ in Select(expression) }
        var request = database.makeRequest(with: statement)
        request.set(document(), json)
        return try request.fetchOne()
    }

    func testABuiltPathSelectsWhatAHandWrittenPathSelects() throws {
        let json = #"{"items":[1,2,3],"other":[1]}"#
        let built = try evaluate(
            document().jsonArrayLength(path: XLJSONPath.root.key("items")),
            document: json
        )
        let handWritten = try evaluate(
            document().jsonArrayLength(path: "$.items"),
            document: json
        )
        XCTAssertEqual(built, 3)
        XCTAssertEqual(built, handWritten)
    }

    func testARootPathSelectsTheWholeDocument() throws {
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root),
                document: "[1,2,3,4]"
            ),
            4
        )
    }

    func testAKeyHoldingADotNamesThatKey() throws {
        // `$.a.b` reads as "b inside a". The built path names the single key
        // `a.b`, which is what the quoted form is for: a `.` in a key is
        // exactly the case the grammar forces it on.
        let json = #"{"a.b":[1,2,3],"a":{"b":[1]}}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key("a.b")),
                document: json
            ),
            3
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: "$.a.b"),
                document: json
            ),
            1
        )
    }

    func testAKeyHoldingBracketsSelectsItsValue() throws {
        // `[` forces the quoted form, and needs no escape once quoted, so
        // this resolves on every supported SQLite.
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key("a[0]")),
                document: #"{"a[0]":[1]}"#
            ),
            1
        )
    }

    func testKeysHoldingQuotesAndBackslashesSelectTheirValues() throws {
        let json = #"{"a\"b":[1,2],"a\\b":[1,2,3]}"#
        try requireRuntimeResolves(document: json, path: #"$.a"b"#)
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key(#"a"b"#)),
                document: json
            ),
            2
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key(#"a\b"#)),
                document: json
            ),
            3
        )
    }

    func testControlCharacterKeysSelectTheirValues() throws {
        let json = #"{"a\nb":[1,2]}"#
        try requireRuntimeResolves(document: json, path: "$.a\nb")
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key("a\nb")),
                document: json
            ),
            2
        )
    }

    func testIndexAndLastSelectArrayElements() throws {
        let json = #"{"rows":[[1],[1,2],[1,2,3]]}"#
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(
                    path: XLJSONPath.root.key("rows").index(1)
                ),
                document: json
            ),
            2
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(
                    path: XLJSONPath.root.key("rows").last
                ),
                document: json
            ),
            3
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(
                    path: XLJSONPath.root.key("rows").index(fromEnd: 3)
                ),
                document: json
            ),
            1
        )
    }

    func testAKeyNeedingBothQuotingAndEscapingWorksWhereSQLiteUnescapes() throws {
        // A key holding both a `.` and a `"` has to be quoted, and the `"`
        // then has to be escaped. Unescaping inside a quoted label is a newer
        // SQLite behaviour: 3.51.0 selects the key, and the 3.43.2 runtime on
        // one CI cell selects nothing. Skip where the runtime cannot do it,
        // so the case is still checked wherever it can be, rather than being
        // dropped from the suite for the oldest runtime's sake.
        try requireRuntimeResolves(
            document: #"{"a.b\"c":[1,2]}"#,
            path: #"$."a.b\"c""#
        )
        XCTAssertEqual(
            try evaluate(
                document().jsonArrayLength(path: XLJSONPath.root.key(#"a.b"c"#)),
                document: #"{"a.b\"c":[1,2]}"#
            ),
            2
        )
    }

    /// Skips the calling test when the connected SQLite does not resolve this
    /// document and path the way SwiftQL renders it.
    ///
    /// A key holding a `"`, a `\`, or a control character has no spelling
    /// that resolves on every supported SQLite. JSON stores such a key
    /// escaped, older engines match a path label against that raw escaped
    /// text, and newer engines unescape both sides first. SwiftQL renders for
    /// the newer behaviour. Asking the connection keeps the boundary visible,
    /// and keeps the case running wherever it can, instead of dropping it for
    /// the oldest runtime's sake or pinning a version this repository cannot
    /// check against every runtime it supports.
    private func requireRuntimeResolves(
        document json: String,
        path: String
    ) throws {
        let resolved = try databasePool.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT json_array_length(?, ?)",
                arguments: [json, path]
            )
        }
        guard resolved != nil else {
            let version = try databasePool.read { database in
                try String.fetchOne(database, sql: "SELECT sqlite_version()")
            } ?? "unknown"
            throw XCTSkip(
                """
                SQLite \(version) does not resolve the path \(path), which \
                needs an engine that unescapes JSON labels.
                """
            )
        }
    }

    func testTheAppendPositionSelectsNothingAndIsWhereAWriteLands() throws {
        // Nothing is one past the end, so a read through `[#]` is NULL. The
        // path exists for writing, which the array length proves after the
        // insert lands.
        let json = #"{"items":[1,2]}"#
        let appendPosition = XLJSONPath.root.key("items").appended
        guard let read = try evaluate(
            document().jsonArrayLength(path: appendPosition),
            document: json
        ) else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(read)

        let appended = try databasePool.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT json_insert(?, ?, 3)",
                arguments: [json, appendPosition.path]
            )
        }
        XCTAssertEqual(appended, #"{"items":[1,2,3]}"#)
    }

    func testAPathThatMatchesNothingIsNull() throws {
        // `evaluate` returns `Value?`, and `Value` is itself `Int?` here, so
        // the row is present and its single column is SQL NULL. Unwrapping
        // the outer optional separates that from "no row at all", and keeps
        // the assertion off a double optional, which XCTAssertNil and
        // XCTAssertNotNil both warn about.
        guard let result = try evaluate(
            document().jsonArrayLength(path: XLJSONPath.root.key("missing")),
            document: #"{"items":[1]}"#
        ) else {
            XCTFail("the statement should return one row")
            return
        }
        XCTAssertNil(result, "the selected column should be SQL NULL")
    }
}
