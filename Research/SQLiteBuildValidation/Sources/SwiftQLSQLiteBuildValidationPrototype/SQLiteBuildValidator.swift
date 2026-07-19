import Foundation
import GRDB
import SwiftQLCore


package enum SQLiteBuildValidator {
    package static func validate(
        plan: SQLiteBuildValidationPlan,
        againstDatabaseAt databaseURL: URL,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        let databaseURL = databaseURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let plan = try plan.validating()
        let resourceValues = try databaseURL.resourceValues(
            forKeys: [.isRegularFileKey]
        )
        guard resourceValues.isRegularFile == true else {
            throw SQLiteBuildValidationValidatorError.databaseIsNotARegularFile(
                databaseURL.path
            )
        }
        try requireSidecarFreeSnapshot(at: databaseURL)
        let databaseData = try Data(
            contentsOf: databaseURL,
            options: .mappedIfSafe
        )
        let observedDatabaseSHA256 = SQLiteBuildValidationSHA256.hexDigest(
            of: databaseData
        )

        var configuration = Configuration()
        configuration.label = "SwiftQLSQLiteBuildValidationPrototype"
        configuration.readonly = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA query_only = ON")
        }
        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: configuration
        )
        defer { try? queue.close() }

        let report = try queue.read { database in
            try validate(
                plan: plan,
                in: database,
                observedDatabaseByteCount: databaseData.count,
                observedDatabaseSHA256: observedDatabaseSHA256,
                environment: environment
            )
        }

        let finalDatabaseData = try Data(
            contentsOf: databaseURL,
            options: .mappedIfSafe
        )
        let finalDatabaseSHA256 = SQLiteBuildValidationSHA256.hexDigest(
            of: finalDatabaseData
        )
        try requireSidecarFreeSnapshot(at: databaseURL)
        guard finalDatabaseData.count == databaseData.count,
              finalDatabaseSHA256 == observedDatabaseSHA256 else {
            throw SQLiteBuildValidationValidatorError
                .databaseChangedDuringValidation(
                    initialByteCount: databaseData.count,
                    initialSHA256: observedDatabaseSHA256,
                    finalByteCount: finalDatabaseData.count,
                    finalSHA256: finalDatabaseSHA256
                )
        }
        return report
    }

    /// Validates on a caller-supplied serialized connection. The URL overload
    /// is the authoritative CLI path because it owns a read-only/query-only
    /// queue. This seam exists for fixture tests and never retains `database`.
    package static func validate(
        plan: SQLiteBuildValidationPlan,
        in database: Database,
        observedDatabaseByteCount: Int? = nil,
        observedDatabaseSHA256: String? = nil,
        environment: SQLiteBuildValidationEnvironment = .init()
    ) throws -> SQLiteBuildValidationReport {
        let validatedPlan = try plan.validating()

        var reportDiagnostics: [SQLiteBuildValidationDiagnostic] = []
        if let observedDatabaseByteCount {
            if observedDatabaseByteCount != validatedPlan.schema.databaseByteCount {
                reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: "schema.byte-count",
                    message: "Schema snapshot byte count is \(observedDatabaseByteCount); expected \(validatedPlan.schema.databaseByteCount)."
                ))
            }
        } else {
            reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .schema,
                code: "schema.byte-count",
                message: "Schema snapshot byte count evidence was not supplied to the caller-owned validation seam."
            ))
        }
        if let observedDatabaseSHA256 {
            if observedDatabaseSHA256.lowercased() != validatedPlan.schema.databaseSHA256 {
                reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: "schema.snapshot-sha",
                    message: "Schema snapshot SHA-256 is \(observedDatabaseSHA256.lowercased()); expected \(validatedPlan.schema.databaseSHA256)."
                ))
            }
        } else {
            reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .schema,
                code: "schema.snapshot-sha",
                message: "Schema snapshot SHA-256 evidence was not supplied to the caller-owned validation seam."
            ))
        }

        let runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
        do {
            runtimeMetadata = try SQLiteBuildValidationRuntime.capture(
                from: database,
                extensionNames: environment.extensionNames
            )
        } catch {
            runtimeMetadata = nil
            reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .runtime,
                code: "runtime.capture",
                message: "SQLite runtime metadata capture failed: \(String(describing: error))."
            ))
        }

        if let runtimeMetadata {
            if runtimeMetadata.schemaRowCount != validatedPlan.schema.schemaRowCount {
                reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: "schema.row-count",
                    message: "Schema contains \(runtimeMetadata.schemaRowCount) sqlite_schema rows; expected \(validatedPlan.schema.schemaRowCount)."
                ))
            }
            if runtimeMetadata.schemaFNV1A64 != validatedPlan.schema.schemaFNV1A64 {
                reportDiagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .schema,
                    code: "schema.fingerprint",
                    message: "Schema FNV-1a-64 is \(runtimeMetadata.schemaFNV1A64); expected \(validatedPlan.schema.schemaFNV1A64)."
                ))
            }
        }

        let outcomes = validatedPlan.queries.map { query in
            validate(
                query: query,
                in: database,
                runtimeMetadata: runtimeMetadata,
                environment: environment
            )
        }
        return SQLiteBuildValidationReport(
            plan: validatedPlan,
            observedDatabaseByteCount: observedDatabaseByteCount,
            observedDatabaseSHA256: observedDatabaseSHA256,
            runtimeMetadata: runtimeMetadata,
            environmentEvidence: environment,
            diagnostics: reportDiagnostics,
            outcomes: outcomes
        )
    }
}


