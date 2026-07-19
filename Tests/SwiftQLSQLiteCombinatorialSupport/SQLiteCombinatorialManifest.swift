import Foundation
import SwiftQL


/// A checked-in or archived description of one deterministic combinatorial run.
///
/// The manifest deliberately excludes wall-clock, host, and elapsed-time fields.
/// Its canonical JSON bytes are therefore suitable for content-addressed replay.
public struct SQLiteCombinatorialManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatorVersion: String
    public let issue: Int
    public let inventoryVersion: String
    public let hardBounds: SQLiteCombinatorialHardBounds
    public let dimensions: [SQLiteCombinatorialManifestDimension]
    public let constraints: [SQLiteCombinatorialManifestConstraint]
    public let exclusions: [SQLiteCombinatorialManifestExclusion]
    public let coverage: [SQLiteCombinatorialManifestCoverage]
    public let cases: [SQLiteCombinatorialCase]

    public init(
        schemaVersion: Int,
        generatorVersion: String,
        issue: Int,
        inventoryVersion: String,
        hardBounds: SQLiteCombinatorialHardBounds,
        dimensions: [SQLiteCombinatorialManifestDimension],
        constraints: [SQLiteCombinatorialManifestConstraint],
        exclusions: [SQLiteCombinatorialManifestExclusion],
        coverage: [SQLiteCombinatorialManifestCoverage],
        cases: [SQLiteCombinatorialCase]
    ) {
        self.schemaVersion = schemaVersion
        self.generatorVersion = generatorVersion
        self.issue = issue
        self.inventoryVersion = inventoryVersion
        self.hardBounds = hardBounds
        self.dimensions = dimensions
        self.constraints = constraints
        self.exclusions = exclusions
        self.coverage = coverage
        self.cases = cases.sorted { $0.id < $1.id }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatorVersion = "generator_version"
        case issue
        case inventoryVersion = "inventory_version"
        case hardBounds = "hard_bounds"
        case dimensions
        case constraints
        case exclusions
        case coverage
        case cases
    }

    /// Validates identity, uniqueness, and every configured generation bound.
    public func validate() throws {
        guard schemaVersion > 0 else {
            throw SQLiteCombinatorialManifestError.invalidField("schema_version must be positive")
        }
        guard !generatorVersion.isEmpty else {
            throw SQLiteCombinatorialManifestError.invalidField("generator_version must not be empty")
        }
        guard issue > 0 else {
            throw SQLiteCombinatorialManifestError.invalidField("issue must be positive")
        }
        guard !inventoryVersion.isEmpty else {
            throw SQLiteCombinatorialManifestError.invalidField("inventory_version must not be empty")
        }

        try hardBounds.validate()
        try requireUnique(dimensions.map(\.id), kind: "dimension")
        try requireUnique(constraints.map(\.id), kind: "constraint")
        try requireUnique(exclusions.map(\.id), kind: "exclusion")
        try requireUnique(cases.map(\.id), kind: "case")

        guard cases.count <= hardBounds.maximumCaseCount else {
            throw SQLiteCombinatorialManifestError.boundExceeded(
                caseID: nil,
                bound: "maximum_case_count",
                actual: cases.count,
                maximum: hardBounds.maximumCaseCount
            )
        }

        let dimensionIDs = Set(dimensions.map(\.id))
        let constraintIDs = Set(constraints.map(\.id))
        for testCase in cases {
            guard !testCase.id.isEmpty else {
                throw SQLiteCombinatorialManifestError.invalidField("case id must not be empty")
            }
            guard !testCase.strength.isEmpty else {
                throw SQLiteCombinatorialManifestError.invalidField(
                    "case \(testCase.id) strength must not be empty"
                )
            }
            guard testCase.dimensionVector.count <= hardBounds.maximumDimensionsPerCase else {
                throw SQLiteCombinatorialManifestError.boundExceeded(
                    caseID: testCase.id,
                    bound: "maximum_dimensions_per_case",
                    actual: testCase.dimensionVector.count,
                    maximum: hardBounds.maximumDimensionsPerCase
                )
            }
            guard testCase.bindings.count <= hardBounds.maximumBindingsPerCase else {
                throw SQLiteCombinatorialManifestError.boundExceeded(
                    caseID: testCase.id,
                    bound: "maximum_bindings_per_case",
                    actual: testCase.bindings.count,
                    maximum: hardBounds.maximumBindingsPerCase
                )
            }
            guard testCase.renderedSQL.utf8.count <= hardBounds.maximumRenderedSQLBytes else {
                throw SQLiteCombinatorialManifestError.boundExceeded(
                    caseID: testCase.id,
                    bound: "maximum_rendered_sql_bytes",
                    actual: testCase.renderedSQL.utf8.count,
                    maximum: hardBounds.maximumRenderedSQLBytes
                )
            }
            guard testCase.reproductionCommand.utf8.count
                <= hardBounds.maximumReproductionCommandBytes
            else {
                throw SQLiteCombinatorialManifestError.boundExceeded(
                    caseID: testCase.id,
                    bound: "maximum_reproduction_command_bytes",
                    actual: testCase.reproductionCommand.utf8.count,
                    maximum: hardBounds.maximumReproductionCommandBytes
                )
            }

            try requireUnique(
                testCase.dimensionVector.map(\.dimensionID),
                kind: "dimension selection in case \(testCase.id)"
            )
            let unknownDimensions = Set(testCase.dimensionVector.map(\.dimensionID))
                .subtracting(dimensionIDs)
            guard unknownDimensions.isEmpty else {
                throw SQLiteCombinatorialManifestError.unknownReference(
                    kind: "dimension",
                    id: unknownDimensions.sorted()[0],
                    caseID: testCase.id
                )
            }

            let unknownConstraints = Set(testCase.constraintIDs).subtracting(constraintIDs)
            guard unknownConstraints.isEmpty else {
                throw SQLiteCombinatorialManifestError.unknownReference(
                    kind: "constraint",
                    id: unknownConstraints.sorted()[0],
                    caseID: testCase.id
                )
            }

            for binding in testCase.bindings {
                try binding.validate(caseID: testCase.id)
            }
        }
    }

    /// Pretty-printed, sorted-key UTF-8 JSON with exactly one trailing newline.
    public func canonicalJSONData() throws -> Data {
        try validate()
        return try SQLiteCombinatorialCanonicalJSON.encode(self)
    }

    public func canonicalJSONString() throws -> String {
        let data = try canonicalJSONData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteCombinatorialManifestError.invalidUTF8
        }
        return string
    }

    /// A deterministic review surface derived only from canonical manifest data.
    public func markdownSummary() throws -> String {
        try validate()

        var lines = [
            "# SwiftQL SQLite combinatorial manifest",
            "",
            "- Schema version: `\(schemaVersion)`",
            "- Generator version: `\(markdownCode(generatorVersion))`",
            "- Coordination issue: `#\(issue)`",
            "- Inventory version: `\(markdownCode(inventoryVersion))`",
            "- Cases: `\(cases.count)`",
            "",
            "## Hard bounds",
            "",
            "| Bound | Maximum |",
            "| --- | ---: |",
            "| Cases | \(hardBounds.maximumCaseCount) |",
            "| Dimensions per case | \(hardBounds.maximumDimensionsPerCase) |",
            "| Bindings per case | \(hardBounds.maximumBindingsPerCase) |",
            "| Rendered SQL bytes | \(hardBounds.maximumRenderedSQLBytes) |",
            "| Reproduction-command bytes | \(hardBounds.maximumReproductionCommandBytes) |",
            "| Reduction attempts | \(hardBounds.maximumReductionAttempts) |",
            "",
            "## Dimensions",
            "",
            "| ID | Title | Ordered values |",
            "| --- | --- | --- |",
        ]

        for dimension in dimensions {
            let values = dimension.values.map { "\($0.id): \($0.label)" }.joined(separator: ", ")
            lines.append(
                "| \(markdownCell(dimension.id)) | \(markdownCell(dimension.title)) | \(markdownCell(values)) |"
            )
        }

        lines.append(contentsOf: [
            "",
            "## Constraints",
            "",
            "| ID | Dimensions | Description |",
            "| --- | --- | --- |",
        ])
        for constraint in constraints {
            lines.append(
                "| \(markdownCell(constraint.id)) | \(markdownCell(constraint.dimensionIDs.joined(separator: ", "))) | \(markdownCell(constraint.description)) |"
            )
        }

        lines.append(contentsOf: [
            "",
            "## Exclusions",
            "",
            "| ID | Constraint | Ordered vector | Reason |",
            "| --- | --- | --- | --- |",
        ])
        for exclusion in exclusions {
            lines.append(
                "| \(markdownCell(exclusion.id)) | \(markdownCell(exclusion.constraintID ?? "-")) | \(markdownCell(render(exclusion.dimensionVector))) | \(markdownCell(exclusion.reason)) |"
            )
        }

        lines.append(contentsOf: [
            "",
            "## Coverage",
            "",
            "| Strength | Ordered dimensions | Required | Covered | Excluded |",
            "| ---: | --- | ---: | ---: | ---: |",
        ])
        for item in coverage {
            lines.append(
                "| \(item.strength) | \(markdownCell(item.dimensionIDs.joined(separator: ", "))) | \(item.requiredTupleCount) | \(item.coveredTupleCount) | \(item.excludedTupleCount) |"
            )
        }

        lines.append(contentsOf: [
            "",
            "## Cases",
            "",
            "| Stable ID | Template | Strength | Mode | Ordered vector | Inventory features | Northwind anchors | Bindings |",
            "| --- | --- | --- | --- | --- | --- | --- | ---: |",
        ])
        for testCase in cases {
            lines.append(
                "| \(markdownCell(testCase.id)) | \(markdownCell(testCase.template)) | \(testCase.strength) | \(testCase.mode.rawValue) | \(markdownCell(render(testCase.dimensionVector))) | \(markdownCell(testCase.inventoryFeatureIDs.joined(separator: ", "))) | \(markdownCell((testCase.northwindAnchorCaseIDs ?? []).joined(separator: ", "))) | \(testCase.bindings.count) |"
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func requireUnique(_ ids: [String], kind: String) throws {
        var observed: Set<String> = []
        for id in ids {
            guard !id.isEmpty else {
                throw SQLiteCombinatorialManifestError.invalidField("\(kind) id must not be empty")
            }
            guard observed.insert(id).inserted else {
                throw SQLiteCombinatorialManifestError.duplicateID(kind: kind, id: id)
            }
        }
    }
}


public struct SQLiteCombinatorialManifestDimension: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let values: [SQLiteCombinatorialManifestDimensionValue]

    public init(
        id: String,
        title: String,
        values: [SQLiteCombinatorialManifestDimensionValue]
    ) {
        self.id = id
        self.title = title
        self.values = values
    }
}


public struct SQLiteCombinatorialManifestDimensionValue: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}


