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
        "XLDocumentationTests.testDocumentationREADME",
        XLDocumentationTests.testDocumentationREADME
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationQuickStart",
        XLDocumentationTests.testDocumentationQuickStart
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationStaticQueries",
        XLDocumentationTests.testDocumentationStaticQueries
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
        "XLDocumentationTests.testDocumentationEnumValues",
        XLDocumentationTests.testDocumentationEnumValues
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
        "Enums.md": "XLDocumentationTests.testDocumentationEnumValues",
        "Expressions.md": "XLDocumentationTests.testDocumentationExpressions",
        "FunctionalSyntax.md": "XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations",
        "GenericTableParameters.md": "XLDocumentationTests.testDocumentationGenericTableParameters",
        "GettingStarted.md": "XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings",
        "LiveQueries.md": "XLDocumentationTests.testDocumentationLiveQueryPublishers",
        "Queries.md": "XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs",
        "StaticQueries.md": "XLDocumentationTests.testDocumentationStaticQueries",
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
            Set(expectedMarkerByFile.values).union([
                "XLDocumentationTests.testDocumentationREADME",
            ]),
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

        let readme = repositoryRootURL().appendingPathComponent("README.md")
        try assertExampleCoverage(
            in: String(contentsOf: readme, encoding: .utf8),
            file: readme.lastPathComponent,
            expectedTest: "XLDocumentationTests.testDocumentationREADME"
        )
    }

    func testGettingStartedDocumentsPreparedStatementOwnershipAndFailureSemantics() throws {
        let gettingStartedURL = documentationCatalogURL()
            .appendingPathComponent("GettingStarted.md")
        let contents = try String(contentsOf: gettingStartedURL, encoding: .utf8)

        for heading in [
            "#### Dialect and driver responsibilities",
            "#### Logical and physical preparation",
            "#### Transactions and bindings",
        ] {
            XCTAssertTrue(contents.contains(heading), "GettingStarted.md is missing \(heading).")
        }

        for semanticPhrase in [
            "database- or pool-bound",
            "depend directly on the `SwiftQLCore` library product",
            "Physical GRDB statements are connection-bound",
            "separately on that leased connection",
            "reuse its own statement cache",
            "must not re-enter the root pool",
            "fresh bindings",
            "current `XLRequest` facade itself is not `Sendable`",
            "Its `GRDBPreparedInvocation` result is",
            "not the same as SQL `NULL`",
            "normalize transport failures",
            "keeps raw `DatabaseError` and `XLColumnReadError`",
            "fail later on a newly leased connection",
        ] {
            XCTAssertTrue(
                contents.contains(semanticPhrase),
                "GettingStarted.md is missing prepared-statement guidance for '\(semanticPhrase)'."
            )
        }
    }

    func testStaticQueriesDocumentsIdentityPreparationAndExecutionContracts() throws {
        let staticQueriesURL = documentationCatalogURL()
            .appendingPathComponent("StaticQueries.md")
        let contents = try String(
            contentsOf: staticQueriesURL,
            encoding: .utf8
        )

        for heading in [
            "## Construct a descriptor",
            "## Stable identity",
            "### Definition versions and registries",
            "## Prepare and invoke",
            "### Intrinsic and contextual slots",
            "### Cardinality",
        ] {
            XCTAssertTrue(contents.contains(heading), "StaticQueries.md is missing \(heading).")
        }

        for semanticPhrase in [
            "construct and register descriptors before opening a database",
            "one flat `XLStaticQueryResultSlot`",
            "`staticRowLayout(using:...)` factories",
            "Exact rendered SQL bytes",
            "deliberately excludes invocation values",
            "Metadata strings that participate in identity use Unicode NFC normalization",
            "Rendered SQL is different: it remains exact UTF-8",
            "different canonical material",
            "`XLStaticQueryError.definitionIdentityCollision`",
            "descriptor registry can be a value-semantic collection",
            "retains that exact configuration snapshot",
            "fresh `XLInvocationBindings` packet for every call",
            "Intrinsic `Bool`, `Int`, `Double`, `String`, and `Data` slots",
            "| `.command` | `execute(bindings:)` |",
            "| `.exactlyOne` | `fetchExactlyOneValues(bindings:)` |",
            "| `.zeroOrOne` | `fetchZeroOrOneValues(bindings:)` |",
            "| `.many` | `fetchAllValues(bindings:)` |",
        ] {
            XCTAssertTrue(
                contents.contains(semanticPhrase),
                "StaticQueries.md is missing static-query guidance for '\(semanticPhrase)'."
            )
        }
    }

    func testCustomTypesDocumentsContextualCodecPolicyAndV1Migration() throws {
        let customTypesURL = documentationCatalogURL()
            .appendingPathComponent("CustomTypes.md")
        let contents = try String(contentsOf: customTypesURL, encoding: .utf8)

        for heading in [
            "## Contextual value codecs",
            "### Selection and errors",
            "### SQL NULL and optional values",
            "### Contextual parameters and invocation packets",
            "## Legacy `XLCustomType` wrappers",
            "## Migrating v1 literals",
        ] {
            XCTAssertTrue(contents.contains(heading), "CustomTypes.md is missing \(heading).")
        }

        for semanticPhrase in [
            "same Swift type without changing `Date` itself",
            "There is no process-global registry",
            "becomes a database default only when its key is listed",
            "Treat changes to a codec key or version",
            "Codec selection uses one deterministic order",
            "The first populated tier is authoritative",
            "first resolve and validate the selected codec",
            "The codec closure never receives either optional state",
            "resolves the codec once from that database's",
            "is missing a binding",
            "compatibility invocation packet",
            "`XLV1LiteralCodec` exposes an existing `Sendable` `XLLiteral` implementation",
            "This is a compatibility bridge",
        ] {
            XCTAssertTrue(
                contents.contains(semanticPhrase),
                "CustomTypes.md is missing contextual-codec guidance for '\(semanticPhrase)'."
            )
        }
    }

    func testREADMERepositoryLinksResolveWithExactCase() throws {
        let repositoryRoot = repositoryRootURL()
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let expression = try NSRegularExpression(pattern: #"\[[^\]]+\]\(([^)]+)\)"#)
        let range = NSRange(readme.startIndex ..< readme.endIndex, in: readme)
        let repositoryLinks = expression.matches(in: readme, range: range).compactMap { match -> String? in
            guard
                let destinationRange = Range(match.range(at: 1), in: readme)
            else {
                return nil
            }
            let destination = String(readme[destinationRange])
            guard !destination.contains("://"), !destination.hasPrefix("#") else {
                return nil
            }
            return destination
        }

        XCTAssertEqual(
            Set(repositoryLinks),
            [
                "BENCHMARKS.md",
                "COMPATIBILITY.md",
                "Coverage/README.md",
                "LICENSE.md",
                "RELEASING.md",
                "ROADMAP.md",
            ]
        )
        for link in repositoryLinks {
            XCTAssertTrue(
                try pathExistsWithExactCase(link, below: repositoryRoot),
                "README link does not resolve with exact case: \(link)"
            )
        }
    }

    func testTrackedSwiftFileHeadersMatchFilenames() throws {
        let repositoryRoot = repositoryRootURL()
        for directoryName in ["IntegrationTests", "Sources", "Tests"] {
            let directory = repositoryRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else {
                XCTFail("Unable to enumerate \(directory.path)")
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let lines = try String(contentsOf: fileURL, encoding: .utf8)
                    .components(separatedBy: .newlines)
                    .prefix(10)
                guard let header = lines.first(where: {
                    $0.hasPrefix("//  ") && $0.hasSuffix(".swift")
                }) else {
                    continue
                }
                XCTAssertEqual(
                    String(header.dropFirst(4)),
                    fileURL.lastPathComponent,
                    "Stale file header in \(fileURL.path)"
                )
            }
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
        repositoryRootURL()
            .appendingPathComponent("Sources/SwiftQL/SwiftQL.docc", isDirectory: true)
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func pathExistsWithExactCase(_ path: String, below root: URL) throws -> Bool {
        var directory = root
        let components = path.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() {
            let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard entries.contains(component) else {
                return false
            }
            if index < components.count - 1 {
                directory.appendPathComponent(component, isDirectory: true)
            }
        }
        return true
    }
}
