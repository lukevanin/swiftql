import Foundation
import XCTest


private struct DocumentationTestReference {

    let name: String

    init(
        _ name: String,
        _ test: @escaping (XLDocumentationTests) -> () throws -> Void
    ) {
        self.name = name
        _ = test
    }
}


private let documentationTests = [
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationQuickStart",
        XLDocumentationTests.testDocumentationQuickStart
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings",
        XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationExpressions",
        XLDocumentationTests.testDocumentationExpressions
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations",
        XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationGenericTableParameters",
        XLDocumentationTests.testDocumentationGenericTableParameters
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationCustomTypeRoundTrips",
        XLDocumentationTests.testDocumentationCustomTypeRoundTrips
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution",
        XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationConditionalAndScalarFunctions",
        XLDocumentationTests.testDocumentationConditionalAndScalarFunctions
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs",
        XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationLiveQueryPublishers",
        XLDocumentationTests.testDocumentationLiveQueryPublishers
    ),
]


final class SQLDocumentationCatalogTests: XCTestCase {

    private let expectedMarkerByFile = [
        "BuiltinFunctions.md": "XLDocumentationTests.testDocumentationConditionalAndScalarFunctions",
        "CustomFunctions.md": "XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution",
        "CustomTypes.md": "XLDocumentationTests.testDocumentationCustomTypeRoundTrips",
        "Expressions.md": "XLDocumentationTests.testDocumentationExpressions",
        "FunctionalSyntax.md": "XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations",
        "GenericTableParameters.md": "XLDocumentationTests.testDocumentationGenericTableParameters",
        "GettingStarted.md": "XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings",
        "LiveQueries.md": "XLDocumentationTests.testDocumentationLiveQueryPublishers",
        "Queries.md": "XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs",
        "SwiftQL.md": "XLDocumentationTests.testDocumentationQuickStart",
    ]

    func testEverySwiftExampleMapsToACompiledDocumentationScenario() throws {
        let catalog = documentationCatalogURL()
        let articleURLs = try FileManager.default.contentsOfDirectory(
            at: catalog,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }

        XCTAssertEqual(
            Set(articleURLs.map(\.lastPathComponent)),
            Set(expectedMarkerByFile.keys),
            "Update the documentation example registry when the source catalog changes."
        )
        XCTAssertEqual(
            Set(documentationTests.map(\.name)),
            Set(expectedMarkerByFile.values),
            "Every marker must target a compile-time-checked documentation scenario."
        )

        for articleURL in articleURLs.sorted(by: { $0.path < $1.path }) {
            let contents = try String(contentsOf: articleURL, encoding: .utf8)
            try assertExampleCoverage(
                in: contents,
                file: articleURL.lastPathComponent,
                expectedTest: try XCTUnwrap(expectedMarkerByFile[articleURL.lastPathComponent])
            )
        }
    }

    private func assertExampleCoverage(
        in contents: String,
        file: String,
        expectedTest: String
    ) throws {
        let lines = contents.components(separatedBy: .newlines)
        let expectedMarker = "<!-- test: \(expectedTest) -->"
        var activeFenceLanguage: String?
        var lastNonemptyLine: String?
        var markerCount = 0
        var swiftExampleCount = 0

        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            if activeFenceLanguage != nil {
                if line == "```" {
                    activeFenceLanguage = nil
                }
                continue
            }

            guard line.hasPrefix("```") else {
                if line.hasPrefix("<!-- test:") {
                    markerCount += 1
                    XCTAssertEqual(
                        line,
                        expectedMarker,
                        "\(file):\(lineNumber) has an unknown documentation-test marker."
                    )
                }
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    lastNonemptyLine = line
                }
                continue
            }

            let language = String(line.dropFirst(3))
            XCTAssertFalse(
                language.isEmpty,
                "\(file):\(lineNumber) has an untyped code fence. Label it swift, sql, or text."
            )
            XCTAssertEqual(
                line,
                "```\(language.trimmingCharacters(in: .whitespaces))",
                "\(file):\(lineNumber) has a malformed code-fence language tag."
            )
            XCTAssertTrue(
                ["swift", "sql", "text"].contains(language),
                "\(file):\(lineNumber) has unsupported code-fence language '\(language)'."
            )
            activeFenceLanguage = language

            if language == "swift" {
                swiftExampleCount += 1
                XCTAssertEqual(
                    lastNonemptyLine,
                    expectedMarker,
                    "\(file):\(lineNumber) must map to \(expectedTest)."
                )
            }
        }

        XCTAssertNil(activeFenceLanguage, "\(file) has an unterminated code fence.")
        XCTAssertGreaterThan(swiftExampleCount, 0, "\(file) must retain executable Swift examples.")
        XCTAssertEqual(
            markerCount,
            swiftExampleCount,
            "\(file) must have exactly one test marker for every Swift example."
        )
        XCTAssertFalse(contents.contains("result {"), "\(file) uses the deprecated result helper.")

        for staleName in [
            "SQLCustomFunction",
            "SQLCustomType",
            "SQLEquatable",
            "SQLComparable",
            "SQLNamedBindingReference",
        ] {
            XCTAssertFalse(contents.contains(staleName), "\(file) uses stale API name \(staleName).")
        }
    }

    private func documentationCatalogURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftQL/SwiftQL.docc", isDirectory: true)
    }
}