public struct SQLiteCombinatorialManifestConstraint: Codable, Equatable, Sendable {
    public let id: String
    public let dimensionIDs: [String]
    public let description: String

    public init(id: String, dimensionIDs: [String], description: String) {
        self.id = id
        self.dimensionIDs = dimensionIDs
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case dimensionIDs = "dimension_ids"
        case description
    }
}


public struct SQLiteCombinatorialManifestExclusion: Codable, Equatable, Sendable {
    public let id: String
    public let constraintID: String?
    public let reason: String
    public let dimensionVector: [SQLiteCombinatorialCaseDimensionSelection]

    public init(
        id: String,
        constraintID: String?,
        reason: String,
        dimensionVector: [SQLiteCombinatorialCaseDimensionSelection]
    ) {
        self.id = id
        self.constraintID = constraintID
        self.reason = reason
        self.dimensionVector = dimensionVector
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case constraintID = "constraint_id"
        case reason
        case dimensionVector = "dimension_vector"
    }
}


public struct SQLiteCombinatorialManifestCoverage: Codable, Equatable, Sendable {
    public let strength: Int
    public let dimensionIDs: [String]
    public let requiredTupleCount: Int
    public let coveredTupleCount: Int
    public let excludedTupleCount: Int

    public init(
        strength: Int,
        dimensionIDs: [String],
        requiredTupleCount: Int,
        coveredTupleCount: Int,
        excludedTupleCount: Int
    ) {
        self.strength = strength
        self.dimensionIDs = dimensionIDs
        self.requiredTupleCount = requiredTupleCount
        self.coveredTupleCount = coveredTupleCount
        self.excludedTupleCount = excludedTupleCount
    }

