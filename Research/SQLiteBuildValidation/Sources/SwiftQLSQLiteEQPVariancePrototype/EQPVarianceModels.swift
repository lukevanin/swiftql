import Foundation
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteBuildValidationPrototype


/// One statement in the #390 EQP-variance corpus: a rendered SQL string with
/// resolved bind values, tagged back to the case identity it came from.
///
/// The corpus is a superset of the #191 combinatorial manifest (reused as-is,
/// including its own `northwind_anchor_case_ids` linkage) plus a small,
/// hand-authored set of Northwind semantic-corpus (#254) anchor statements
/// cribbed from `NorthwindSemanticCorpusTests` for join/CTE/subquery shapes
/// the pairwise grid does not itself exercise against real data.
package struct EQPVarianceStatement: Codable, Equatable, Sendable {
    package enum Source: String, Codable, Sendable {
        case combinatorial
        case northwindAnchor = "northwind_anchor"
    }

    package let id: String
    package let source: Source
    package let renderedSQL: String
    package let northwindAnchorCaseIDs: [String]
    package let bindings: [SQLiteCombinatorialBinding]

    package init(
        id: String,
        source: Source,
        renderedSQL: String,
        northwindAnchorCaseIDs: [String],
        bindings: [SQLiteCombinatorialBinding]
    ) {
        self.id = id
        self.source = source
        self.renderedSQL = renderedSQL
        self.northwindAnchorCaseIDs = northwindAnchorCaseIDs.sorted()
        self.bindings = bindings.sorted { $0.logicalIndex < $1.logicalIndex }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case renderedSQL = "rendered_sql"
        case northwindAnchorCaseIDs = "northwind_anchor_case_ids"
        case bindings
    }
}


/// A raw `EXPLAIN QUERY PLAN` row, kept in SQLite's own column order.
package struct EQPRow: Codable, Equatable, Sendable {
    package let id: Int64
    package let parent: Int64
    package let notused: Int64
    package let detail: String

    package init(id: Int64, parent: Int64, notused: Int64, detail: String) {
        self.id = id
        self.parent = parent
        self.notused = notused
        self.detail = detail
    }
}


/// The captured EQP rows for one statement, on one SQLite build.
package struct EQPStatementCapture: Codable, Equatable, Sendable {
    package let statementID: String
    package let rows: [EQPRow]

    package init(statementID: String, rows: [EQPRow]) {
        self.statementID = statementID
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey {
        case statementID = "statement_id"
        case rows
    }
}


/// One full capture run: every statement's EQP rows plus the runtime
/// provenance (#132 capability-audit evidence) of the SQLite build that
/// produced them.
package struct EQPCaptureRun: Codable, Equatable, Sendable {
    package let label: String
    package let captureMethod: String
    package let runtimeMetadata: SQLiteBuildValidationRuntimeMetadata
    package let statements: [EQPStatementCapture]

    package init(
        label: String,
        captureMethod: String,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata,
        statements: [EQPStatementCapture]
    ) {
        self.label = label
        self.captureMethod = captureMethod
        self.runtimeMetadata = runtimeMetadata
        self.statements = statements.sorted { $0.statementID < $1.statementID }
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case captureMethod = "capture_method"
        case runtimeMetadata = "runtime_metadata"
        case statements
    }
}


/// Deterministic, diff-friendly JSON matching the house style established by
/// `SQLiteBuildValidationCanonicalJSON` (#132 prototype).
package enum EQPVarianceCanonicalJSON {
    package static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        while data.last == 0x0A {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }
}
