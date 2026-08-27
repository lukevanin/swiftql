//
//  GRDBDatabase+StaticQueryValidation.swift
//  SwiftQL
//
//  Confirming that a statement's parameters, codecs, and storage classes belong
//  to this database's immutable coding snapshot before anything is prepared.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


extension GRDBDatabase {

    /// Confirms that every contextual parameter retained by the rendered
    /// statement belongs to this database's immutable coding snapshot. A
    /// reference resolved by another database is accepted only when the same
    /// durable codec identity is registered for the same dialect.
    func preparedParameterLayoutError(
        for encoding: XLEncoding
    ) -> XLInvocationBindingError? {
        if let parameterLayoutError = encoding.parameterLayoutError {
            return parameterLayoutError
        }

        for slot in encoding.parameterLayout.slots {
            if let failure = codecResolutionFailure(for: slot.codecIdentity) {
                return failure.bindingError(
                    slot: slot,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
        }
        return nil
    }

    ///
    /// Why a slot's declared codec cannot be used against this database, or
    /// `nil` when it can be -- including when the slot declares no codec.
    ///
    /// The resolution is one question asked in three places: on the rendered
    /// parameter layout, on a static descriptor's parameters, and on its
    /// results. Each reports it in a different taxonomy -- the first as an
    /// `XLInvocationBindingError` returned rather than thrown, the second as
    /// the same error thrown, the third as a `GRDBStaticQueryError` naming the
    /// descriptor -- which is why they were three copies (issue #561). The
    /// answer is shared; only the reporting differs.
    ///
    func codecResolutionFailure(
        for codecIdentity: XLValueCodecIdentity?
    ) -> GRDBCodecResolutionFailure? {
        guard let expected = codecIdentity else {
            return nil
        }
        guard expected.dialectIdentifier == dialect.descriptor.identity else {
            return .dialectMismatch(expected)
        }
        guard let actual = codingConfiguration.registry.identity(
            for: expected.key
        ) else {
            return .unavailable(expected)
        }
        guard actual == expected else {
            return .identityMismatch(expected: expected, actual: actual)
        }
        return nil
    }

    func validateStaticQueryCodecs(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for metadata in descriptor.parameters {
            let slot = metadata.slot
            if let failure = codecResolutionFailure(for: slot.codecIdentity) {
                throw failure.bindingError(
                    slot: slot,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
        }

        for slot in descriptor.results.slots {
            if let failure = codecResolutionFailure(for: slot.codecIdentity) {
                throw failure.staticQueryError(
                    identity: descriptor.identity,
                    slot: slot,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
        }
    }

    func validateStaticQueryStorage(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for parameter in descriptor.parameters {
            guard XLSQLiteStorageClass(
                rawValue: parameter.storageIdentifier.rawValue
            ) != nil else {
                throw GRDBStaticQueryError.unsupportedParameterStorage(
                    identity: descriptor.identity,
                    parameter: parameter
                )
            }
        }

        for slot in descriptor.results.slots {
            guard XLSQLiteStorageClass(
                rawValue: slot.storageIdentifier.rawValue
            ) != nil else {
                throw GRDBStaticQueryError.unsupportedResultStorage(
                    identity: descriptor.identity,
                    slot: slot
                )
            }
        }
    }

    func logicalStatement(for encoding: XLEncoding) -> XLLogicalPreparedStatement {
        XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: encoding.dialectRequirement,
            sql: encoding.sql,
            entities: encoding.entities,
            parameterLayout: encoding.parameterLayout
        )
    }
}