    private enum CodingKeys: String, CodingKey {
        case strength
        case dimensionIDs = "dimension_ids"
        case requiredTupleCount = "required_tuple_count"
        case coveredTupleCount = "covered_tuple_count"
        case excludedTupleCount = "excluded_tuple_count"
    }
}


/// Generation and replay limits that are part of manifest identity.
public struct SQLiteCombinatorialHardBounds: Codable, Equatable, Sendable {
    public let maximumCaseCount: Int
    public let maximumDimensionsPerCase: Int
    public let maximumBindingsPerCase: Int
    public let maximumRenderedSQLBytes: Int
    public let maximumReproductionCommandBytes: Int
    public let maximumReductionAttempts: Int

    public init(
        maximumCaseCount: Int,
        maximumDimensionsPerCase: Int,
        maximumBindingsPerCase: Int,
        maximumRenderedSQLBytes: Int,
        maximumReproductionCommandBytes: Int,
        maximumReductionAttempts: Int
    ) {
        self.maximumCaseCount = maximumCaseCount
        self.maximumDimensionsPerCase = maximumDimensionsPerCase
        self.maximumBindingsPerCase = maximumBindingsPerCase
        self.maximumRenderedSQLBytes = maximumRenderedSQLBytes
        self.maximumReproductionCommandBytes = maximumReproductionCommandBytes
        self.maximumReductionAttempts = maximumReductionAttempts
    }

