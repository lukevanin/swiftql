import Foundation


/// The four variance axes #390 asks for, plus one class this prototype found
/// necessary in practice: SQLite's own EQP `id`/`parent` numbering is not a
/// stable identifier across builds even when the plan is otherwise identical
/// (see `SQLiteEQPVariance.md`). Keeping it distinct from `cosmeticWording`
/// matters because it means naive byte-diffing over-reports variance: two
/// evidence captures must be renumbered before they can be compared at all.
package enum EQPVarianceDifferenceClass: String, Codable, Sendable {
    case identical
    case idRenumberingOnly = "id_renumbering_only"
    case cosmeticWordingChange = "cosmetic_wording_change"
    case accessPathChange = "access_path_change"
    case joinOrderChange = "join_order_change"
    case materializationStrategyChange = "materialization_strategy_change"
    case unclassified
}


/// One statement's classified before/after comparison. Raw rows from both
/// captures are always retained so a classification is auditable rather than
/// asserted (same principle #391 will apply to shape classification).
package struct EQPVarianceStatementComparison: Codable, Equatable, Sendable {
    package let statementID: String
    package let classification: EQPVarianceDifferenceClass
    package let baselineRows: [EQPRow]
    package let comparisonRows: [EQPRow]

    package init(
        statementID: String,
        classification: EQPVarianceDifferenceClass,
        baselineRows: [EQPRow],
        comparisonRows: [EQPRow]
    ) {
        self.statementID = statementID
        self.classification = classification
        self.baselineRows = baselineRows
        self.comparisonRows = comparisonRows
    }

    private enum CodingKeys: String, CodingKey {
        case statementID = "statement_id"
        case classification
        case baselineRows = "baseline_rows"
        case comparisonRows = "comparison_rows"
    }
}


package enum EQPVarianceClassifierError: Error, Sendable {
    case statementSetMismatch(onlyInBaseline: [String], onlyInComparison: [String])
}


