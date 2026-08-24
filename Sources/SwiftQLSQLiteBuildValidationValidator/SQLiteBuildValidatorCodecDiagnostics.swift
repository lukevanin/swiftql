import Foundation
import SwiftQLSQLiteBuildValidationManifest

//
//  Codec conformance: that a slot's declared codec agrees with the slot it
//  codes for, and that every codec the query needs was supplied.
//
//  Split out of SQLiteBuildValidator.swift (#566).
//

extension SQLiteBuildValidator {

    static func codecDiagnostics(
        query: SQLiteBuildValidationQueryEntry,
        environment: SQLiteBuildValidationEnvironment
    ) -> [SQLiteBuildValidationDiagnostic] {
        struct Slot {
            let identity: String
            let valueTypeIdentifier: String
            let storageIdentifier: String
            let codec: SQLiteBuildValidationCodecReference
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
                    code: .codecValueType,
                    message: "Slot '\(slot.identity)' value type '\(slot.valueTypeIdentifier)' does not match codec value type '\(slot.codec.valueTypeIdentifier)'.",
                    query: query
                ))
            }
            if slot.codec.dialectIdentifier != query.dialectIdentifier {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .codec,
                    code: .codecDialect,
                    message: "Slot '\(slot.identity)' codec dialect '\(slot.codec.dialectIdentifier)' does not match query dialect '\(query.dialectIdentifier)'.",
                    query: query
                ))
            }
            if slot.codec.storageIdentifier != slot.storageIdentifier {
                diagnostics.append(SQLiteBuildValidationDiagnostic(
                    verdict: .failed,
                    stage: .codec,
                    code: .codecStorage,
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
                code: .codecMissing,
                message: "Required codec '\(identifier)' was not supplied to the validator environment.",
                query: query
            ))
        }
        return diagnostics
    }
}
