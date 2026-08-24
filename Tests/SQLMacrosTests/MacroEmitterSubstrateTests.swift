//
//  MacroEmitterSubstrateTests.swift
//  SwiftQL
//
//  Direct coverage of the pieces every macro builder emits through (issue
//  #563): the `CodeWriter` code writer, the `GeneratedIdentifierAllocator`
//  collision-avoidance algorithm, the validating `makeDecl` parse, and the
//  string-literal escaping in `quoted`.
//
//  Both `CodeWriter` and `GeneratedIdentifierAllocator` had no tests of their
//  own. Every assertion about them was indirect, through a whole macro
//  expansion snapshot, where an indentation or collision bug reads as a diff in
//  generated Swift rather than as the behaviour that produced it. That is a
//  poor safety net for the `MetaBuilder` split (#564), which moves the emit
//  half wholesale.
//

import SwiftSyntax
import XCTest

@testable import SQLMacros


final class CodeWriterTests: XCTestCase {

    func testLinesAreIndentedOneLevel() {
        var writer = CodeWriter()
        writer.line("let foo = 12")
        writer.line("let bar = 13")

        XCTAssertEqual(writer.build(), "  let foo = 12\n  let bar = 13")
    }

    /// The example from `block`'s own documentation.
    func testBlockWrapsContentsAndIndentsThemOneFurtherLevel() {
        var writer = CodeWriter()
        writer.block("makeFoo() -> Int") { writer in
            writer.line("return 42")
        }

        XCTAssertEqual(
            writer.build(),
            """
              makeFoo() -> Int {
                return 42
              }
            """.trimmingCharacters(in: .newlines)
        )
    }

    /// Each nesting level adds exactly one indentation unit, and the closing
    /// delimiter sits at the level of the line that opened it -- the property
    /// that makes generated source readable when a macro is inspected.
    func testNestedBlocksIndentCumulativelyAndCloseAtTheOpeningLevel() {
        var writer = CodeWriter(indentation: "    ")
        writer.block("struct Foo") { writer in
            writer.block("func bar()") { writer in
                writer.line("baz()")
            }
        }

        XCTAssertEqual(
            writer.build(),
            """
            struct Foo {
                func bar() {
                    baz()
                }
            }
            """.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
        )
    }

    func testBlockHonorsCustomOpeningAndClosingDelimiters() {
        var writer = CodeWriter()
        writer.block("Foo", opening: "(", closing: ")") { writer in
            writer.line("name: 42")
        }

        XCTAssertEqual(writer.build(), "  Foo(\n    name: 42\n  )")
    }

    /// The separator goes on the *previous* item, never after the last one, so
    /// the result is a well-formed argument list rather than one with a
    /// trailing comma in a position Swift rejects.
    ///
    /// List items land two indentation levels below their opening line rather
    /// than one -- `list` indents through its own writer and again when the
    /// lines are appended. That is cosmetic and is what every committed
    /// expansion snapshot already shows, so it is pinned here rather than
    /// changed.
    func testDeclarationSeparatesItemsWithoutATrailingSeparator() {
        var writer = CodeWriter()
        writer.declaration("Foo") { list in
            list.item { writer in
                writer.line("name: 42")
            }
            list.item { writer in
                writer.line("other: 43")
            }
        }

        XCTAssertEqual(
            writer.build(),
            "  Foo(\n      name: 42,\n      other: 43\n  )"
        )
    }

    /// A multi-line item takes the separator on its last line, which is where
    /// the next item continues from.
    func testMultiLineListItemsTakeTheSeparatorOnTheirFinalLine() {
        var writer = CodeWriter()
        writer.declaration("Foo") { list in
            list.item { writer in
                writer.line("first: 1")
                writer.line("second: 2")
            }
            list.item { writer in
                writer.line("third: 3")
            }
        }

        XCTAssertEqual(
            writer.build(),
            "  Foo(\n      first: 1\n      second: 2,\n      third: 3\n  )"
        )
    }

    func testEmptyWriterBuildsAnEmptyString() {
        XCTAssertEqual(CodeWriter().build(), "")
    }
}


final class GeneratedIdentifierAllocatorTests: XCTestCase {

    func testAnUncontestedBaseIsHandedOutUnchanged() {
        var allocator = GeneratedIdentifierAllocator(used: [])

        XCTAssertEqual(allocator.allocate("row"), "row")
    }