package enum EQPVarianceClassifier {
    /// Compares two capture runs statement-by-statement. Both runs must
    /// contain the same statement ids (i.e. both ran the same corpus) or the
    /// comparison is meaningless and this throws rather than silently
    /// skipping statements.
    package static func compare(
        baseline: EQPCaptureRun,
        comparison: EQPCaptureRun
    ) throws -> [EQPVarianceStatementComparison] {
        let baselineByID = Dictionary(
            uniqueKeysWithValues: baseline.statements.map { ($0.statementID, $0.rows) }
        )
        let comparisonByID = Dictionary(
            uniqueKeysWithValues: comparison.statements.map { ($0.statementID, $0.rows) }
        )
        let baselineIDs = Set(baselineByID.keys)
        let comparisonIDs = Set(comparisonByID.keys)
        guard baselineIDs == comparisonIDs else {
            throw EQPVarianceClassifierError.statementSetMismatch(
                onlyInBaseline: Array(baselineIDs.subtracting(comparisonIDs)).sorted(),
                onlyInComparison: Array(comparisonIDs.subtracting(baselineIDs)).sorted()
            )
        }

        return baselineIDs.sorted().map { statementID in
            let baselineRows = baselineByID[statementID] ?? []
            let comparisonRows = comparisonByID[statementID] ?? []
            return EQPVarianceStatementComparison(
                statementID: statementID,
                classification: classify(baselineRows: baselineRows, comparisonRows: comparisonRows),
                baselineRows: baselineRows,
                comparisonRows: comparisonRows
            )
        }
    }

    package static func classify(
        baselineRows: [EQPRow],
        comparisonRows: [EQPRow]
    ) -> EQPVarianceDifferenceClass {
        if baselineRows == comparisonRows {
            return .identical
        }

        let normalizedBaseline = normalize(baselineRows)
        let normalizedComparison = normalize(comparisonRows)
        if normalizedBaseline == normalizedComparison {
            return .idRenumberingOnly
        }

        guard normalizedBaseline.count == normalizedComparison.count else {
            return .materializationStrategyChangeIfPlausible(
                normalizedBaseline,
                normalizedComparison
            )
        }

        let baselineShapes = normalizedBaseline.map { RowShape(detail: $0.detail) }
        let comparisonShapes = normalizedComparison.map { RowShape(detail: $0.detail) }

        let baselineTables = baselineShapes.compactMap(\.table)
        let comparisonTables = comparisonShapes.compactMap(\.table)
        if Set(baselineTables) == Set(comparisonTables), baselineTables != comparisonTables {
            return .joinOrderChange
        }

        let baselineAccess: [TableAccess] = baselineShapes.compactMap { shape in
            shape.table.map { TableAccess(table: $0, accessMethod: shape.accessMethod) }
        }
        let comparisonAccess: [TableAccess] = comparisonShapes.compactMap { shape in
            shape.table.map { TableAccess(table: $0, accessMethod: shape.accessMethod) }
        }
        if baselineAccess.map(\.table) == comparisonAccess.map(\.table),
           baselineAccess.map(\.accessMethod) != comparisonAccess.map(\.accessMethod) {
            return .accessPathChange
        }

        let baselineMarkers = baselineShapes.map(\.materializationMarker)
        let comparisonMarkers = comparisonShapes.map(\.materializationMarker)
        if baselineMarkers != comparisonMarkers {
            return .materializationStrategyChange
        }

        // Same row count, same parent shape (post-normalization), same
        // extracted tables/access/materialization markers: whatever differs
        // is limited to incidental detail-string wording.
        return .cosmeticWordingChange
    }

    fileprivate struct NormalizedRow: Equatable {
        let parent: Int64
        let detail: String
    }

    private struct TableAccess {
        let table: String
        let accessMethod: String?
    }

    /// Remaps every row's `id`/`parent` to its 1-based position in emission
    /// order. EQP always emits a parent before its children, so this is a
    /// valid, deterministic renumbering without needing full tree recursion.
    private static func normalize(_ rows: [EQPRow]) -> [NormalizedRow] {
        var oldToNew: [Int64: Int64] = [0: 0]
        for (offset, row) in rows.enumerated() {
            oldToNew[row.id] = Int64(offset + 1)
        }
        return rows.map { row in
            NormalizedRow(parent: oldToNew[row.parent] ?? row.parent, detail: row.detail)
        }
    }

    private struct RowShape {
        let table: String?
        let accessMethod: String?
        let materializationMarker: String?

        init(detail: String) {
            if detail.hasPrefix("SEARCH ") || detail.hasPrefix("SCAN ") {
                let body = detail.hasPrefix("SEARCH ")
                    ? String(detail.dropFirst("SEARCH ".count))
                    : String(detail.dropFirst("SCAN ".count))
                let tableToken = body.split(separator: " ").first.map(String.init)
                if tableToken == "CONSTANT" {
                    table = nil
                    accessMethod = nil
                } else {
                    table = tableToken
                    if let usingRange = body.range(of: "USING ") {
                        accessMethod = String(body[usingRange.upperBound...])
                    } else {
                        accessMethod = detail.hasPrefix("SEARCH ") ? "search-default" : "full-scan"
                    }
                }
                materializationMarker = nil
            } else {
                table = nil
                accessMethod = nil
                materializationMarker = Self.materializationMarker(for: detail)
            }
        }

        private static func materializationMarker(for detail: String) -> String? {
            if detail.contains("TEMP B-TREE") {
                return "temp-b-tree"
            }
            if detail.hasPrefix("MERGE (") {
                return "merge-compound"
            }
            if detail == "COMPOUND QUERY" || detail == "LEFT-MOST SUBQUERY" {
                return "legacy-compound"
            }
            if detail == "LEFT" || detail == "RIGHT" {
                return "merge-compound-branch"
            }
            if detail.hasPrefix("CO-ROUTINE") {
                return "co-routine"
            }
            if detail.hasPrefix("SCALAR SUBQUERY") {
                return "scalar-subquery"
            }
            return nil
        }
    }
}


private extension EQPVarianceDifferenceClass {
    /// A row-count change is either a materialization-strategy change (the
    /// two builds chose structurally different plans, e.g. merge-based vs.
    /// materialize-then-set-op compound execution) or something this
    /// prototype's heuristics do not recognise. There is no way to align two
    /// differently-shaped row lists well enough to check for a join-order or
    /// access-path change, so this collapses to one of those two buckets.
    static func materializationStrategyChangeIfPlausible(
        _ baseline: [EQPVarianceClassifier.NormalizedRow],
        _ comparison: [EQPVarianceClassifier.NormalizedRow]
    ) -> EQPVarianceDifferenceClass {
        let materializationKeywords = [
            "TEMP B-TREE", "MERGE (", "COMPOUND QUERY", "LEFT-MOST SUBQUERY",
            "CO-ROUTINE", "RECURSIVE STEP", "SETUP",
        ]
        func mentionsMaterialization(_ rows: [EQPVarianceClassifier.NormalizedRow]) -> Bool {
            rows.contains { row in
                materializationKeywords.contains { row.detail.contains($0) }
            }
        }
        if mentionsMaterialization(baseline) || mentionsMaterialization(comparison) {
            return .materializationStrategyChange
        }
        return .unclassified
    }
}
