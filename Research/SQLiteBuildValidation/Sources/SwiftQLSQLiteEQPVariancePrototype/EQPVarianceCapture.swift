import Foundation
import GRDB
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteBuildValidationPrototype


package enum EQPVarianceCaptureError: Error, Sendable {
    case emptyCorpus
    case invalidBinding(statementID: String, reason: String)
}


/// Runs the #390 corpus's `EXPLAIN QUERY PLAN` against one live SQLite
/// connection and records the runtime provenance that produced it.
///
/// Mirrors the existing `SQLiteCombinatorialConformanceTests.arguments(for:)`
/// binding logic (same all-named-or-all-indexed assumption, which every
/// corpus statement here satisfies) so the same statement, with the same
/// bound values, is comparable across capture methods.
package enum EQPVarianceCapture {
    package static func capture(
        from database: Database,
        corpus: [EQPVarianceStatement],
        label: String,
        captureMethod: String = "grdb-in-process"
    ) throws -> EQPCaptureRun {
        guard !corpus.isEmpty else {
            throw EQPVarianceCaptureError.emptyCorpus
        }

        let runtimeMetadata = try SQLiteBuildValidationRuntime.capture(from: database)

        let statements = try corpus.map { statement -> EQPStatementCapture in
            let rows = try Row.fetchAll(
                database,
                sql: "EXPLAIN QUERY PLAN \(statement.renderedSQL)",
                arguments: try arguments(for: statement.bindings, statementID: statement.id)
            ).map { row -> EQPRow in
                EQPRow(
                    id: row["id"],
                    parent: row["parent"],
                    notused: row["notused"],
                    detail: row["detail"]
                )
            }
            return EQPStatementCapture(statementID: statement.id, rows: rows)
        }

        return EQPCaptureRun(
            label: label,
            captureMethod: captureMethod,
            runtimeMetadata: runtimeMetadata,
            statements: statements
        )
    }

    /// Throws rather than silently dropping or reinterpreting a malformed
    /// binding: a missing named key or a mix of named/indexed keys within one
    /// statement would otherwise produce a capture with quietly missing or
    /// wrongly-positioned bound values instead of a clear failure.
    package static func arguments(
        for bindings: [SQLiteCombinatorialBinding],
        statementID: String
    ) throws -> StatementArguments {
        guard !bindings.isEmpty else {
            return StatementArguments()
        }

        let allNamed = bindings.allSatisfy { $0.keyKind == .named }
        let allIndexed = bindings.allSatisfy { $0.keyKind == .indexed }
        guard allNamed || allIndexed else {
            throw EQPVarianceCaptureError.invalidBinding(
                statementID: statementID,
                reason: "bindings mix named and indexed keys"
            )
        }

        if allNamed {
            var pairs: [String: DatabaseValue] = [:]
            pairs.reserveCapacity(bindings.count)
            for binding in bindings {
                guard let keyName = binding.keyName else {
                    throw EQPVarianceCaptureError.invalidBinding(
                        statementID: statementID,
                        reason: "named binding at logical index \(binding.logicalIndex) has no key_name"
                    )
                }
                guard pairs.updateValue(databaseValue(binding.taggedValue), forKey: keyName) == nil else {
                    throw EQPVarianceCaptureError.invalidBinding(
                        statementID: statementID,
                        reason: "duplicate named binding key_name \"\(keyName)\""
                    )
                }
            }
            return StatementArguments(pairs)
        }

        return StatementArguments(
            bindings
                .sorted { $0.logicalIndex < $1.logicalIndex }
                .map { databaseValue($0.taggedValue) }
        )
    }

    private static func databaseValue(
        _ value: SQLiteCombinatorialTaggedValue
    ) -> DatabaseValue {
        switch value {
        case .null:
            return .null
        case .integer(let value):
            return value.databaseValue
        case .real(let value):
            return value.databaseValue
        case .text(let value):
            return value.databaseValue
        case .blob(let value):
            return value.databaseValue
        }
    }
}
