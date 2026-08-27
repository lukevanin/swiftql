import Foundation
import SwiftQLCore
import SwiftQLSQLiteBuildValidationManifest

//
//  Resolving a query's declared capability requirements against the evidence
//  captured from the validator's connection.
//
//  Split out of SQLiteBuildValidator.swift (#566). Classification of a
//  capability identifier now lives in one place, `CapabilityKind`; it used to
//  be written out three times over, with the same prefixes and the same case
//  folding repeated in each.
//

extension SQLiteBuildValidator {

    /// Dialect-level requirements: that the query is SQLite at all, that the
    /// connection's SQLite is new enough, and that every dialect capability bit
    /// the descriptor asks for is one SwiftQL's SQLite dialect provides.
    static func dialectDiagnostics(
        query: SQLiteBuildValidationQueryEntry,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
    ) -> [SQLiteBuildValidationDiagnostic] {
        var diagnostics: [SQLiteBuildValidationDiagnostic] = []
        if query.dialectIdentifier != XLSQLiteDialect.identity.rawValue {
            diagnostics.append(SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .capability,
                code: .capabilityDialect,
                message: "Descriptor requires dialect '\(query.dialectIdentifier)'; this validator validates SQLite only.",
                query: query
            ))
        }

        if let requiredVersion = query.minimumDialectVersion {
            guard let actualVersion = runtimeMetadata?.sqliteVersion else {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .unsupported,
                    stage: .capability,
                    code: .capabilitySQLiteVersion,
                    message: "SQLite \(requiredVersion) or newer is required, but runtime identity is unavailable.",
                    query: query
                ))
                return diagnostics
            }
            if !version(actualVersion, isAtLeast: requiredVersion) {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .unsupported,
                    stage: .capability,
                    code: .capabilitySQLiteVersion,
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
                code: .capabilityDialectFlags,
                message: "Descriptor requires unsupported dialect capability bits \(unavailable).",
                query: query
            ))
        }
        return diagnostics
    }

    /// One `unsupported` diagnostic per required capability the connection does
    /// not provide.
    ///
    /// A capability the validator cannot observe at all is the one case a
    /// caller can settle: they may legitimately own it, and its absence can
    /// never be proven from a SQLite connection, so an explicit declaration in
    /// the environment satisfies it. An *observable* capability is never
    /// satisfied that way -- otherwise declaring `function:JSON_VALID` would
    /// spoof a function the connection does not have.
    static func capabilityDiagnostics(
        query: SQLiteBuildValidationQueryEntry,
        runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?,
        environment: SQLiteBuildValidationEnvironment
    ) -> [SQLiteBuildValidationDiagnostic] {
        let explicitCapabilities = Set(environment.capabilityIDs)
        return query.requiredCapabilities.compactMap { requirement in
            let (kind, name) = CapabilityKind.classify(requirement.id)
            let isSatisfied = capability(
                kind: kind,
                name: name,
                isAvailableIn: runtimeMetadata
            ) || (!kind.isObservable
                && explicitCapabilities.contains(requirement.id))
            guard !isSatisfied else {
                return nil
            }
            return SQLiteBuildValidationDiagnostic(
                verdict: .unsupported,
                stage: .capability,
                code: kind.diagnosticCode,
                message: "Required capability '\(requirement.id)' is unavailable on the validator connection.",
                query: query
            )
        }
    }

    /// Whether the captured runtime evidence shows this capability present.
    ///
    /// With no evidence captured nothing is available, including the intrinsic
    /// capabilities: a run whose runtime capture failed has already reported
    /// that failure, and claiming availability from a connection it could not
    /// read would be an assertion rather than evidence.
    static func capability(
        kind: CapabilityKind,
        name: String?,
        isAvailableIn runtimeMetadata: SQLiteBuildValidationRuntimeMetadata?
    ) -> Bool {
        guard let runtimeMetadata else {
            return false
        }
        switch kind {
        case .function:
            return name.map { runtimeMetadata.hasFunction(named: $0) } ?? false
        case .collation:
            return name.map { runtimeMetadata.hasCollation(named: $0) } ?? false
        case .compileOption:
            return name.map { runtimeMetadata.hasCompileOption($0) } ?? false
        case .module:
            return name.map { runtimeMetadata.hasModule(named: $0) } ?? false
        case .loadedExtension:
            return name.map { runtimeMetadata.hasExtension(named: $0) } ?? false
        case .sqliteJSONFunctions:
            return runtimeMetadata.hasFunction(named: "JSON_VALID")
        case .intrinsic:
            return true
        case .opaque:
            return false
        }
    }

    /// Compares dotted SQLite version strings component by component.
    ///
    /// Numeric, not lexicographic: `3.9.0` is older than `3.10.0`, which a
    /// string comparison gets backwards.
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
