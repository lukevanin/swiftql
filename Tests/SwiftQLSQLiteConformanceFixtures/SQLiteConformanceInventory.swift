import Foundation


/// The checked-in, versioned description of SwiftQL's public SQLite surface.
///
/// The inventory joins syntax claims, executable evidence, SQLite runtime
/// metadata, planned suites, and adopted value-boundary behavior in one
/// machine-readable source of truth.
public struct SQLiteConformanceInventory: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let inventoryVersion: String
    public let coordinationIssue: Int
    public let scope: Scope
    public let sqliteEnvironments: [SQLiteEnvironment]
    public let evidence: [Evidence]
    public let suites: [Suite]
    public let features: [Feature]

    public struct Scope: Decodable, Equatable, Sendable {
        public let claim: String
        public let limits: [String]
        public let requiredFamilies: [String]

        private enum CodingKeys: String, CodingKey {
            case claim
            case limits
            case requiredFamilies = "required_families"
        }
    }

    public struct SQLiteEnvironment: Decodable, Equatable, Sendable {
        public let id: String
        public let sqliteVersion: String
        public let sqliteSourceID: String
        public let source: String
        public let capturedAt: String
        public let toolchain: String
        public let architecture: String
        public let capabilities: [String]

        private enum CodingKeys: String, CodingKey {
            case id
            case sqliteVersion = "sqlite_version"
            case sqliteSourceID = "sqlite_source_id"
            case source
            case capturedAt = "captured_at"
            case toolchain
            case architecture
            case capabilities
        }
    }

    public struct Evidence: Decodable, Equatable, Sendable {
        public let id: String
        public let sourcePath: String
        public let testCase: String
        public let runnerPath: String?
        public let layers: [Layer]
        public let realSQLite: Bool
        public let environmentIDs: [String]

        public enum Layer: String, CaseIterable, Decodable, Equatable, Sendable {
            case swiftTypecheck = "swift-typecheck"
            case rendering
            case bindings
            case prepare
            case execution
            case compileFail = "compile-fail"
            case structuredError = "structured-error"
            case runtimeMetadata = "runtime-metadata"
            case semanticOracle = "semantic-oracle"
            case observation
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case sourcePath = "source_path"
            case testCase = "test_case"
            case runnerPath = "runner_path"
            case layers
            case realSQLite = "real_sqlite"
            case environmentIDs = "environment_ids"
        }
    }

    public struct Suite: Decodable, Equatable, Sendable {
        public let id: String
        public let issue: Int
        public let milestone: String
        public let status: Status
        public let caseIDs: [String]
        public let evidenceIDs: [String]

        public enum Status: String, CaseIterable, Decodable, Equatable, Sendable {
            case planned
            case completed
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case issue
            case milestone
            case status
            case caseIDs = "case_ids"
            case evidenceIDs = "evidence_ids"
        }
    }

    public struct Feature: Decodable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let family: String
        public let title: String
        public let status: Status
        public let adoptionStatus: AdoptionStatus
        public let publicAPI: [PublicAPI]
        public let sqliteDocumentationURLs: [String]
        public let notSQLiteSyntaxReason: String?
        public let minimumSQLiteVersion: String?
        public let reviewedSQLiteRelease: String
        public let reviewedSQLiteSourceID: String
        public let requiredCapabilities: [String]
        public let schemaRequirements: [String]
        public let evidenceIDs: [String]
        public let deviations: [String]
        public let followUpIssues: [Int]
        public let deferral: Deferral?
        public let provenance: [Provenance]

        public enum Kind: String, CaseIterable, Decodable, Equatable, Sendable {
            case syntax
            case adoptedBehavior = "adopted-behavior"
            case adapterContract = "adapter-contract"
        }

        public enum Status: String, CaseIterable, Decodable, Equatable, Sendable {
            case supported
            case partial
            case capabilityGated = "capability-gated"
            case intentionallyUnsupported = "intentionally-unsupported"
            case unimplemented
        }

        public enum AdoptionStatus:
            String,
            CaseIterable,
            Decodable,
            Equatable,
            Sendable
        {
            case alreadyCovered = "already-covered"
            case adoptableNow = "adoptable-now"
            case syntaxGated = "syntax-gated"
            case adapterAPIGated = "adapter/API-gated"
            case intentionallyOutOfScope = "intentionally-out-of-scope"
        }

        public struct PublicAPI: Decodable, Equatable, Sendable {
            public let symbol: String
            public let sourcePath: String
            public let sourceTokens: [String]

            private enum CodingKeys: String, CodingKey {
                case symbol
                case sourcePath = "source_path"
                case sourceTokens = "source_tokens"
            }
        }

        public struct Deferral: Decodable, Equatable, Sendable {
            public let blockingIssue: Int
            public let targetMilestone: String
            public let reason: String

            private enum CodingKeys: String, CodingKey {
                case blockingIssue = "blocking_issue"
                case targetMilestone = "target_milestone"
                case reason
            }
        }

        public struct Provenance: Decodable, Equatable, Sendable {
            public let repository: String
            public let commit: String
            public let path: String
            public let upstreamCase: String
            public let licenseSPDX: String
            public let licenseFilePath: String
            public let licenseFileURL: String
            public let licenseBlobSHA: String
            public let licenseDisposition: String
            public let copiedMaterial: Bool
            public let noticePath: String?
            public let adaptationNotes: String

            private enum CodingKeys: String, CodingKey {
                case repository
                case commit
                case path
                case upstreamCase = "upstream_case"
                case licenseSPDX = "license_spdx"
                case licenseFilePath = "license_file_path"
                case licenseFileURL = "license_file_url"
                case licenseBlobSHA = "license_blob_sha"
                case licenseDisposition = "license_disposition"
                case copiedMaterial = "copied_material"
                case noticePath = "notice_path"
                case adaptationNotes = "adaptation_notes"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case kind
            case family
            case title
            case status
            case adoptionStatus = "adoption_status"
            case publicAPI = "public_api"
            case sqliteDocumentationURLs = "sqlite_documentation_urls"
            case notSQLiteSyntaxReason = "not_sqlite_syntax_reason"
            case minimumSQLiteVersion = "minimum_sqlite_version"
            case reviewedSQLiteRelease = "reviewed_sqlite_release"
            case reviewedSQLiteSourceID = "reviewed_sqlite_source_id"
            case requiredCapabilities = "required_capabilities"
            case schemaRequirements = "schema_requirements"
            case evidenceIDs = "evidence_ids"
            case deviations
            case followUpIssues = "follow_up_issues"
            case deferral
            case provenance
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case inventoryVersion = "inventory_version"
        case coordinationIssue = "coordination_issue"
        case scope
        case sqliteEnvironments = "sqlite_environments"
        case evidence
        case suites
        case features
    }

    /// Loads the canonical inventory bundled with the conformance fixture
    /// module.
    public static func load() throws -> Self {
        guard let url = Bundle.module.url(
            forResource: "SQLiteConformanceInventory",
            withExtension: "json"
        ) else {
            throw SQLiteConformanceInventoryError.missingResource
        }
        return try decode(contentsOf: url)
    }

    /// Decodes an inventory at an explicit URL, useful to validator clients
    /// and focused decoder tests.
    public static func decode(contentsOf url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}


public enum SQLiteConformanceInventoryError: Error, Equatable {
    case missingResource
}