private extension SQLiteBuildValidator {
    static func validate(
        query: SQLiteBuildValidationQuery,
        in database: Database,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?,
        environment: SQLiteBuildValidationEnvironment
    ) -> SQLiteBuildValidationQueryOutcome {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        let placeholderAnalysis = SQLiteBuildValidationPlaceholderScanner.scan(
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
                    code: "sqlite.prepare.failed",
                    message: "SQLite preparation failed: \(String(describing: error)).",
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

    static func dialectDiagnostics(
        query: SQLiteBuildValidationQuery,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if query.dialectIdentifier != XLSQLiteDialect.identity.rawValue {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .capability,
                code: "capability.dialect",
                message: "Descriptor requires dialect '\(query.dialectIdentifier)'; this prototype validates SQLite only.",
                query: query
            ))
        }

        if let requiredVersion = query.minimumSQLiteVersion {
            guard let actualVersion = runtimeMetadata?.sqliteVersion else {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .unsupported,
                    stage: .capability,
                    code: "capability.sqlite-version",
                    message: "SQLite \(requiredVersion) or newer is required, but runtime identity is unavailable.",
                    query: query
                ))
                return diagnostics
            }
            if !version(actualVersion, isAtLeast: requiredVersion) {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .unsupported,
                    stage: .capability,
                    code: "capability.sqlite-version",
                    message: "SQLite \(actualVersion) does not satisfy required version \(requiredVersion).",
                    query: query
                ))
            }
        }

        let availableDialectCapabilities = XLSQLiteDialect
            .standardCapabilities.rawValue
        let unavailable = query.dialectCapabilitiesRawValue
            & ~availableDialectCapabilities
        if unavailable != 0 {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .capability,
                code: "capability.dialect-flags",
                message: "Descriptor requires unsupported dialect capability bits \(unavailable).",
                query: query
            ))
        }
        return diagnostics
    }

    static func codecDiagnostics(
        query: SQLiteBuildValidationQuery,
        environment: SQLiteBuildValidationEnvironment
    ) -> [SQLiteBuildValidationDiagnostic] {
        struct Slot {
            let identity: String
            let valueTypeIdentifier: String
            let storageIdentifier: String
            let codec: SQLiteBuildValidationCodec
        }

        let slots = query.parameters.compactMap { parameter -> Slot? in
            parameter.codec.map {
                Slot(
                    identity: parameter.identity,
                    valueTypeIdentifier: parameter.valueTypeIdentifier,
                    storageIdentifier: parameter.storageIdentifier,
                    codec: $0
                )
            }
        } + query.results.compactMap { result -> Slot? in
            result.codec.map {
                Slot(
                    identity: result.identity,
                    valueTypeIdentifier: result.valueTypeIdentifier,
                    storageIdentifier: result.storageIdentifier,
                    codec: $0
                )
            }
        }

        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        for slot in slots {
            if slot.codec.valueTypeIdentifier != slot.valueTypeIdentifier {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .codec,
                    code: "codec.value-type",
                    message: "Slot '\(slot.identity)' value type '\(slot.valueTypeIdentifier)' does not match codec value type '\(slot.codec.valueTypeIdentifier)'.",
                    query: query
                ))
            }
            if slot.codec.dialectIdentifier != query.dialectIdentifier {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .codec,
                    code: "codec.dialect",
                    message: "Slot '\(slot.identity)' codec dialect '\(slot.codec.dialectIdentifier)' does not match query dialect '\(query.dialectIdentifier)'.",
                    query: query
                ))
            }
            if slot.codec.storageIdentifier != slot.storageIdentifier {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .codec,
                    code: "codec.storage",
                    message: "Slot '\(slot.identity)' storage '\(slot.storageIdentifier)' does not match codec storage '\(slot.codec.storageIdentifier)'.",
                    query: query
                ))
            }
        }

        let available = Set(environment.codecIdentifiers)
        for identifier in query.requiredCodecIdentifiers where !available.contains(identifier) {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .codec,
                code: "codec.missing",
                message: "Required codec '\(identifier)' was not supplied to the validator environment.",
                query: query
            ))
        }
        return diagnostics
    }

    static func capabilityDiagnostics(
        query: SQLiteBuildValidationQuery,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?,
        environment: SQLiteBuildValidationEnvironment
    ) -> [SQLiteBuildValidationDiagnostic] {
        let explicitCapabilities = Set(environment.capabilityIDs)
        return query.requiredCapabilities.compactMap { requirement in
            if capability(
                    requirement.id,
                    isAvailableIn: runtimeMetadata
                ) || (isOpaqueCapability(requirement.id)
                    && explicitCapabilities.contains(requirement.id)) {
                return nil
            }
            return SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .capability,
                code: capabilityDiagnosticCode(requirement.id),
                message: "Required capability '\(requirement.id)' is unavailable on the validator connection.",
                query: query
            )
        }
    }

    static func isOpaqueCapability(_ id: String) -> Bool {
        let foldedID = id.lowercased()
        let observablePrefixes = [
            "function:",
            "collation:",
            "compile-option:",
            "module:",
            "extension:",
        ]
        return foldedID != "sqlite-json-functions"
            && !observablePrefixes.contains(where: foldedID.hasPrefix)
    }

    static func hasUnavailablePreparationPrerequisite(
        _ diagnostics: [SQLiteBuildValidationDiagnostic]
    ) -> Bool {
        let preparationBlockingCodes = Set([
            "capability.collation",
            "capability.dialect",
            "capability.dialect-flags",
            "capability.extension",
            "capability.function",
            "capability.module",
            "capability.sqlite-json-functions",
            "capability.sqlite-version",
        ])
        return diagnostics.contains { diagnostic in
            diagnostic.verdict == .unsupported
                && preparationBlockingCodes.contains(diagnostic.code)
        }
    }

    static func requireSidecarFreeSnapshot(at databaseURL: URL) throws {
        for suffix in ["-journal", "-shm", "-wal"] {
            let sidecarPath = databaseURL.path + suffix
            guard !FileManager.default.fileExists(atPath: sidecarPath) else {
                throw SQLiteBuildValidationValidatorError.databaseHasSidecar(
                    sidecarPath
                )
            }
        }
    }

    static func capability(
        _ id: String,
        isAvailableIn runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
    ) -> Bool {
        guard let runtimeMetadata else {
            return false
        }
        if let name = suffix(of: id, after: "function:") {
            return runtimeMetadata.hasFunction(named: name)
        }
        if let name = suffix(of: id, after: "collation:") {
            return runtimeMetadata.hasCollation(named: name)
        }
        if let option = suffix(of: id, after: "compile-option:") {
            return runtimeMetadata.hasCompileOption(option)
        }
        if let name = suffix(of: id, after: "module:") {
            return runtimeMetadata.hasModule(named: name)
        }
        if let name = suffix(of: id, after: "extension:") {
            return runtimeMetadata.hasExtension(named: name)
        }
        switch id {
        case "named-bindings", "indexed-bindings", "sqlite-core-parser",
             "sqlite-storage-classes", "compound-select", "recursive-cte",
             "transactions":
            return true
        case "sqlite-json-functions":
            return runtimeMetadata.hasFunction(named: "JSON_VALID")
        default:
            return false
        }
    }

    static func capabilityDiagnosticCode(_ id: String) -> String {
        let foldedID = id.lowercased()
        if foldedID.hasPrefix("function:") {
            return "capability.function"
        }
        if foldedID.hasPrefix("collation:") {
            return "capability.collation"
        }
        if foldedID.hasPrefix("compile-option:") {
            return "capability.compile-option"
        }
        if foldedID.hasPrefix("module:") {
            return "capability.module"
        }
        if foldedID.hasPrefix("extension:") {
            return "capability.extension"
        }
        if foldedID == "sqlite-json-functions" {
            return "capability.sqlite-json-functions"
        }
        return "capability.missing"
    }

    static func parameterDiagnostics(
        query: SQLiteBuildValidationQuery,
        shape: SQLitePreparedStatementShape,
        analysis: SQLiteBuildValidationPlaceholderAnalysis
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if shape.physicalParameterCount != query.expectedPhysicalParameterCount {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .parameter,
                code: "parameter.count",
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
                ($0.physicalIndex, $0.expectedSQLiteName)
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
                        code: "parameter.key",
                        message: "Physical parameter \(physicalIndex) is '\(actual ?? "anonymous/implicit")'; descriptor expects '\(expected)'.",
                        query: query
                    ))
                    continue
                }
            } else if let actual {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .parameter,
                    code: "parameter.key",
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
                    code: "parameter.metadata",
                    message: "Lexical placeholder evidence does not match SQLite's physical parameter table.",
                    query: query
                ))
            }
        }
        return diagnostics
    }

    static func placeholderDiagnostics(
        query: SQLiteBuildValidationQuery,
        analysis: SQLiteBuildValidationPlaceholderAnalysis
    ) -> [SQLiteBuildValidationDiagnostic] {
        let unsupported = analysis.unsupported.map { placeholder in
            SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .parameter,
                code: "parameter.syntax",
                message: "Unsupported placeholder '\(placeholder.spelling)' at UTF-8 byte offset \(placeholder.byteOffset): \(placeholder.reason)",
                query: query
            )
        }
        let collisions = analysis.collisions.map { collision in
            SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .parameter,
                code: "parameter.key",
                message: collision,
                query: query
            )
        }
        return unsupported + collisions
    }

    static func resultDiagnostics(
        query: SQLiteBuildValidationQuery,
        shape: SQLitePreparedStatementShape
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if shape.columns.count != query.results.count {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .result,
                code: "result.count",
                message: "SQLite exposes \(shape.columns.count) result columns; descriptor expects \(query.results.count).",
                query: query
            ))
        }

        let actualByIndex = Dictionary(
            uniqueKeysWithValues: shape.columns.map { ($0.index, $0) }
        )
        for result in query.results {
            guard let expectedAlias = result.expectedAlias,
                  let column = actualByIndex[result.index],
                  column.name != expectedAlias else {
                continue
            }
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .result,
                code: "result.name",
                message: "Result column \(result.index) is named '\(column.name)'; descriptor expects explicit alias '\(expectedAlias)'.",
                query: query
            ))
        }
        return diagnostics
    }

    static func prepareDiagnostic(
        _ error: SQLitePrepareV3ProbeError,
        query: SQLiteBuildValidationQuery
    ) -> SQLiteBuildValidationDiagnostic {
        switch error {
        case .emptyStatement:
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: "statement.empty",
                message: "SQL contains no preparable SQLite statement.",
                query: query
            )
        case .embeddedNUL:
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: "statement.embedded-nul",
                message: "SQL contains an embedded NUL byte.",
                query: query
            )
        case .multipleStatements:
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: "statement.multiple",
                message: "SQL contains more than one preparable SQLite statement.",
                query: query
            )
        case .sqlitePrepare(let resultCode, let extendedResultCode, let message):
            return SQLiteBuildValidationDiagnostic(
                verdict: .failed,
                stage: .prepare,
                code: "sqlite.prepare.failed",
                message: message,
                query: query,
                sqliteResultCode: resultCode,
                sqliteExtendedResultCode: extendedResultCode
            )
        }
    }

    static func suffix(of value: String, after prefix: String) -> String? {
        guard value.hasPrefix(prefix) else {
            return nil
        }
        let suffix = String(value.dropFirst(prefix.count))
        return suffix.isEmpty ? nil : suffix
    }

    static func version(_ actual: String, isAtLeast required: String) -> Bool {
        guard let actual = versionComponents(actual),
              let required = versionComponents(required) else {
            return false
        }
        return actual.lexicographicallyPrecedes(required) == false
    }

    static func versionComponents(_ value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.count <= 3,
              components.allSatisfy({ Int($0) != nil }) else {
            return nil
        }
        return components.map { Int($0)! }
            + Array(repeating: 0, count: 3 - components.count)
    }
}


package enum SQLiteBuildValidationValidatorError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case databaseIsNotARegularFile(String)
    case databaseHasSidecar(String)
    case databaseChangedDuringValidation(
        initialByteCount: Int,
        initialSHA256: String,
        finalByteCount: Int,
        finalSHA256: String
    )

    package var description: String {
        switch self {
        case .databaseIsNotARegularFile(let path):
            return "Build-validation database is not a regular file: \(path)"
        case .databaseHasSidecar(let path):
            return "Build-validation snapshot has an adjacent SQLite sidecar and is not immutable: \(path)"
        case .databaseChangedDuringValidation(
            let initialByteCount,
            let initialSHA256,
            let finalByteCount,
            let finalSHA256
        ):
            return "Build-validation snapshot changed during validation: initial byte count \(initialByteCount), SHA-256 \(initialSHA256); final byte count \(finalByteCount), SHA-256 \(finalSHA256)."
        }
    }
}
