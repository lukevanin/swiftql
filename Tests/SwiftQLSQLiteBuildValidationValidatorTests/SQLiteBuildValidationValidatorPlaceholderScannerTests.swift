//
//  SQLiteBuildValidationValidatorPlaceholderScannerTests.swift
//
//  The lexical placeholder scan the validator runs over a manifest query's SQL
//  before preparing it: which spellings become physical parameters, which
//  collide, which are unsupported, and which text is not scanned at all.
//
//  Ported from the research prototype when `Research/SQLiteBuildValidation`
//  was retired (issue #565). The shipped scanner had no tests of its own; the
//  quoting rules in particular -- string literals, quoted identifiers,
//  bracketed identifiers, line and block comments -- are exactly where a scan
//  invents or loses a parameter without any query failing to prepare.
//

import XCTest

@testable import SwiftQLSQLiteBuildValidationValidator


final class SQLiteBuildValidationValidatorPlaceholderScannerTests: XCTestCase {
    func testRecognizesNamedIndexedGapsAndRepeatedNamesWhileIgnoringQuotedText() {
        let analysis = SQLiteBuildValidationValidatorPlaceholderScanner.scan(
            """
            SELECT ?3, :later, :later, ?1,
                   ':string', "?:identifier", `:quoted`, [?:bracket]
            -- :line_comment ?8
            /* :block_comment ?9 */
            """
        )

        XCTAssertEqual(analysis.physicalParameterCount, 4)
        XCTAssertEqual(analysis.parameters, [
            SQLitePreparedParameter(physicalIndex: 1, name: "?1"),
            SQLitePreparedParameter(physicalIndex: 2, name: nil),
            SQLitePreparedParameter(physicalIndex: 3, name: "?3"),
            SQLitePreparedParameter(physicalIndex: 4, name: ":later"),
        ])
        XCTAssertEqual(
            analysis.occurrences.map(\.spelling),
            ["?3", ":later", ":later", "?1"]
        )
        XCTAssertEqual(
            analysis.occurrences.map(\.physicalIndex),
            [3, 4, 4, 1]
        )
        XCTAssertEqual(analysis.unsupported, [])
        XCTAssertEqual(analysis.collisions, [])
    }

    func testRecordsCollisionsAndUnsupportedPlaceholderSpellings() {
        let analysis = SQLiteBuildValidationValidatorPlaceholderScanner.scan(
            "SELECT :first, ?1, ?, @other, $cash, ?0"
        )

        XCTAssertEqual(analysis.physicalParameterCount, 1)
        XCTAssertEqual(
            analysis.collisions,
            ["Physical parameter 1 is named by both ':first' and '?1'."]
        )
        XCTAssertEqual(
            analysis.unsupported.map(\.spelling),
            ["?", "@other", "$cash", "?0"]
        )
        XCTAssertTrue(analysis.unsupported.allSatisfy { !$0.reason.isEmpty })
    }
}
