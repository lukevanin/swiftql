import Foundation
import XCTest

//
// Decodes and validates `MacroRegressionCorpus.json`, the issue #256
// provenance/disposition record for the @SQLTable/@SQLResult macro
// code-generation regression corpus.
//
// Issue #190's `SQLiteConformanceInventory.json` (Tests/
// SwiftQLSQLiteConformanceFixtures/SQLiteConformanceInventory.json) is
// scoped to SQL *syntax* conformance -- its `required_families` are
// select/expression/join/subquery/compound/cte/dml/ddl. Issue #256 is a
// different concern (the generated *Swift* API surface), so this corpus is
// a deliberate sibling record rather than an extension of that inventory;
// see the corpus JSON's own `scope.relationship_to_190` field for the
// documented reasoning. This test only validates the sibling record's own
// internal consistency -- it does not touch the #190 inventory.
//

private struct MacroRegressionCorpus: Decodable {
    let schemaVersion: Int
    let corpusVersion: String
    let coordinationIssue: Int
    let scope: Scope
    let cases: [Case]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case corpusVersion = "corpus_version"
        case coordinationIssue = "coordination_issue"
        case scope
        case cases
    }

    struct Scope: Decodable {
        let claim: String
        let relationshipTo190: String
        let dispositionMeaning: [String: String]
        let provenancePolicy: String

        private enum CodingKeys: String, CodingKey {
            case claim
            case relationshipTo190 = "relationship_to_190"
            case dispositionMeaning = "disposition_meaning"
            case provenancePolicy = "provenance_policy"
        }
    }

    struct Case: Decodable {
        let id: String
        let category: String
        let title: String
        let description: String
        let provenance: Provenance
        let disposition: Disposition
        let gating: Gating?
        let evidence: [Evidence]

        enum Disposition: String, Decodable {
            case supported
            case gated
        }

        struct Provenance: Decodable {
            let inspiration: String
            let upstreamReference: String?
            let licenseNote: String

            private enum CodingKeys: String, CodingKey {
                case inspiration
                case upstreamReference = "upstream_reference"
                case licenseNote = "license_note"
            }
        }

        struct Gating: Decodable {
            let reason: String
            let blockingIssue: Int
            let milestone: String
            let documentedAt: [String]

            private enum CodingKeys: String, CodingKey {
                case reason
                case blockingIssue = "blocking_issue"
                case milestone
                case documentedAt = "documented_at"
            }
        }

        struct Evidence: Decodable {
            let layer: String
            let sourcePath: String
            let testCase: String

            private enum CodingKeys: String, CodingKey {
                case layer
                case sourcePath = "source_path"
                case testCase = "test_case"
            }
        }
    }
}


private enum MacroRegressionCorpusError: Error {
    case missingResource
}


final class MacroRegressionCorpusTests: XCTestCase {

