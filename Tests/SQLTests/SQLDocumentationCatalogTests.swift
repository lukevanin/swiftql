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


private struct DocumentationConformanceInventory: Decodable {

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

    let features: [Feature]
    let evidence: [Evidence]
    let sqliteEnvironments: [SQLiteEnvironment]

    enum CodingKeys: String, CodingKey {
        case features
        case evidence
        case sqliteEnvironments = "sqlite_environments"
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
        "XLDocumentationTests.testDocumentationAdvancedUsage",
        XLDocumentationTests.testDocumentationAdvancedUsage
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationExpressions",
        XLDocumentationTests.testDocumentationExpressions
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationRealValues",
        XLDocumentationTests.testDocumentationRealValues
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
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationDeclaredQueries",
        XLDocumentationTests.testDocumentationDeclaredQueries
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationNumericDateCodecs",
        XLDocumentationTests.testDocumentationNumericDateCodecs
    ),
    DocumentationTestReference(
        "XLDocumentationTests.testDocumentationTutorialEndToEndQuery",
        XLDocumentationTests.testDocumentationTutorialEndToEndQuery
    ),
]


final class SQLDocumentationCatalogTests: XCTestCase {

    private let expectedMarkerByFile = [
        "AdvancedUsage.md": "XLDocumentationTests.testDocumentationAdvancedUsage",
        "BuiltinFunctions.md": "XLDocumentationTests.testDocumentationConditionalAndScalarFunctions",
        "CustomFunctions.md": "XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution",
        "CustomTypes.md": "XLDocumentationTests.testDocumentationCustomTypeRoundTrips",
        "DeclaredQueries.md": "XLDocumentationTests.testDocumentationDeclaredQueries",
        "Enums.md": "XLDocumentationTests.testDocumentationEnumValues",
        "Expressions.md": "XLDocumentationTests.testDocumentationExpressions",
        "FunctionalSyntax.md": "XLDocumentationTests.testDocumentationFunctionalQueriesAndMutations",
        "GenericTableParameters.md": "XLDocumentationTests.testDocumentationGenericTableParameters",
        "GettingStarted.md": "XLDocumentationTests.testDocumentationGettingStartedCRUDAndBindings",
        "LiveQueries.md": "XLDocumentationTests.testDocumentationLiveQueryPublishers",
        "NumericDateCodecs.md": "XLDocumentationTests.testDocumentationNumericDateCodecs",
        "Queries.md": "XLDocumentationTests.testDocumentationQueriesJoinsAggregatesPaginationSubqueriesCompoundsAndCTEs",
        "RealValues.md": "XLDocumentationTests.testDocumentationRealValues",
        "StaticQueries.md": "XLDocumentationTests.testDocumentationStaticQueries",
        "SwiftQL.md": "XLDocumentationTests.testDocumentationQuickStart",
    ]

    /// Tutorial pages carry no Markdown fences, so instead of a `<!-- test:
    /// -->` marker each one names the compiled walkthrough its `@Code(file:)`
    /// snapshots are cut from, and the scenario that runs the last snapshot.
    private let expectedTutorialWalkthroughByFile = [
        "EndToEndQuery.tutorial": TutorialWalkthrough(
            source: "Tests/SQLTests/SQLTutorialWalkthrough.swift",
            marker: "swiftql-tutorial-walkthrough",
            expectedTest: "XLDocumentationTests.testDocumentationTutorialEndToEndQuery"
        ),
    ]

    /// A tutorial page with no code of its own. It only lists the tutorials
    /// that do have code, so there is nothing to check against a walkthrough.
    private let tableOfContentsTutorialFiles: Set<String> = ["SwiftQL.tutorial"]

