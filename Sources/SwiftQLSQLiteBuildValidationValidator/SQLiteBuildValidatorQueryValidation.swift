import Foundation
import GRDB
import SwiftQLSQLiteBuildValidationManifest

//
//  Validating one manifest query: the checks that run before preparation, the
//  preparation itself, and the reconciliation of SwiftQL's declared parameter
//  and result metadata with what SQLite reports for the prepared statement.
//
//  Split out of SQLiteBuildValidator.swift (#566).
//

extension SQLiteBuildValidator {

    static func validate(
        query: SQLiteBuildValidationQueryEntry,
        in database: Database,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?,
        environment: SQLiteBuildValidationEnvironment
    ) -> SQLiteBuildValidationQueryOutcome {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        let placeholderAnalysis = SQLiteBuildValidationValidatorPlaceholderScanner.scan(
            query.sql
        )
        diagnostics.append(contentsOf: placeholderDiagnostics(
            query: query,
            analysis: placeholderAnalysis
        ))
        diagnostics.append(contentsOf: dialectDiagnostics(
            query: query,
            runtimeMetadata: runtimeMetadata
        ))
        diagnostics.append(contentsOf: codecDiagnostics(
            query: query,
            environment: environment
        ))
        diagnostics.append(contentsOf: capabilityDiagnostics(
            query: query,
            runtimeMetadata: runtimeMetadata,
            environment: environment
        ))

        let preparedShape: SQLitePreparedStatementShape?
        if hasUnavailablePreparationPrerequisite(diagnostics) {
            preparedShape = nil
        } else {
            do {
                let shape = try SQLitePrepareV3Probe.prepare(
                    sql: query.sql,
                    in: database
                )
                preparedShape = shape
                if placeholderAnalysis.unsupported.isEmpty {
                    diagnostics.append(contentsOf: parameterDiagnostics(
                        query: query,
                        shape: shape,
                        analysis: placeholderAnalysis
                    ))
                }
                diagnostics.append(contentsOf: resultDiagnostics(
                    query: query,
                    shape: shape
                ))
            } catch let error as SQLitePrepareV3ProbeError {
                preparedShape = nil
                diagnostics.append(prepareDiagnostic(error, query: query))
            } catch {
                preparedShape = nil
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .prepare,
                    code: .sqlitePrepareFailed,
                    message: "SQLite preparation failed with an unexpected \(String(reflecting: type(of: error))).",
                    query: query
                ))
            }
        }

        return SQLiteBuildValidationQueryOutcome(
            query: query,
            placeholderAnalysis: placeholderAnalysis,
            preparedShape: preparedShape,
            diagnostics: diagnostics
        )
    }

    /// Whether something the query needs to be preparable at all is
    /// unavailable, in which case preparation is skipped.
    ///
    /// Attempting it anyway would report SQLite's own parse failure -- a
    /// syntax error naming a function that simply is not registered -- which
    /// tells the author nothing about the capability that is actually missing.
    static func hasUnavailablePreparationPrerequisite(
        _ diagnostics: [SQLiteBuildValidationDiagnostic]
    ) -> Bool {
        diagnostics.contains { diagnostic in
            guard
                diagnostic.verdict == .unsupported,
                let code = diagnostic.diagnosticCode
            else {
                return false
            }
            return SQLiteBuildValidationDiagnosticCode
                .preparationBlocking.contains(code)
        }
    }

    static func placeholderDiagnostics(
        query: SQLiteBuildValidationQueryEntry,
        analysis: SQLiteBuildValidationValidatorPlaceholderAnalysis
    ) -> [SQLiteBuildValidationDiagnostic] {
        let unsupported = analysis.unsupported.map { placeholder in
            SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .parameter,
                code: .parameterSyntax,
                message: "Unsupported placeholder '\(placeholder.spelling)' at UTF-8 byte offset \(placeholder.byteOffset): \(placeholder.reason)",
                query: query
            )
        }
        let collisions = analysis.collisions.map { collision in
            SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .parameter,
                code: .parameterKey,
                message: collision,
                query: query
            )
        }
        return unsupported + collisions
    }

    static func parameterDiagnostics(
        query: SQLiteBuildValidationQueryEntry,
        shape: SQLitePreparedStatementShape,
        analysis: SQLiteBuildValidationValidatorPlaceholderAnalysis
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if shape.physicalParameterCount != query.expectedPhysicalParameterCount {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .parameter,
                code: .parameterCount,
                message: "SQLite exposes \(shape.physicalParameterCount) physical parameter slots; descriptor expects \(query.expectedPhysicalParameterCount).",
                query: query
            ))
        }

        let actualByIndex = Dictionary(
            uniqueKeysWithValues: shape.parameters.map {
                ($0.physicalIndex, $0.name)
            }
        )
        let expectedByIndex = Dictionary(
            uniqueKeysWithValues: query.parameters.map {
                ($0.physicalIndex, $0.expectedSQLiteSpelling)
            }
        )
        let allIndices = Set(actualByIndex.keys).union(expectedByIndex.keys).sorted()
        for physicalIndex in allIndices {
            let expected = expectedByIndex[physicalIndex]
            let actual = actualByIndex[physicalIndex] ?? nil
            if let expected {
                guard actual == expected else {
                    diagnostics.append(SQLiteBuildValidationDiagnostic(
                        verdict: .failed,
                        stage: .parameter,
                        code: .parameterKey,
                        message: "Physical parameter \(physicalIndex) is '\(actual ?? "anonymous/implicit")'; descriptor expects '\(expected)'.",
                        query: query
                    ))
                    continue
                }
            } else if let actual {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .parameter,
                    code: .parameterKey,
                    message: "Physical parameter \(physicalIndex) unexpectedly exposes key '\(actual)'.",
                    query: query
                ))
            }
        }

        if analysis.unsupported.isEmpty {
            if analysis.physicalParameterCount != shape.physicalParameterCount
                || analysis.parameters != shape.parameters {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .parameter,
                    code: .parameterMetadata,
                    message: "Lexical placeholder evidence does not match SQLite's physical parameter table.",
                    query: query
                ))
            }
        }
        return diagnostics
    }

    static func resultDiagnostics(
        query: SQLiteBuildValidationQueryEntry,
        shape: SQLitePreparedStatementShape
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if shape.columns.count != query.results.count {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .result,
                code: .resultCount,
                message: "SQLite exposes \(shape.columns.count) result columns; descriptor expects \(query.results.count).",
                query: query
            ))
        }

        let actualByIndex = Dictionary(
            uniqueKeysWithValues: shape.columns.map { ($0.index, $0) }
        )
        for result in query.results {
            guard let expectedAlias = result.declaredAlias,
                  let column = actualByIndex[result.index],
                  column.name != expectedAlias else {
                continue
            }
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .result,
                code: .resultName,
                message: "Result column \(result.index) is named '\(column.name)'; descriptor expects explicit alias '\(expectedAlias)'.",
                query: query
            ))
        }
        return diagnostics
    }

    static func prepareDiagnostic(
        _ error: SQLitePrepareV3ProbeError,
        query: SQLiteBuildValidationQueryEntry
    ) -> SQLiteBuildValidationDiagnostic {
        switch error {
        case .emptyStatement:
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: .statementEmpty,
                message: "SQL contains no preparable SQLite statement.",
                query: query
            )
        case .embeddedNUL:
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: .statementEmbeddedNUL,
                message: "SQL contains an embedded NUL byte.",
                query: query
            )
        case .multipleStatements:
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: .statementMultiple,
                message: "SQL contains more than one preparable SQLite statement.",
                query: query
            )
        case .sqlitePrepare(let resultCode, let extendedResultCode, let message):
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: .sqlitePrepareFailed,
                message: message,
                query: query,
                sqliteResultCode: resultCode,
                sqliteExtendedResultCode: extendedResultCode
            )
        case .sqliteFinalize(let resultCode, let extendedResultCode, let message):
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: .sqliteFinalizeFailed,
                message: message,
                query: query,
                sqliteResultCode: resultCode,
                sqliteExtendedResultCode: extendedResultCode
            )
        }
    }
}
