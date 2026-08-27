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
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                return .preparedCodecDialectMismatch(
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                return .preparedCodecUnavailable(
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                return .preparedCodecIdentityMismatch(
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }
        return nil
    }

    func validateStaticQueryCodecs(
        _ descriptor: XLStaticQueryDescriptor
    ) throws {
        for metadata in descriptor.parameters {
            let slot = metadata.slot
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                throw XLInvocationBindingError.preparedCodecDialectMismatch(
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                throw XLInvocationBindingError.preparedCodecUnavailable(
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                throw XLInvocationBindingError.preparedCodecIdentityMismatch(
                    slot: slot,
                    expected: expected,
                    actual: actual
                )
            }
        }

        for slot in descriptor.results.slots {
            guard let expected = slot.codecIdentity else {
                continue
            }
            guard expected.dialectIdentifier == dialect.descriptor.identity else {
                throw GRDBStaticQueryError.resultCodecDialectMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    codecIdentity: expected,
                    expectedDialectIdentifier: dialect.descriptor.identity
                )
            }
            guard let actual = codingConfiguration.registry.identity(
                for: expected.key
            ) else {
                throw GRDBStaticQueryError.resultCodecUnavailable(
                    identity: descriptor.identity,
                    slot: slot,
                    codecIdentity: expected
                )
            }
            guard actual == expected else {
                throw GRDBStaticQueryError.resultCodecIdentityMismatch(
                    identity: descriptor.identity,
                    slot: slot,
                    expected: expected,
                    actual: actual
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