    fileprivate func validate() throws {
        let values = [
            ("maximum_case_count", maximumCaseCount),
            ("maximum_dimensions_per_case", maximumDimensionsPerCase),
            ("maximum_bindings_per_case", maximumBindingsPerCase),
            ("maximum_rendered_sql_bytes", maximumRenderedSQLBytes),
            ("maximum_reproduction_command_bytes", maximumReproductionCommandBytes),
            ("maximum_reduction_attempts", maximumReductionAttempts),
        ]
        for (name, value) in values where value <= 0 {
            throw SQLiteCombinatorialManifestError.invalidField("\(name) must be positive")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case maximumCaseCount = "maximum_case_count"
        case maximumDimensionsPerCase = "maximum_dimensions_per_case"
        case maximumBindingsPerCase = "maximum_bindings_per_case"
        case maximumRenderedSQLBytes = "maximum_rendered_sql_bytes"
        case maximumReproductionCommandBytes = "maximum_reproduction_command_bytes"
        case maximumReductionAttempts = "maximum_reduction_attempts"
    }
}


public struct SQLiteCombinatorialCaseDimensionSelection: Codable, Equatable, Sendable {
    public let dimensionID: String
    public let valueID: String

    public init(dimensionID: String, valueID: String) {
        self.dimensionID = dimensionID
        self.valueID = valueID
    }

    private enum CodingKeys: String, CodingKey {
        case dimensionID = "dimension_id"
        case valueID = "value_id"
    }
}


public enum SQLiteCombinatorialCaseMode: String, Codable, CaseIterable, Sendable {
    case prepareOnly = "prepare-only"
    case semantic
}


public struct SQLiteCombinatorialOracle: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case fixedValue = "fixed-value"
        case rawSQL = "raw-sql"
        case packagedView = "packaged-view"
        case databaseState = "database-state"
    }

    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}


public struct SQLiteCombinatorialCase: Codable, Equatable, Sendable {
    public let id: String
    public let template: String
    public let strength: String
    public let dimensionVector: [SQLiteCombinatorialCaseDimensionSelection]
    public let constraintIDs: [String]
    public let inventoryFeatureIDs: [String]
    public let northwindAnchorCaseIDs: [String]?
    public let requiredCapabilities: [String]
    public let renderedSQL: String
    public let bindings: [SQLiteCombinatorialBinding]
    public let mode: SQLiteCombinatorialCaseMode
    public let oracle: SQLiteCombinatorialOracle?
    public let reproductionCommand: String

    public init(
        id: String,
        template: String,
        strength: String,
        dimensionVector: [SQLiteCombinatorialCaseDimensionSelection],
        constraintIDs: [String],
        inventoryFeatureIDs: [String],
        northwindAnchorCaseIDs: [String]?,
        requiredCapabilities: [String],
        renderedSQL: String,
        bindings: [SQLiteCombinatorialBinding],
        mode: SQLiteCombinatorialCaseMode,
        oracle: SQLiteCombinatorialOracle?,
        reproductionCommand: String
    ) {
        self.id = id
        self.template = template
        self.strength = strength
        self.dimensionVector = dimensionVector
        self.constraintIDs = sortedUnique(constraintIDs)
        self.inventoryFeatureIDs = sortedUnique(inventoryFeatureIDs)
        let anchors = sortedUnique(northwindAnchorCaseIDs ?? [])
        self.northwindAnchorCaseIDs = anchors.isEmpty ? nil : anchors
        self.requiredCapabilities = sortedUnique(requiredCapabilities)
        self.renderedSQL = renderedSQL
        self.bindings = bindings.sorted(by: SQLiteCombinatorialBinding.canonicalOrder)
        self.mode = mode
        self.oracle = oracle
        self.reproductionCommand = reproductionCommand
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case template
        case strength
        case dimensionVector = "dimension_vector"
        case constraintIDs = "constraint_ids"
        case inventoryFeatureIDs = "inventory_feature_ids"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case requiredCapabilities = "required_capabilities"
        case renderedSQL = "rendered_sql"
        case bindings
        case mode
        case oracle
        case reproductionCommand = "reproduction_command"
    }
}


