//
//  SQLStaticQueryDescriptor+Encoding.swift
//  SwiftQL
//
//  Bridging from a rendered `XLEncoding` to the database-independent static
//  descriptor types, which live in SwiftQLCore.
//
//  Renamed from `SQLStaticQueryDescriptor.swift` (issue #555): the old name
//  promised the descriptor types themselves, and this file holds neither --
//  only the two extensions that build one.
//

import Foundation


extension XLStaticStatementDefinition {

    /// Creates a database-independent static statement from one validated SQL
    /// rendering.
    ///
    /// The SwiftQL expression graph is deliberately discarded here. Static
    /// descriptors retain only deterministic SQL, dialect requirements,
    /// referenced entities, immutable parameter metadata, and the signatures of
    /// the functions SwiftQL bundles.
    ///
    /// A registration in `encoding.customFunctions` is a live closure, not
    /// deterministic metadata, so it cannot survive into a database-independent
    /// descriptor. A *signature* can, and SwiftQL can rebuild its own
    /// implementation from one, so the bundled functions the statement calls are
    /// recorded in `XLStaticStatementDefinition.bundledFunctions` and
    /// registered when the descriptor is prepared (issue #615).
    ///
    /// An application's own custom function is still dropped: SwiftQL cannot
    /// rebuild an implementation it did not write. Such a statement has to have
    /// it registered upfront with `GRDBDatabaseBuilder.addFunction(_:)` to be
    /// executed as a static descriptor.
    public init(validating encoding: XLEncoding) throws {
        if let valueEncodingError = encoding.valueEncodingError {
            throw valueEncodingError
        }
        if let parameterLayoutError = encoding.parameterLayoutError {
            throw parameterLayoutError
        }
        self.init(
            sql: encoding.sql,
            dialectRequirement: encoding.dialectRequirement,
            entities: encoding.entities,
            parameterLayout: encoding.parameterLayout,
            bundledFunctions: Set(
                encoding.customFunctions.keys.filter { definition in
                    XLCustomFunctionRegistration.bundled[definition] != nil
                }
            )
        )
    }
}


extension XLContextualBindingReference {

    /// Describes this contextual parameter in a static query after rendering
    /// has assigned its deterministic logical index.
    public func staticQueryParameter(
        identity: XLQuerySlotIdentity,
        in layout: XLParameterLayout
    ) throws -> XLStaticQueryParameterMetadata {
        let parameter = try preparedParameter(in: layout)
        return XLStaticQueryParameterMetadata(
            identity: identity,
            slot: parameter.slot,
            storageIdentifier: parameter.codecIdentity.storageIdentifier
        )
    }
}
