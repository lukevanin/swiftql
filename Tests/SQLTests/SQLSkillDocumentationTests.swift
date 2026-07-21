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
            "checked-out public v1 contract",
            "1.3.0 is the latest published package and adds conformance evidence rather than new public syntax or validation APIs",
            "`1.3.0` is the latest published package",
            "Keep those five statuses distinct",
            "recorded SQLite version, source ID, compile options, capabilities",
            "#132 remains package-private research",
            "neither persists prepared statements nor removes runtime preparation",
            "Swift 5.9 and Swift 6.0-6.3 evidence",
        ] {
            XCTAssertTrue(
                normalizedContents.contains(required),
                "SKILL.md is missing '\(required)'."
            )
        }
    }

    func testV13GuidanceMatchesCanonicalConformanceInventory() throws {
        let inventory = try JSONDecoder().decode(
            SkillConformanceInventory.self,
            from: Data(
                contentsOf: repositoryRootURL().appendingPathComponent(
                    "Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json"
                )
            )
        )
        let combinatorialManifest = try JSONDecoder().decode(
            SkillCombinatorialManifest.self,
            from: Data(
                contentsOf: repositoryRootURL().appendingPathComponent(
                    "Conformance/SQLite/COMBINATORIAL_CASES.json"
                )
            )
        )
        let statusCounts = Dictionary(
            grouping: inventory.features,
            by: \.status
        ).mapValues(\.count)
        let realSQLiteEvidenceCount = inventory.evidence.filter {
            $0.realSQLite
        }.count
        let environmentCountText = inventory.sqliteEnvironments.count == 1
            ? "one"
            : String(inventory.sqliteEnvironments.count)
        let environmentNoun = inventory.sqliteEnvironments.count == 1
            ? "environment"
            : "environments"
        let sqliteVersions = Set(
            inventory.sqliteEnvironments.map(\.sqliteVersion)
        ).sorted().joined(separator: ", ")
        let supportedCount = statusCounts["supported", default: 0]
        let partialCount = statusCounts["partial", default: 0]
        let capabilityGatedCount = statusCounts[
            "capability-gated",
            default: 0
        ]
        let intentionallyUnsupportedCount = statusCounts[
            "intentionally-unsupported",
            default: 0
        ]
        let unimplementedCount = statusCounts["unimplemented", default: 0]
        let combinatorialSuite = try XCTUnwrap(
            inventory.suites.first { $0.issue == 191 }
        )
        let functionOverloadSuite = try XCTUnwrap(
            inventory.suites.first { $0.issue == 286 }
        )
        let northwindSuite = try XCTUnwrap(
            inventory.suites.first { $0.issue == 254 }
        )
        let observationSuite = try XCTUnwrap(
            inventory.suites.first { $0.issue == 255 }
        )
        let normalizedContents = normalizedWhitespace(try skillContents())

        XCTAssertEqual(
            statusCounts.values.reduce(0, +),
            inventory.features.count,
            "Every inventory feature must contribute to the skill's status totals."
        )
        for suite in [
            combinatorialSuite,
            functionOverloadSuite,
            northwindSuite,
            observationSuite,
        ] {
            XCTAssertEqual(suite.status, "completed")
        }
        let issue286CaseCount = combinatorialManifest.cases.filter {
            $0.id.hasPrefix("c286.v1.expression.")
        }.count
        let issue287CaseCount = combinatorialManifest.cases.filter {
            $0.id.hasPrefix("c287.v1.expression.")
        }.count
        let issue288CaseCount = combinatorialManifest.cases.filter {
            $0.id.hasPrefix("c288.v1.subquery.")
        }.count
        let issue191CaseCount = combinatorialManifest.cases.count
            - issue286CaseCount
            - issue287CaseCount
            - issue288CaseCount
        XCTAssertTrue(
            combinatorialSuite.evidenceIDs.contains(
                "evidence.combinatorial.broken-renderer.sqlite"
            )
        )
        for required in [
            "It records \(inventory.features.count) feature records: "
                + "\(supportedCount) supported, \(partialCount) partial, "
                + "\(capabilityGatedCount) capability-gated, "
                + "\(intentionallyUnsupportedCount) intentionally unsupported, "
                + "and \(unimplementedCount) unimplemented.",
            "Of the \(inventory.evidence.count) evidence records, "
                + "\(realSQLiteEvidenceCount) exercise real SQLite against "
                + "\(environmentCountText) captured \(environmentNoun), SQLite "
                + "\(sqliteVersions).",
            "Evidence is reusable, so evidence and feature counts do not map one to one",
            "The generated corpus holds \(combinatorialManifest.cases.count) "
                + "positives plus one broken-renderer control: "
                + "\(issue191CaseCount) from #191, \(issue286CaseCount) from #286, "
                + "\(issue287CaseCount) from #287, and \(issue288CaseCount) from "
                + "#288. #254 adds \(northwindSuite.caseIDs.count) Northwind and "
                + "#255 adds \(observationSuite.caseIDs.count) "
                + "observation-stress cases",
            "It ships no public validator, build plugin, query macro, schema system, or new v1.3 API. It neither persists prepared statements nor removes runtime preparation on a physical connection.",
        ] {
            XCTAssertTrue(
                normalizedContents.contains(required),
                "SKILL.md is stale against the canonical inventory phrase '\(required)'."
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

        for path in [
            "README.md",
            "CHANGELOG.md",
            "COMPATIBILITY.md",
            "Conformance/SQLite/REPORT.md",
            "Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json",
        ] {
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
        XCTAssertTrue(
            contents.contains(
                "](COMPATIBILITY.md#sqlite-conformance-inventory)"
            )
        )

        let shell = try text(between: "```sh\n", and: "\n```", in: contents)
        XCTAssertEqual(
            shell.components(separatedBy: .newlines),
            [
                "swift test --filter SQLSkillDocumentationTests",
                "python3 scripts/ci/sqlite-conformance-inventory.py check",
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


private struct SkillConformanceInventory: Decodable {

    struct Feature: Decodable {
        let status: String
    }

    struct Evidence: Decodable {
        let realSQLite: Bool

        enum CodingKeys: String, CodingKey {
            case realSQLite = "real_sqlite"
        }
    }

    struct SQLiteEnvironment: Decodable {
        let sqliteVersion: String

        enum CodingKeys: String, CodingKey {
            case sqliteVersion = "sqlite_version"
        }
    }

    struct Suite: Decodable {
        let issue: Int
        let status: String
        let caseIDs: [String]
        let evidenceIDs: [String]

        enum CodingKeys: String, CodingKey {
            case issue
            case status
            case caseIDs = "case_ids"
            case evidenceIDs = "evidence_ids"
        }
    }

    let features: [Feature]
    let evidence: [Evidence]
    let sqliteEnvironments: [SQLiteEnvironment]
    let suites: [Suite]

    enum CodingKeys: String, CodingKey {
        case features
        case evidence
        case sqliteEnvironments = "sqlite_environments"
        case suites
    }
}


private struct SkillCombinatorialManifest: Decodable {

    struct Case: Decodable {
        let id: String
    }

    let cases: [Case]
}