public enum SQLiteCombinatorialBindingKeyKind: String, Codable, CaseIterable, Sendable {
    case named
    case indexed
}


public enum SQLiteCombinatorialStorageClass: String, Codable, CaseIterable, Sendable {
    case null
    case integer
    case real
    case text
    case blob
}


/// A value with an explicit SQLite-storage tag and a lossless JSON shape.
public enum SQLiteCombinatorialTaggedValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var storageClass: SQLiteCombinatorialStorageClass {
        switch self {
        case .null:
            return .null
        case .integer:
            return .integer
        case .real:
            return .real
        case .text:
            return .text
        case .blob:
            return .blob
        }
    }
}


extension SQLiteCombinatorialTaggedValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(SQLiteCombinatorialStorageClass.self, forKey: .tag)
        switch tag {
        case .null:
            self = .null
        case .integer:
            self = .integer(try container.decode(Int64.self, forKey: .value))
        case .real:
            let text = try container.decode(String.self, forKey: .value)
            guard let value = SQLiteCombinatorialTaggedValue.decodeReal(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid tagged SQLite real: \(text)"
                )
            }
            self = .real(value)
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .blob:
            let hex = try container.decode(String.self, forKey: .value)
            guard let data = Data(lowercaseHex: hex) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid tagged SQLite blob hex"
                )
            }
            self = .blob(data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storageClass, forKey: .tag)
        switch self {
        case .null:
            break
        case .integer(let value):
            try container.encode(value, forKey: .value)
        case .real(let value):
            try container.encode(Self.encodeReal(value), forKey: .value)
        case .text(let value):
            try container.encode(value, forKey: .value)
        case .blob(let value):
            try container.encode(value.lowercaseHex, forKey: .value)
        }
    }

    private static func encodeReal(_ value: Double) -> String {
        if value.isNaN {
            return "nan"
        }
        if value == .infinity {
            return "infinity"
        }
        if value == -.infinity {
            return "-infinity"
        }
        if value == 0, value.sign == .minus {
            return "-0.0"
        }
        return String(value)
    }

    private static func decodeReal(_ text: String) -> Double? {
        switch text {
        case "nan":
            return .nan
        case "infinity":
            return .infinity
        case "-infinity":
            return -.infinity
        default:
            return Double(text)
        }
    }
}


/// One logical SwiftQL binding, including repeated-placeholder identity.
public struct SQLiteCombinatorialBinding: Codable, Equatable, Sendable {
    public let logicalIndex: Int
    public let keyKind: SQLiteCombinatorialBindingKeyKind
    public let keyName: String?
    public let keyIndex: Int?
    public let storage: SQLiteCombinatorialStorageClass
    public let taggedValue: SQLiteCombinatorialTaggedValue
    public let repeatCount: Int

    public init(
        logicalIndex: Int,
        keyKind: SQLiteCombinatorialBindingKeyKind,
        keyName: String?,
        keyIndex: Int?,
        storage: SQLiteCombinatorialStorageClass,
        taggedValue: SQLiteCombinatorialTaggedValue,
        repeatCount: Int
    ) {
        self.logicalIndex = logicalIndex
        self.keyKind = keyKind
        self.keyName = keyName
        self.keyIndex = keyIndex
        self.storage = storage
        self.taggedValue = taggedValue
        self.repeatCount = repeatCount
    }

    /// Captures SwiftQL's concrete logical slot and driver-neutral SQLite value.
    public init(
        slot: XLParameterSlot,
        value: XLSQLiteValue,
        repeatCount: Int = 1
    ) {
        let keyKind: SQLiteCombinatorialBindingKeyKind
        let keyName: String?
        let keyIndex: Int?
        switch slot.key {
        case .named(let name):
            keyKind = .named
            keyName = name
            keyIndex = nil
        case .indexed(let index):
            keyKind = .indexed
            keyName = nil
            keyIndex = index
        }

        let taggedValue = SQLiteCombinatorialTaggedValue(value)
        self.init(
            logicalIndex: slot.index.rawValue,
            keyKind: keyKind,
            keyName: keyName,
            keyIndex: keyIndex,
            storage: taggedValue.storageClass,
            taggedValue: taggedValue,
            repeatCount: repeatCount
        )
    }