    /// The names already in scope are the whole point: a generated `row` beside
    /// an author's `row` is a redeclaration.
    func testACollidingBaseTakesTheLowestFreeSuffix() {
        var allocator = GeneratedIdentifierAllocator(used: ["row", "row_1"])

        XCTAssertEqual(allocator.allocate("row"), "row_2")
    }

    /// Allocation is not a pure function of its argument: each name handed out
    /// joins the used set, so repeating a base yields a fresh identifier every
    /// time rather than the same one twice.
    func testRepeatedAllocationsOfOneBaseNeverAgree() {
        var allocator = GeneratedIdentifierAllocator(used: [])

        XCTAssertEqual(
            (0 ..< 4).map { _ in allocator.allocate("value") },
            ["value", "value_1", "value_2", "value_3"]
        )
    }

    /// A suffixed name that was reserved up front is skipped rather than
    /// reissued, so the algorithm cannot walk into a collision it was given.
    func testSuffixedNamesAlreadyInUseAreSkipped() {
        var allocator = GeneratedIdentifierAllocator(used: ["value_1", "value_3"])

        XCTAssertEqual(
            (0 ..< 3).map { _ in allocator.allocate("value") },
            ["value", "value_2", "value_4"]
        )
    }

    func testDistinctBasesDoNotInterfere() {
        var allocator = GeneratedIdentifierAllocator(used: ["row"])

        XCTAssertEqual(allocator.allocate("row"), "row_1")
        XCTAssertEqual(allocator.allocate("column"), "column")
    }
}


final class MacroDeclarationEmissionTests: XCTestCase {

    func testWellFormedSourceParsesToADeclaration() throws {
        let declaration = try makeDecl("let value: Int = 42")

        XCTAssertEqual(declaration.trimmedDescription, "let value: Int = 42")
    }

    /// `DeclSyntax(stringLiteral:)` accepts anything and leaves error nodes in
    /// the tree, so without this check a generation bug reaches the compiler as
    /// a pile of errors about source the author never wrote. The thrown error
    /// carries the offending source, which is what makes it a bug report.
    func testMalformedSourceThrowsAndCarriesTheGeneratedSource() {
        let source = "func broken( -> {"

        XCTAssertThrowsError(try makeDecl(source)) { error in
            guard
                case .invalidGeneratedCode(let reported) =
                    error as? SQLMacroError
            else {
                return XCTFail("Expected invalidGeneratedCode, received \(error)")
            }
            XCTAssertEqual(reported, source)
            XCTAssertTrue(
                SQLMacroError.invalidGeneratedCode(source)
                    .description.contains(source)
            )
        }
    }
}


final class MacroQuotedLiteralTests: XCTestCase {

    func testAnOrdinaryNameIsSurroundedByQuotes() {
        XCTAssertEqual(quoted("Customers"), "\"Customers\"")
    }

    /// The issue #563 case. A raw-string `name:` argument carries no escapes,
    /// so its represented value can hold a quote or a backslash; emitting one
    /// unescaped produced generated source that did not parse.
    func testQuotesAndBackslashesAreEscaped() {
        XCTAssertEqual(quoted("my\"table"), "\"my\\\"table\"")
        XCTAssertEqual(quoted("back\\slash"), "\"back\\\\slash\"")
        XCTAssertEqual(quoted("both\\\"here"), "\"both\\\\\\\"here\"")
    }

    func testControlCharactersAreEscapedRatherThanEmittedLiterally() {
        XCTAssertEqual(quoted("two\nlines"), "\"two\\nlines\"")
        XCTAssertEqual(quoted("a\tb"), "\"a\\tb\"")
        XCTAssertEqual(quoted("a\rb"), "\"a\\rb\"")
        XCTAssertEqual(quoted("a\0b"), "\"a\\0b\"")
    }

    /// The real property: whatever goes in comes back out of the Swift parser
    /// unchanged, for every case above.
    func testEscapedLiteralsRoundTripThroughTheParser() throws {
        for name in [
            "Customers",
            "my\"table",
            "back\\slash",
            "both\\\"here",
            "two\nlines",
            "a\tb",
        ] {
            let declaration = try makeDecl("let name = \(quoted(name))")
            let literal = try XCTUnwrap(
                declaration.as(VariableDeclSyntax.self)?
                    .bindings.first?
                    .initializer?.value
                    .as(StringLiteralExprSyntax.self),
                "Expected a string literal for \(name.debugDescription)"
            )
            XCTAssertEqual(
                literal.representedLiteralValue,
                name,
                name.debugDescription
            )
        }
    }
}