    // Bundled as a processed resource of the SQLMacrosTests target (see
    // Package.swift), mirroring how Tests/SwiftQLSQLiteConformanceFixtures/
    // SQLiteConformanceInventory.json is loaded for the #190 inventory.
    private var corpusURL: URL {
        get throws {
            guard let url = Bundle.module.url(
                forResource: "MacroRegressionCorpus",
                withExtension: "json"
            ) else {
                throw MacroRegressionCorpusError.missingResource
            }
            return url
        }
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadCorpus() throws -> MacroRegressionCorpus {
        let data = try Data(contentsOf: try corpusURL)
        return try JSONDecoder().decode(MacroRegressionCorpus.self, from: data)
    }

    func testCorpusDecodesWithExpectedIdentity() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.coordinationIssue, 256)
        XCTAssertFalse(corpus.corpusVersion.isEmpty)
        XCTAssertFalse(corpus.cases.isEmpty)
    }

    func testCorpusDocumentsItsRelationshipToThe190Inventory() throws {
        let corpus = try loadCorpus()
        // The corpus must explain -- not silently assume -- why it is a
        // sibling record rather than an extension of the #190 SQL-syntax
        // conformance inventory. This pins that a future edit cannot delete
        // that explanation without failing a test.
        XCTAssertTrue(corpus.scope.relationshipTo190.contains("190"))
        XCTAssertTrue(corpus.scope.relationshipTo190.lowercased().contains("syntax"))
    }

    func testEveryCaseIDIsUnique() throws {
        let corpus = try loadCorpus()
        let ids = corpus.cases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate case IDs: \(ids)")
    }

    func testEveryCaseIDIsNamespacedUnderMacro() throws {
        let corpus = try loadCorpus()
        for testCase in corpus.cases {
            XCTAssertTrue(
                testCase.id.hasPrefix("macro."),
                "case ID '\(testCase.id)' is not namespaced under 'macro.'"
            )
        }
    }

    // Every issue-#256-mandated case category must be represented by at
    // least one case, so a future edit that quietly drops a whole category
    // (rather than an individual case) is caught.
    func testEveryRequiredCaseCategoryIsRepresented() throws {
        let corpus = try loadCorpus()
        let categories = Set(corpus.cases.map(\.category))
        let requiredCategories: Set<String> = [
            "reserved-and-escaped-identifiers",
            "unicode-names",
            "keyword-like-properties",
            "optionals",
            "enums-and-supported-custom-values",
            "access-control",
            "generic-nested-contexts",
            "empty-minimal-declarations",
            "many-stored-properties",
            "duplicate-or-conflicting-generated-names",
            "malformed-property-shapes",
            "source-located-diagnostics",
        ]
        let missing = requiredCategories.subtracting(categories)
        XCTAssertTrue(missing.isEmpty, "missing required categories: \(missing.sorted())")
    }

    // A "supported" case must carry real evidence; a "gated" case must name
    // the reason and the issue/milestone tracking the remaining work,
    // rather than either disposition being asserted without backing.
    func testDispositionMatchesEvidenceAndGatingShape() throws {
        let corpus = try loadCorpus()
        for testCase in corpus.cases {
            switch testCase.disposition {
            case .supported:
                XCTAssertFalse(
                    testCase.evidence.isEmpty,
                    "'\(testCase.id)' is supported but carries no evidence"
                )
                XCTAssertNil(
                    testCase.gating,
                    "'\(testCase.id)' is supported but carries a gating record"
                )
            case .gated:
                guard let gating = testCase.gating else {
                    XCTFail("'\(testCase.id)' is gated but carries no gating record")
                    continue
                }
                XCTAssertFalse(gating.reason.isEmpty, "'\(testCase.id)' gating reason is empty")
                XCTAssertGreaterThan(
                    gating.blockingIssue, 0,
                    "'\(testCase.id)' gating.blocking_issue must be a real issue number"
                )
                XCTAssertFalse(gating.milestone.isEmpty, "'\(testCase.id)' gating milestone is empty")
                XCTAssertFalse(
                    gating.documentedAt.isEmpty,
                    "'\(testCase.id)' gating carries no documentation pointers"
                )
            }
        }
    }

    // Every evidence entry must point at a file that actually exists, and
    // name identifiers that actually occur in that file, so a rename or
    // deletion of the referenced test/declaration makes this fail instead
    // of leaving a stale citation.
    func testEveryEvidenceEntryResolvesToRealSourceContainingItsNamedIdentifiers() throws {
        let corpus = try loadCorpus()
        var fileCache: [String: String] = [:]

        func contents(of relativePath: String) throws -> String {
            if let cached = fileCache[relativePath] {
                return cached
            }
            let url = packageRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MacroRegressionCorpusError.missingResource
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            fileCache[relativePath] = text
            return text
        }

        for testCase in corpus.cases {
            for evidence in testCase.evidence {
                XCTAssertFalse(
                    evidence.layer.isEmpty,
                    "'\(testCase.id)' has an evidence entry with an empty layer"
                )
                let text: String
                do {
                    text = try contents(of: evidence.sourcePath)
                }
                catch {
                    XCTFail("'\(testCase.id)' evidence source_path does not exist: \(evidence.sourcePath)")
                    continue
                }
                for token in identifierTokens(in: evidence.testCase) {
                    XCTAssertTrue(
                        text.contains(token),
                        "'\(testCase.id)' evidence test_case token '\(token)' not found in \(evidence.sourcePath)"
                    )
                }
            }
        }
    }

    // A gated case's documentation pointers must resolve to real files too,
    // so a stale citation to already-superseded documentation is caught.
    func testGatedCaseDocumentationPointersResolveToRealFiles() throws {
        let corpus = try loadCorpus()
        for testCase in corpus.cases {
            guard let gating = testCase.gating else { continue }
            for pointer in gating.documentedAt {
                guard let path = pointer.split(separator: " ").first else {
                    XCTFail("'\(testCase.id)' documented_at entry has no leading path: \(pointer)")
                    continue
                }
                let url = packageRoot.appendingPathComponent(String(path))
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: url.path),
                    "'\(testCase.id)' documented_at path does not exist: \(path)"
                )
            }
        }
    }
}


/// Splits free-form evidence text into identifier-like tokens (letters,
/// digits, and underscores), discarding punctuation such as backticks,
/// slashes, and periods used to separate a class name from a method name or
/// a type name from a free-form description.
private func identifierTokens(in text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for character in text {
        if character.isLetter || character.isNumber || character == "_" {
            current.append(character)
        }
        else if !current.isEmpty {
            tokens.append(current)
            current = ""
        }
    }
    if !current.isEmpty {
        tokens.append(current)
    }
    // Common connective words in free-form evidence descriptions carry no
    // identifying information and would otherwise force every source file
    // referenced to contain the literal word "via" or "and".
    let stopWords: Set<String> = ["via", "and"]
    return tokens.filter { !stopWords.contains($0) }
}