    static func canonicalOrder(
        _ lhs: SQLiteCombinatorialBinding,
        _ rhs: SQLiteCombinatorialBinding
    ) -> Bool {
        if lhs.logicalIndex != rhs.logicalIndex {
            return lhs.logicalIndex < rhs.logicalIndex
        }
        if lhs.keyKind.rawValue != rhs.keyKind.rawValue {
            return lhs.keyKind.rawValue < rhs.keyKind.rawValue
        }
        if lhs.keyName != rhs.keyName {
            return (lhs.keyName ?? "") < (rhs.keyName ?? "")
        }
        return (lhs.keyIndex ?? -1) < (rhs.keyIndex ?? -1)
    }

    fileprivate func validate(caseID: String) throws {
        guard logicalIndex >= 0 else {
            throw SQLiteCombinatorialManifestError.invalidBinding(
                caseID: caseID,
                logicalIndex: logicalIndex,
                reason: "logical_index must not be negative"
            )
        }
        guard repeatCount > 0 else {
            throw SQLiteCombinatorialManifestError.invalidBinding(
                caseID: caseID,
                logicalIndex: logicalIndex,
                reason: "repeat_count must be positive"
            )
        }
        guard storage == taggedValue.storageClass else {
            throw SQLiteCombinatorialManifestError.invalidBinding(
                caseID: caseID,
                logicalIndex: logicalIndex,
                reason: "storage does not match tagged_value"
            )
        }
        switch keyKind {
        case .named:
            guard let keyName, !keyName.isEmpty, keyIndex == nil else {
                throw SQLiteCombinatorialManifestError.invalidBinding(
                    caseID: caseID,
                    logicalIndex: logicalIndex,
                    reason: "named key requires key_name and no key_index"
                )
            }
        case .indexed:
            guard keyName == nil, let keyIndex, keyIndex >= 0 else {
                throw SQLiteCombinatorialManifestError.invalidBinding(
                    caseID: caseID,
                    logicalIndex: logicalIndex,
                    reason: "indexed key requires a nonnegative key_index and no key_name"
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case logicalIndex = "logical_index"
        case keyKind = "key_kind"
        case keyName = "key_name"
        case keyIndex = "key_index"
        case storage
        case taggedValue = "tagged_value"
        case repeatCount = "repeat_count"
    }
}


public enum SQLiteCombinatorialManifestError: Error, Equatable, Sendable {
    case invalidField(String)
    case duplicateID(kind: String, id: String)
    case unknownReference(kind: String, id: String, caseID: String)
    case invalidBinding(caseID: String, logicalIndex: Int, reason: String)
    case boundExceeded(caseID: String?, bound: String, actual: Int, maximum: Int)
    case invalidUTF8
}


enum SQLiteCombinatorialCanonicalJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        if data.last != 0x0A {
            data.append(0x0A)
        }
        return data
    }
}


private extension SQLiteCombinatorialTaggedValue {
    init(_ value: XLSQLiteValue) {
        switch value {
        case .null:
            self = .null
        case .integer(let integer):
            self = .integer(integer)
        case .real(let real):
            self = .real(real)
        case .text(let text):
            self = .text(text)
        case .blob(let data):
            self = .blob(data)
        }
    }
}


private extension Data {
    init?(lowercaseHex: String) {
        guard lowercaseHex.count.isMultiple(of: 2),
              lowercaseHex.unicodeScalars.allSatisfy({
                  ("0" ... "9").contains(Character($0))
                      || ("a" ... "f").contains(Character($0))
              }) else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(lowercaseHex.count / 2)
        var index = lowercaseHex.startIndex
        while index < lowercaseHex.endIndex {
            let next = lowercaseHex.index(index, offsetBy: 2)
            guard let byte = UInt8(lowercaseHex[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var lowercaseHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}


private func sortedUnique(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}


private func markdownCell(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "|", with: "\\|")
        .replacingOccurrences(of: "\r\n", with: "<br>")
        .replacingOccurrences(of: "\n", with: "<br>")
        .replacingOccurrences(of: "\r", with: "<br>")
}


private func markdownCode(_ value: String) -> String {
    value.replacingOccurrences(of: "`", with: "\\`")
}


private func render(_ vector: [SQLiteCombinatorialCaseDimensionSelection]) -> String {
    vector.map { "\($0.dimensionID)=\($0.valueID)" }.joined(separator: ", ")
}
