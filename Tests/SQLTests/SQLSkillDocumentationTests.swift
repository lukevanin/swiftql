import Foundation
import XCTest


final class SQLSkillDocumentationTests: XCTestCase {

    func testSkillUsesCurrentCodexMetadataAndBoundedInstructions() throws {
        let contents = try skillContents()
        let lines = contents.components(separatedBy: .newlines)
        let normalizedContents = normalizedWhitespace(contents)

        XCTAssertEqual(lines.first, "---")
        guard let closingFrontmatter = lines.dropFirst().firstIndex(of: "---") else {
            return XCTFail("SKILL.md must close its YAML frontmatter.")
        }
        let metadata = Array(lines[1 ..< closingFrontmatter])
        XCTAssertEqual(
            metadata.filter { $0.hasPrefix("name:") },
            ["name: swiftql"]
        )
        XCTAssertEqual(metadata.filter { $0.hasPrefix("description:") }.count, 1)
        XCTAssertEqual(
            metadata.filter { $0.contains(":") }.count,
            2,
            "Codex skill metadata must contain only name and description."
        )
        XCTAssertLessThan(lines.count, 220, "Keep the repository skill concise.")

        for forbidden in [
            "/Users/",
            "/Applications/",
            "DEVELOPER_DIR=",
            "sudo ",
            "rm -",
            "git clean",
            "git reset",
        ] {
            XCTAssertFalse(contents.contains(forbidden), "SKILL.md contains '\(forbidden)'.")
        }

        for required in [
            "https://github.com/lukevanin/swiftql.git",
            "`SwiftQLCore` only when implementing a dialect or database adapter",
            "fresh immutable `XLInvocationBindings<XLSQLiteValue>` packet",
            "`XLStaticQueryDescriptor`",
            "runtime Swift values are not inferred from bare variables",
            "`XLValueCodec`",
            "`XLInvocationBindingError` and `XLRequestBindingError`",
            "Do not invent a high-level `GRDBDatabase.transaction` API",
            "`sqlCreate` is not a migration engine",
            "SwiftQL exposes no general raw-fragment API",
            "`XLRequest` across tasks; it is not `Sendable`",
            "Swift 5.9 and Swift 6.0-6.3 evidence",
        ] {
            XCTAssertTrue(
                normalizedContents.contains(required),
                "SKILL.md is missing '\(required)'."
            )
        }
    }

    func testEverySwiftSnippetIsTheCompiledConsumerFixture() throws {
        let skill = try skillContents()
        let sourceURL = repositoryRootURL().appendingPathComponent(
            "IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/SkillQuickStart.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let expected = try text(
            between: "// swiftql-skill-example-begin\n",
            and: "\n// swiftql-skill-example-end",
            in: source
        )

        XCTAssertEqual(
            skill.components(separatedBy: "```swift\n").count - 1,
            1,
            "Every added Swift fence needs an explicit compiled fixture."
        )
        let actual = try text(between: "```swift\n", and: "\n```", in: skill)
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(
            skill.contains(
                "<!-- compile-test: IntegrationTests/Swift5Client/Sources/SwiftQLSwift5Client/SkillQuickStart.swift -->"
            )
        )
    }

    func testSkillLinksResolveAndCommandsStayRepositoryRelative() throws {
        let root = repositoryRootURL()
        let contents = try skillContents()

        for path in ["README.md", "CHANGELOG.md", "COMPATIBILITY.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
            XCTAssertTrue(contents.contains("](\(path))"), "SKILL.md must link \(path).")
        }
        for canonicalURL in [
            "https://lukevanin.github.io/swiftql/documentation/swiftql/staticqueries/",
            "https://lukevanin.github.io/swiftql/documentation/swiftql/customtypes/",
            "https://lukevanin.github.io/swiftql/documentation/swiftql/gettingstarted/",
        ] {
            XCTAssertTrue(contents.contains(canonicalURL))
        }

        let shell = try text(between: "```sh\n", and: "\n```", in: contents)
        XCTAssertEqual(
            shell.components(separatedBy: .newlines),
            [
                "swift test --filter SQLSkillDocumentationTests",
                "scripts/ci/check-downstream-swift5-client.sh committed",
                "swift test",
                "./make-docs.sh docs",
                "scripts/ci/check-first-party-warnings.sh",
                "scripts/ci/check-strict-concurrency.sh",
            ]
        )
    }

    private func skillContents() throws -> String {
        try String(
            contentsOf: repositoryRootURL().appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
    }

    private func text(
        between opening: String,
        and closing: String,
        in contents: String
    ) throws -> String {
        guard
            let start = contents.range(of: opening)?.upperBound,
            let end = contents.range(of: closing, range: start ..< contents.endIndex)?.lowerBound
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return String(contents[start ..< end])
    }

    private func normalizedWhitespace(_ contents: String) -> String {
        contents
            .split(whereSeparator: { $0.isWhitespace })
            .map { "\($0)" }
            .joined(separator: " ")
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