    struct TutorialWalkthrough {
        let source: String
        let marker: String
        let expectedTest: String
    }

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
            Set(expectedMarkerByFile.values)
                .union(expectedTutorialWalkthroughByFile.values.map(\.expectedTest))
                .union([
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

    /// The Markdown coverage check above cannot see tutorials, because a
    /// `.tutorial` page shows code through `@Code(file:)` resources instead of
    /// fenced examples. This is the same contract for those resources: every
    /// snapshot a reader sees is cut from source the package compiles, the
    /// snapshots only ever grow, and the last one is the compiled walkthrough
    /// in full.
    func testEveryTutorialCodeSnapshotIsCutFromCompiledSource() throws {
        let catalog = documentationCatalogURL()
        let tutorialURLs = try tutorialFileURLs(in: catalog)
        XCTAssertEqual(
            Set(tutorialURLs.map(\.lastPathComponent)),
            Set(expectedTutorialWalkthroughByFile.keys)
                .union(tableOfContentsTutorialFiles),
            "Update the tutorial registry when the source catalog changes."
        )

        var referencedResources: Set<String> = []
        for tutorialURL in tutorialURLs {
            let file = tutorialURL.lastPathComponent
            let contents = try String(contentsOf: tutorialURL, encoding: .utf8)

            for image in imageDirectives(in: contents) {
                referencedResources.insert(image.source)
                XCTAssertFalse(
                    image.alt.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(file) references \(image.source) without alternative text."
                )
                XCTAssertGreaterThan(
                    image.alt.split(separator: " ").count,
                    5,
                    "\(file) gives \(image.source) alternative text too short to describe it."
                )
            }

            let codeSnapshots = codeDirectives(in: contents)
            guard let walkthrough = expectedTutorialWalkthroughByFile[file] else {
                XCTAssertTrue(
                    codeSnapshots.isEmpty,
                    "\(file) shows code but is registered as a table of contents."
                )
                continue
            }

            XCTAssertFalse(
                codeSnapshots.isEmpty,
                "\(file) must show at least one code snapshot."
            )
            XCTAssertEqual(
                Set(codeSnapshots.map(\.file)).count,
                codeSnapshots.count,
                "\(file) shows the same snapshot more than once."
            )
            XCTAssertEqual(
                codeSnapshots.map(\.file),
                codeSnapshots.map(\.file).sorted(),
                "\(file) shows its snapshots out of order."
            )
            referencedResources.formUnion(codeSnapshots.map(\.file))

            let walkthroughSource = try String(
                contentsOf: repositoryRootURL()
                    .appendingPathComponent(walkthrough.source),
                encoding: .utf8
            )
            XCTAssertTrue(
                walkthroughSource.contains(file),
                "\(walkthrough.source) must name the tutorial it feeds."
            )
            XCTAssertTrue(
                walkthroughSource.contains(walkthrough.expectedTest),
                "\(walkthrough.source) must name \(walkthrough.expectedTest)."
            )

            let compiled = try markedRegion(
                named: walkthrough.marker,
                in: walkthroughSource,
                source: walkthrough.source
            )
            var previous: [String] = []
            var previousName = ""
            for snapshot in codeSnapshots {
                let resourceURL = try resourceURL(named: snapshot.file, in: catalog)
                let lines = try String(contentsOf: resourceURL, encoding: .utf8)
                    .components(separatedBy: "\n")
                    .dropLast()
                XCTAssertFalse(lines.isEmpty, "\(snapshot.file) is empty.")
                XCTAssertTrue(
                    isOrderedSubsequence(Array(lines), of: compiled),
                    "\(snapshot.file) contains lines that are not in \(walkthrough.source)."
                )
                XCTAssertTrue(
                    isOrderedSubsequence(previous, of: Array(lines)),
                    "\(snapshot.file) drops lines that \(previousName) already showed."
                )
                if !previousName.isEmpty {
                    XCTAssertGreaterThan(
                        lines.count,
                        previous.count,
                        "\(snapshot.file) adds nothing to \(previousName)."
                    )
                }
                previous = Array(lines)
                previousName = snapshot.file
            }
            XCTAssertEqual(
                previous,
                compiled,
                "\(previousName) must be the whole \(walkthrough.marker) region of \(walkthrough.source)."
            )
        }

        let resources = try FileManager.default.contentsOfDirectory(
            at: catalog.appendingPathComponent("Tutorials/Resources", isDirectory: true),
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        XCTAssertEqual(
            Set(resources),
            referencedResources,
            "Every tutorial resource must be referenced by exactly the tutorials that ship it."
        )
        for resource in resources {
            XCTAssertTrue(
                try pathExistsWithExactCase(
                    "Sources/SwiftQL/SwiftQL.docc/Tutorials/Resources/\(resource)",
                    below: repositoryRootURL()
                ),
                "Tutorial resource does not resolve with exact case: \(resource)"
            )
        }
    }

    /// The execution-model contract moved out of `GettingStarted.md` so the
    /// onboarding guide stays an onboarding guide. Every heading and phrase
    /// this test pinned there is still pinned — on the article that now owns
    /// it.
    func testAdvancedUsageDocumentsPreparedStatementOwnershipAndFailureSemantics() throws {
        let advancedUsageURL = documentationCatalogURL()
            .appendingPathComponent("AdvancedUsage.md")
        let contents = try String(contentsOf: advancedUsageURL, encoding: .utf8)

        for heading in [
            "## Dialect and driver responsibilities",
            "## Logical and physical preparation",
            "## Incremental row lifetime",
            "## Transactions and bindings",
            "## Typed multi-statement transaction scopes",
        ] {
            XCTAssertTrue(contents.contains(heading), "AdvancedUsage.md is missing \(heading).")
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
            "normalize transport failures",
            "keeps raw `DatabaseError` and `XLColumnReadError`",
            "fail later on a newly leased connection",
        ] {
            XCTAssertTrue(
                contents.contains(semanticPhrase),
                "AdvancedUsage.md is missing prepared-statement guidance for '\(semanticPhrase)'."
            )
        }
    }

    /// The onboarding guide keeps the everyday contract a first-time reader
    /// needs, and keeps pointing at the advanced article for the rest.
    func testGettingStartedStaysAnOnboardingGuide() throws {
        let gettingStartedURL = documentationCatalogURL()
            .appendingPathComponent("GettingStarted.md")
        let contents = try String(contentsOf: gettingStartedURL, encoding: .utf8)

        for heading in [
            "## Defining tables",
            "## Executing statements",
            "## Inserting data",
            "## Running select queries",
            "## Named bindings",
            "## Update statements",
            "## Delete statements",
            "## Grouping work in a transaction",
            "## Where to go next",
        ] {
            XCTAssertTrue(contents.contains(heading), "GettingStarted.md is missing \(heading).")
        }

        for semanticPhrase in [
            "not the same as SQL `NULL`",
            "<doc:AdvancedUsage>",
        ] {
            XCTAssertTrue(
                contents.contains(semanticPhrase),
                "GettingStarted.md is missing onboarding guidance for '\(semanticPhrase)'."
            )
        }

        for relocatedPhrase in [
            "Physical GRDB statements are connection-bound",
            "must not re-enter the root pool",
            "normalize transport failures",
        ] {
            XCTAssertFalse(
                contents.contains(relocatedPhrase),
                "GettingStarted.md regained execution-model depth that belongs in AdvancedUsage.md: '\(relocatedPhrase)'."
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
            "### Property-level codec selection",
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
            "`@SQLCodec` declares that choice on the property itself",
            "It is metadata only",
            "it never wraps the property",
            "a generated `staticResultField(_:...)` convenience per annotated",
            "`@SQLCodec` selects among registered codecs, it does not",
        ] {
            XCTAssertTrue(
                contents.contains(semanticPhrase),
                "CustomTypes.md is missing contextual-codec guidance for '\(semanticPhrase)'."
            )
        }
    }

    func testV13PublicDocumentsShareReleaseAndBoundaryContract() throws {
        let repositoryRoot = repositoryRootURL()
        let inventory = try JSONDecoder().decode(
            DocumentationConformanceInventory.self,
            from: Data(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Tests/SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json"
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
        let environmentCount = inventory.sqliteEnvironments.count
        let environmentCountText = environmentCount == 1
            ? "one"
            : String(environmentCount)
        let environmentNoun = environmentCount == 1
            ? "environment"
            : "environments"
        let sqliteVersions = Set(
            inventory.sqliteEnvironments.map(\.sqliteVersion)
        ).sorted().joined(separator: ", ")
        let supportedCount = statusCounts["supported", default: 0]
        let partialCount = statusCounts["partial", default: 0]
        let capabilityGatedCount = statusCounts["capability-gated", default: 0]
        let intentionallyUnsupportedCount = statusCounts[
            "intentionally-unsupported",
            default: 0
        ]
        let unimplementedCount = statusCounts["unimplemented", default: 0]
        XCTAssertEqual(
            statusCounts.values.reduce(0, +),
            inventory.features.count,
            "Every inventory feature must contribute to the documented status totals."
        )

        let requiredPhrasesByPath = [
            "README.md": [
                "`1.5.5` is the latest published package",
            ],
            "COMPATIBILITY.md": [
                "## v1.3 public products and runtime boundaries",
                "iOS 16 or later and macOS 13 or later",
                "SwiftSyntax 509.0.0, GRDB 6.29.3",
                "The high-level `XLRequest` facade",
                "only a SQLite dialect and a GRDB database driver",
                "seven release-blocking compiler cells",
                "It ships no",
                "public validator, build plugin, macro, schema system, or new v1.3 API",
            ],
            "CHANGELOG.md": [
                "## [1.3.0] - 2026-07-20",
                "141 stable generated",
                "deliberately broken-renderer",
                "internal research, not a",
                "No migration is required for v1.3",
                "## [1.2.0] - 2026-07-19",
            ],
            "RELEASING.md": [
                "states the procedure once, version-neutrally",
                "close the milestone with no open issues",
                "$matches[0].state == \"closed\"",
                "$matches[0].open_issues == 0",
                "It is not proof that any later milestone is ready",
                "must contain all seven",
                "release-blocking compiler cells",
                "Protect v-prefixed release tags",
                "A merge commit is mandatory.",
                "fails the reachability gate",
                "dedicated release issue for",
            ],
            "Sources/SwiftQL/SwiftQL.docc/SwiftQL.md": [
                "## v1.3 conformance evidence",
                "database-independent query definitions",
                "`SwiftQLCore` contains the GRDB-free",
                "The current `XLRequest` facade is",
                "not a claim of complete SQLite",
                "v1.3 does not ship a public",
                "validator, build plugin, query macro, schema system",
                "Version 1.5.5 is the latest published package",
            ],
            "Sources/SwiftQL/SwiftQL.docc/GettingStarted.md": [
                "Version 1.5.5 is the published package",
                "This guide's basic request path remains",
                "from version 1.2.0 or later",
            ],
            "Sources/SwiftQL/SwiftQL.docc/AdvancedUsage.md": [
                "research-only schema-snapshot preparation prototype",
                "perform physical preparation on the runtime",
            ],
            "Sources/SwiftQL/SwiftQL.docc/StaticQueries.md": [
                "### Build-validation research boundary",
                "not a public SwiftQL",
                "product or API",
                "runtime execution still",
                "prepares or retrieves a cached physical statement",
            ],
            "scripts/ci/check-docc-output.sh": [
                "realvalues|Real Values",
                "staticqueries|Static queries",
            ],
        ]
        let inventoryPhrasesByPath = [
            "COMPATIBILITY.md": [
                "The v1.3 inventory contains \(inventory.features.count) feature records and \(inventory.evidence.count) evidence records",
                "| Supported | \(supportedCount) |",
                "| Partial | \(partialCount) |",
                "| Capability-gated | \(capabilityGatedCount) |",
                "| Intentionally unsupported | \(intentionallyUnsupportedCount) |",
                "| Unimplemented | \(unimplementedCount) |",
                "Of those \(inventory.evidence.count) evidence records, \(realSQLiteEvidenceCount) exercise real SQLite",
                "cite \(environmentCountText) captured \(environmentNoun), SQLite \(sqliteVersions)",
            ],
            "CHANGELOG.md": [
                "\(inventory.features.count) public-surface feature records: \(supportedCount)",
                "supported, \(partialCount) partial, \(capabilityGatedCount) capability-gated, \(intentionallyUnsupportedCount) intentionally unsupported, and",
                "\(unimplementedCount) unimplemented",
                "Of the \(inventory.evidence.count) evidence records, \(realSQLiteEvidenceCount) exercise real SQLite",
                "cite \(environmentCountText) captured SQLite \(sqliteVersions) \(environmentNoun)",
            ],
        ]

        for (path, requiredPhrases) in requiredPhrasesByPath {
            let contents = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            for phrase in requiredPhrases {
                XCTAssertTrue(
                    contents.contains(phrase),
                    "\(path) is missing the v1.3 contract phrase '\(phrase)'."
                )
            }
        }
        for (path, inventoryPhrases) in inventoryPhrasesByPath {
            let contents = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            for phrase in inventoryPhrases {
                XCTAssertTrue(
                    contents.contains(phrase),
                    "\(path) is stale against the canonical inventory phrase '\(phrase)'."
                )
            }
        }

        let changelog = try String(
            contentsOf: repositoryRoot.appendingPathComponent("CHANGELOG.md"),
            encoding: .utf8
        )
        let firstReleaseHeading = changelog
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("## [") })
        XCTAssertEqual(firstReleaseHeading, "## [1.5.5] - 2026-07-30")
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
                "CHANGELOG.md",
                "COMPATIBILITY.md",
                "COMPATIBILITY.md#sqlite-conformance-inventory",
                "Coverage/README.md",
                "Documentation/DESIGN.md",
                "Documentation/PortingFromSQL.md",
                "LICENSE.md",
                "RELEASING.md",
                "ROADMAP.md",
                "WHATSNEW.md",
            ]
        )
        for link in repositoryLinks {
            let components = link.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let path = String(components[0])
            XCTAssertTrue(
                try pathExistsWithExactCase(path, below: repositoryRoot),
                "README link does not resolve with exact case: \(path)"
            )
            if components.count == 2 {
                let fragment = String(components[1])
                let contents = try String(
                    contentsOf: repositoryRoot.appendingPathComponent(path),
                    encoding: .utf8
                )
                let anchors = Set(
                    contents
                        .components(separatedBy: .newlines)
                        .compactMap(markdownHeadingAnchor)
                )
                XCTAssertTrue(
                    anchors.contains(fragment),
                    "README link does not resolve to a heading: \(link)"
                )
            }
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

    private func tutorialFileURLs(in catalog: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: catalog,
            includingPropertiesForKeys: nil
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "tutorial" }
            .sorted { $0.path < $1.path }
    }

    private func resourceURL(named name: String, in catalog: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: catalog,
            includingPropertiesForKeys: nil
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        let matches = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == name }
        // DocC resolves `@Code(file:)` and `@Image(source:)` by file name
        // alone, so a name that matches twice is ambiguous in the built site
        // even though both files exist.
        XCTAssertEqual(matches.count, 1, "\(name) does not resolve to one catalog resource.")
        return try XCTUnwrap(matches.first)
    }

    private func markedRegion(
        named marker: String,
        in contents: String,
        source: String
    ) throws -> [String] {
        let lines = contents.components(separatedBy: "\n")
        let begin = lines.firstIndex(of: "// \(marker)-begin")
        let end = lines.firstIndex(of: "// \(marker)-end")
        let start = try XCTUnwrap(begin, "\(source) is missing // \(marker)-begin.")
        let finish = try XCTUnwrap(end, "\(source) is missing // \(marker)-end.")
        XCTAssertLessThan(start, finish, "\(source) closes \(marker) before it opens it.")
        return Array(lines[(start + 1) ..< finish])
    }

    private func isOrderedSubsequence(_ candidate: [String], of whole: [String]) -> Bool {
        var index = whole.startIndex
        for line in candidate {
            guard let match = whole[index...].firstIndex(of: line) else {
                return false
            }
            index = whole.index(after: match)
        }
        return true
    }

    private func codeDirectives(in contents: String) -> [(name: String, file: String)] {
        let expression = try? NSRegularExpression(
            pattern: #"@Code\(name: "([^"]+)", file: ([^)\s]+)\)"#
        )
        return matches(of: expression, in: contents).map {
            (name: $0[0], file: $0[1])
        }
    }

    private func imageDirectives(in contents: String) -> [(source: String, alt: String)] {
        let expression = try? NSRegularExpression(
            pattern: #"@Image\(source: ([^,\s]+), alt: "([^"]*)"\)"#
        )
        return matches(of: expression, in: contents).map {
            (source: $0[0], alt: $0[1])
        }
    }

    private func matches(
        of expression: NSRegularExpression?,
        in contents: String
    ) -> [[String]] {
        guard let expression else {
            return []
        }
        let range = NSRange(contents.startIndex ..< contents.endIndex, in: contents)
        return expression.matches(in: contents, range: range).map { match in
            (1 ..< match.numberOfRanges).compactMap { group in
                Range(match.range(at: group), in: contents).map { String(contents[$0]) }
            }
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

    private func markdownHeadingAnchor(_ line: String) -> String? {
        let heading = line.drop(while: { $0 == "#" })
        guard heading.count < line.count, heading.first == " " else {
            return nil
        }

        var anchor = ""
        for scalar in heading.dropFirst().lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                anchor.unicodeScalars.append(scalar)
            } else if CharacterSet.whitespaces.contains(scalar) {
                anchor.append("-")
            }
        }
        return anchor.isEmpty ? nil : anchor
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
